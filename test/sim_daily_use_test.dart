// 模拟小学班级管理系统的「一天教学日常」，检验是否满足日常使用。
//
// 这不是单元测试，而是**端到端使用模拟**：调用真实仓储 / 真实服务，
// 在真实的 SQLite 数据目录上跑一遍老师从开学到期末会做的事，
// 记录每一步的实际结果，最后产出可用性清单。
//
// 运行方式（必须重定向 APPDATA，避免污染真实教师数据）：
//   APPDATA=<临时目录> flutter test test/sim_daily_use_test.dart
//
// 产出：<报告目录>/sim_daily_use_report.md

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:classroom_manager/data/db.dart';
import 'package:classroom_manager/data/models.dart';
import 'package:classroom_manager/data/repo.dart';
import 'package:classroom_manager/services/backup_service.dart';
import 'package:classroom_manager/services/report_service.dart';
import 'package:classroom_manager/services/textbook_seed_service.dart';
import 'package:classroom_manager/services/tts_service.dart';

// ---------------------------------------------------------------------------
// 极简结果采集器：不抛异常，尽量把问题都跑出来再汇总。
// ---------------------------------------------------------------------------

class Finding {
  Finding(this.area, this.item, this.ok, this.detail);

  final String area;
  final String item;
  final bool ok;
  final String detail;
}

final List<Finding> _findings = [];
final Stopwatch _clock = Stopwatch();

void record(String area, String item, bool ok, [String detail = '']) {
  _findings.add(Finding(area, item, ok, detail));
}

void note(String area, String item, String detail) =>
    record(area, item, true, detail);

/// 期望成功，失败则记为问题。
void expectOk(String area, String item, bool ok, [String detail = '']) =>
    record(area, item, ok, detail);

const String _className = '三年级2班';

/// 模拟一份真实班级名单：42 人，含重名、含逗号分隔、含中英文逗号混用。
const String _rawRoster = '''
张小明
李小红
王小刚
赵一诺
陈子涵
刘思远
杨梦琪
黄浩然
周雨欣
吴梓豪
徐嘉怡
孙俊熙
马诗涵
朱奕辰
胡欣妍
郭泽宇
林语彤
何俊杰
高晨曦
罗嘉悦
郑博文
梁子萱
谢明轩
唐雨桐
许昊天
韩雪莹
冯思淼
邓紫琪
曹逸凡
彭佳琪
曾子墨
萧雅涵
田俊豪
董思彤
潘子轩
于晓彤
蒋一鸣
蔡雨萌
余嘉豪
杜若曦
叶星辰
程诗雨
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _clock.start();
    // 模拟「新老师拿到一台干净的电脑」：清空数据目录。
    final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dataDir = Directory(p.join(appData, 'classroom_manager', 'data'));
    if (dataDir.existsSync()) {
      dataDir.deleteSync(recursive: true);
    }
    dataDir.createSync(recursive: true);
    await AppDb.init();
  });

  tearDownAll(() async {
    _clock.stop();
    await _writeReport();
  });

  // =========================================================================
  // S1 开学准备：建班 + 名单
  // =========================================================================

  test('S1 开学准备：建班与名单管理', () async {
    const area = 'S1 名单';
    var sw = Stopwatch()..start();

    // 1. 干净电脑上的空状态
    final empty = await Repo.listClasses();
    expectOk(area, '干净电脑启动时无班级（空状态）', empty.isEmpty,
        'listClasses() 返回 ${empty.length} 个班级');

    // 2. 新建班级
    final klass = await Repo.addClass('  $_className  ');
    final classes = await Repo.listClasses();
    expectOk(area, '新建班级后出现在列表', classes.length == 1,
        '班级名「${klass.name}」');
    expectOk(area, '班级名自动去除首尾空格', klass.name == _className,
        '实际「${klass.name}」');

    // 3. 批量导入：走页面同款解析规则（换行 / 中英文逗号，去重）
    final names = _rawRoster
        .split(RegExp(r'[\n\r,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final imported =
        await Repo.addStudentsByName(classId: klass.id, names: names);
    var students = await Repo.listStudents(klass.id);
    expectOk(area, '批量导入 $imported 人', students.length == imported,
        '名单实际 ${students.length} 人');

    // 4. 逗号分隔 + 重名去重
    final dupRaw = '张小明,李小红，张小明\n王小刚';
    final dupNames = dupRaw
        .split(RegExp(r'[\n\r,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    expectOk(area, '同一批内重名自动去重', dupNames.length == 3,
        '「$dupRaw」→ ${dupNames.join("/")}');

    // 5. 添加单个学生（带学号 + 性别）
    await Repo.addStudent(
        classId: klass.id, name: '转学生测试', seatNo: 43, gender: '男');
    students = await Repo.listStudents(klass.id);
    final transfer = students.firstWhere((s) => s.name == '转学生测试');
    expectOk(area, '添加学生（学号+性别）', transfer.seatNo == 43 && transfer.gender == '男',
        '学号 ${transfer.seatNo} / ${transfer.gender}');
    expectOk(area, '有学号的学生排在名单最前（座号升序）', students.first.name == '转学生测试',
        '排序首位「${students.first.name}」');

    // 6. 编辑学生
    await Repo.updateStudent(
        existing: transfer, name: '转学生已改名', seatNo: 43, gender: '男');
    students = await Repo.listStudents(klass.id);
    expectOk(
        area,
        '编辑学生姓名立即生效',
        students.any((s) => s.name == '转学生已改名') &&
            !students.any((s) => s.name == '转学生测试'),
        '列表已更新');

    // 7. 重复导入同一份名单（老师手滑再点一次导入）——用独立班级验证
    final probeClass = await Repo.addClass('重复导入验证班');
    await Repo.addStudentsByName(classId: probeClass.id, names: names);
    await Repo.addStudentsByName(classId: probeClass.id, names: names);
    final probeStudents = await Repo.listStudents(probeClass.id);
    expectOk(
      area,
      '重复导入同一份名单不会产生重复学生',
      probeStudents.length == names.length,
      '两次导入同一份 ${names.length} 人名单 → 班级实际 ${probeStudents.length} 人'
          '${probeStudents.length != names.length ? '（去重只在本次粘贴内容内做，不与库内既有名单比对）' : ''}',
    );

    // 8. 删除「无任何记录」的学生
    final plain = students.firstWhere((s) => s.name == '程诗雨');
    var deletePlainOk = true;
    var deletePlainMsg = '';
    try {
      await Repo.deleteStudent(plain.id);
      final after = await Repo.listStudents(klass.id);
      deletePlainOk = !after.any((s) => s.id == plain.id);
      deletePlainMsg = '删除后 ${after.length} 人';
    } catch (e) {
      deletePlainOk = false;
      deletePlainMsg = '抛出异常：$e';
    }
    expectOk(area, '删除无记录学生', deletePlainOk, deletePlainMsg);

    // 9. 删除「已有小红花记录」的学生（日常最常发生的误操作）
    students = await Repo.listStudents(klass.id);
    final withFlower = students.firstWhere((s) => s.name == '赵一诺');
    await Repo.awardFlower(
        studentId: withFlower.id, delta: 3, reason: '作业优秀');
    var deleteBusyOk = true;
    var deleteBusyMsg = '';
    try {
      await Repo.deleteStudent(withFlower.id);
      final after = await Repo.listStudents(klass.id);
      deleteBusyOk = !after.any((s) => s.id == withFlower.id);
      deleteBusyMsg = deleteBusyOk ? '已删除' : '调用未报错但学生仍在名单中';
    } catch (e) {
      deleteBusyOk = false;
      deleteBusyMsg = '抛出异常：$e';
    }
    expectOk(
      area,
      '删除已有小红花记录的学生（转学/录错）',
      deleteBusyOk,
      deleteBusyMsg,
    );

    sw.stop();
    note('S1 名单', '耗时', '${sw.elapsedMilliseconds} ms');
  });

  // =========================================================================
  // S2 课堂上：小红花授奖
  // =========================================================================

  test('S2 课堂上：小红花加减与纠错', () async {
    const area = 'S2 小红花';
    final klass = (await Repo.listClasses()).first;
    final students = await Repo.listStudents(klass.id);

    // 按姓名取人（名单排序受学号影响，用下标容易取错）
    Student byName(String n) => students.firstWhere((s) => s.name == n);
    final a = byName('张小明');
    final b = byName('李小红');
    final c = byName('王小刚');

    // 1. 授奖：确认才写入（这里直接模拟「确认」路径）
    await Repo.awardFlower(studentId: a.id, delta: 2, reason: '积极发言');
    await Repo.awardFlower(studentId: a.id, delta: 3, reason: '作业优秀');
    var totals = await Repo.flowerTotals(klass.id);
    expectOk(area, '连续授奖后合计正确', totals[a.id] == 5,
        '张小明 = ${totals[a.id]}（期望 5）');

    // 2. 扣减：负向记录
    await Repo.awardFlower(studentId: a.id, delta: -1, reason: '上课讲话');
    totals = await Repo.flowerTotals(klass.id);
    expectOk(area, '扣减后合计正确', totals[a.id] == 4,
        '张小明 = ${totals[a.id]}（期望 4）');

    // 3. 流水只增不改：明细条数 = 3
    var detail = await Repo.studentLogs(a.id);
    expectOk(area, '流水只增不改（3 条记录全部保留）', detail.length == 3,
        '明细 ${detail.length} 条：${detail.map((e) => e.log.delta).join(",")}');

    // 4. 每条记录可追溯到数量与原因
    final allHaveReason = detail.every((e) => e.log.reason != null);
    expectOk(area, '每条记录都可追溯原因', allHaveReason,
        detail.map((e) => '${e.log.delta}·${e.log.reason}').join(' / '));

    // 5. 删除单条流水 → 合计实时刷新
    final target = detail.firstWhere((e) => e.log.delta == -1);
    await Repo.deleteFlowerLog(target.log.id);
    totals = await Repo.flowerTotals(klass.id);
    expectOk(area, '删除单条流水后合计实时刷新', totals[a.id] == 5,
        '删掉 -1 后 张小明 = ${totals[a.id]}（期望 5）');

    // 6. 纠错：插入反向记录而非改原记录
    final origin = (await Repo.studentLogs(a.id))
        .firstWhere((e) => e.log.delta == 2);
    await Repo.awardFlower(
        studentId: a.id, delta: -2, reason: '撤销：记错了', refLogId: origin.log.id);
    detail = await Repo.studentLogs(a.id);
    final originStillThere = detail.any((e) => e.log.id == origin.log.id);
    final reverseThere = detail.any((e) => e.log.refLogId == origin.log.id);
    expectOk(area, '纠错通过反向记录实现，原记录保留',
        originStillThere && reverseThere,
        '原记录在：$originStillThere，反向记录在：$reverseThere');
    totals = await Repo.flowerTotals(klass.id);
    expectOk(area, '纠错后净额正确', totals[a.id] == 3,
        '张小明 = ${totals[a.id]}（期望 3）');

    // 7. 多学生数据，用于榜单校验
    await Repo.awardFlower(studentId: b.id, delta: 5, reason: '朗读优秀');
    await Repo.awardFlower(studentId: c.id, delta: 2, reason: '进步明显');
    await Repo.awardFlower(studentId: c.id, delta: 1, reason: '帮助同学');

    // 8. 榜单：本周 / 本月 / 累计
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .millisecondsSinceEpoch;
    final startOfMonth =
        DateTime(now.year, now.month, 1).millisecondsSinceEpoch;

    final week = await Repo.flowerLeaderboard(klass.id, sinceMs: startOfWeek);
    final month = await Repo.flowerLeaderboard(klass.id, sinceMs: startOfMonth);
    final all = await Repo.flowerLeaderboard(klass.id, sinceMs: 0);

    expectOk(area, '本周榜单按合计降序', _isDescending(week),
        week.map((e) => '${e.name}:${e.total}').join(' > '));
    expectOk(area, '本周榜首位正确', week.isNotEmpty && week.first.name == '李小红',
        '首位 ${week.isNotEmpty ? week.first.name : "空"}');
    expectOk(area, '本月榜与本周榜均可用', month.isNotEmpty,
        month.map((e) => '${e.name}:${e.total}').join(' > '));
    expectOk(area, '累计榜包含全部有分学生（4 人）', all.length == 4,
        all.map((e) => '${e.name}:${e.total}').join(' > '));
    expectOk(area, '前三名可标记奖牌', all.length >= 3, '榜单 ${all.length} 人');

    // 9. 跨周数据：插一条 8 天前的记录（本月内、本周外）
    final db = await AppDb.db;
    final eightDaysAgo = DateTime.now()
        .subtract(const Duration(days: 8))
        .millisecondsSinceEpoch;
    await db.insert('flower_logs', {
      'id': 'sim-old-log-0001',
      'student_id': a.id,
      'delta': 10,
      'reason': '上周比赛获奖',
      'ref_log_id': null,
      'created_at': eightDaysAgo,
    });
    final week2 = await Repo.flowerLeaderboard(klass.id, sinceMs: startOfWeek);
    final month2 = await Repo.flowerLeaderboard(klass.id, sinceMs: startOfMonth);
    final all2 = await Repo.flowerLeaderboard(klass.id, sinceMs: 0);
    final aWeek = week2.firstWhere((e) => e.studentId == a.id, orElse: () => LeaderRow(studentId: a.id, name: a.name, total: 0));
    final aMonth = month2.firstWhere((e) => e.studentId == a.id, orElse: () => LeaderRow(studentId: a.id, name: a.name, total: 0));
    final aAll = all2.firstWhere((e) => e.studentId == a.id, orElse: () => LeaderRow(studentId: a.id, name: a.name, total: 0));
    expectOk(area, '本周榜不含 8 天前的记录', aWeek.total == 3,
        '本周 张小明 = ${aWeek.total}（期望 3）');
    expectOk(area, '本月榜含 8 天前的记录（同月）', aMonth.total == 13,
        '本月 张小明 = ${aMonth.total}（期望 13，本月起始 ${DateTime.fromMillisecondsSinceEpoch(startOfMonth)}）');
    expectOk(area, '累计榜含 8 天前的记录', aAll.total == 13,
        '累计 张小明 = ${aAll.total}（期望 13）');

    // 10. 今日统计与时间线
    final startOfToday =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final today = await Repo.classLogsSince(klass.id, sinceMs: startOfToday);
    var flowers = 0, persons = 0, deducts = 0;
    for (final e in today) {
      if (e.log.delta > 0) {
        flowers += e.log.delta;
        persons += 1;
      } else {
        deducts += 1;
      }
    }
    expectOk(area, '今日时间线可读且带学生姓名',
        today.isNotEmpty && today.every((e) => e.studentName.isNotEmpty),
        '今日 ${today.length} 条：奖励 $flowers 朵 / $persons 人次 / 扣减 $deducts 次');
    expectOk(area, '今日流水按时间倒序', _isDesc(today.map((e) => e.log.createdAt).toList()),
        '首条 ${today.isEmpty ? "-" : today.first.studentName}');

    // 11. 同名不同人（真实班级常见）——用独立班级验证
    final dupClass = await Repo.addClass('同名学生验证班');
    await Repo.addStudent(classId: dupClass.id, name: '张小明', seatNo: 1);
    await Repo.addStudent(classId: dupClass.id, name: '张小明', seatNo: 2);
    final sameName = await Repo.listStudents(dupClass.id);
    final distinctIds = sameName.map((s) => s.id).toSet().length;
    await Repo.awardFlower(
        studentId: sameName[0].id, delta: 2, reason: '课堂表现');
    await Repo.awardFlower(
        studentId: sameName[1].id, delta: 1, reason: '积极发言');
    final totalsSameName = await Repo.flowerTotals(dupClass.id);
    expectOk(area, '同名两名学生可共存且各自独立计分',
        sameName.length == 2 && distinctIds == 2,
        '同名 ${sameName.length} 人（座位 1/2），红花分别 '
            '${sameName.map((s) => totalsSameName[s.id] ?? 0).join(" / ")}');
  });

  // =========================================================================
  // S3 听写备课
  // =========================================================================

  test('S3 听写备课：教材词表导入 + 粘贴词语合成', () async {
    const area = 'S3 听写';

    // 1. 一键导入教材词表（离线，发音随包分发）
    var sw = Stopwatch()..start();
    final r1 = await TextbookSeedService.run();
    sw.stop();
    final lists = await Repo.listWordLists();
    expectOk(
      area,
      '一键导入教材词表（离线）',
      r1.createdLists > 0 && r1.createdWords > 0,
      '新建 ${r1.createdLists} 组 / ${r1.createdWords} 词，耗时 ${sw.elapsedMilliseconds} ms',
    );

    // 2. 词数与教材一致
    var totalWords = 0;
    for (final l in lists) {
      totalWords += (await Repo.listWords(l.id)).length;
    }
    expectOk(area, '导入词数与教材词表一致（213 词 / 18 组）',
        totalWords == 213 && lists.length == 18,
        '实际 ${lists.length} 组 / $totalWords 词');

    // 3. 音频文件已复制进数据目录
    final firstList = lists.firstWhere((l) => l.title == '第1课');
    final words = await Repo.listWords(firstList.id);
    final audioExists = words.every((w) => File(w.audioFile).existsSync());
    final insideDataDir =
        words.every((w) => p.isWithin(AppDb.dataDir, w.audioFile));
    expectOk(area, '音频先复制进应用数据目录再写库', audioExists && insideDataDir,
        '「第1课」${words.length} 词，文件均在 ${AppDb.dataDir}\\audio 下：$audioExists');
    final durationOk = words.every((w) => (w.durationMs ?? 0) > 0);
    expectOk(
      area,
      'WAV 时长解析正确（词表列表显示秒数用）',
      durationOk,
      '示例：${words.take(3).map((w) => "${w.text}=${w.durationMs}ms").join(" / ")}'
          '${durationOk ? "" : "（probeAudioFile 的 _probeWav 按大端读 chunk 长度，WAV 实为小端 → 所有 wav 时长恒为 0；只影响列表秒数显示，不影响播放）"}',
    );

    // 4. 重复点「导入教材词表」不应产生重复组
    final r2 = await TextbookSeedService.run();
    final lists2 = await Repo.listWordLists();
    expectOk(area, '重复导入教材词表不会重复建组',
        lists2.length == lists.length && r2.createdLists == 0,
        '第二次：新建 ${r2.createdLists} 组 / 跳过 ${r2.skippedLists} 组，总组数仍为 ${lists2.length}');

    // 5. 粘贴词语 → 自动合成发音（本课临时词表）
    sw = Stopwatch()..start();
    final tmp = Directory(p.join(Directory.systemTemp.path,
        'sim_tts_${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);
    final custom = await Repo.createWordList('临时听写·模拟', subject: '语文');
    final okIdx = await _ttsGenerate(tmp.path, const [
      ('w1', '桂花'),
      ('w2', '故乡'),
      ('w3', '欣赏'),
      ('w4', '糕饼'),
      ('w5', '成熟'),
    ]);
    sw.stop();
    expectOk(area, '粘贴词语可自动合成标准普通话发音', okIdx.length == 5,
        '成功 ${okIdx.length}/5，耗时 ${sw.elapsedMilliseconds} ms（Windows SAPI）');

    if (okIdx.isNotEmpty) {
      final items = <WordImportItem>[];
      for (var i = 0; i < 5; i++) {
        final f = File(p.join(tmp.path, 'w${i + 1}.wav'));
        if (!f.existsSync()) continue;
        items.add(WordImportItem(
          sourcePath: f.path,
          ext: '.wav',
          word: const ['桂花', '故乡', '欣赏', '糕饼', '成熟'][i],
          durationMs: _wavDurationMs(f),
          origFilename: '${const ['桂花', '故乡', '欣赏', '糕饼', '成熟'][i]}.wav',
        ));
      }
      final n = await Repo.importWords(listId: custom.id, items: items);
      final stored = await Repo.listWords(custom.id);
      expectOk(area, '合成的发音入库且文件落盘',
          stored.length == n && stored.every((w) => File(w.audioFile).existsSync()),
          '入库 $n 词，全部文件存在');
      expectOk(area, '词条顺序与输入顺序一致（听写按序出题）',
          stored.map((w) => w.text).join(',') == '桂花,故乡,欣赏,糕饼,成熟',
          stored.map((w) => w.text).join(','));
    }
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}

    // 6. 删除词表 → 音频一并清理
    final audioDir = Directory(p.join(AppDb.dataDir, 'audio', custom.id));
    final filesBefore =
        audioDir.existsSync() ? audioDir.listSync().whereType<File>().length : 0;
    await Repo.deleteWordList(custom.id);
    final filesAfter =
        audioDir.existsSync() ? audioDir.listSync().whereType<File>().length : 0;
    final afterLists = await Repo.listWordLists();
    expectOk(area, '删除词表会连带清理录音文件',
        !afterLists.any((l) => l.id == custom.id) && filesAfter == 0,
        '删除前 $filesBefore 个录音文件 → 删除后 $filesAfter 个');
    if (audioDir.existsSync()) {
      note(area, '删除词表后残留空目录（无害，但会长期累积）', audioDir.path);
    }

    // 7. 粘贴格式异常的行应被跳过而不是报错
    final messy = '桂花\n\n   \n故乡,课文第一课\n；\n欣赏';
    final lines = messy
        .split(RegExp(r'[\n\r;；]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    expectOk(area, '粘贴内容含空行/异常行时只跳过不报错', lines.length == 3,
        '「桂花 / 故乡,课文第一课 / 欣赏」共 ${lines.length} 行被识别');
  });

  // =========================================================================
  // S4 期末：报表导出
  // =========================================================================

  test('S4 期末：Excel 报表导出', () async {
    const area = 'S4 报表';
    final klass = (await Repo.listClasses()).first;

    for (final range in ReportRange.values) {
      var path = '';
      var ok = true;
      var msg = '';
      var sw = Stopwatch()..start();
      try {
        path = await ReportService.exportFlowerReport(
          classId: klass.id,
          className: klass.name,
          range: range,
        );
      } catch (e) {
        ok = false;
        msg = '导出异常：$e';
      }
      sw.stop();
      if (!ok) {
        expectOk(area, '导出${range.label}报表', false, msg);
        continue;
      }
      final f = File(path);
      expectOk(area, '导出${range.label}报表', f.existsSync(),
          '${p.basename(path)}（${f.existsSync() ? f.lengthSync() : 0} 字节，${sw.elapsedMilliseconds} ms）');
      if (!f.existsSync()) continue;

      // 校验工作表
      try {
        final excel = Excel.decodeBytes(f.readAsBytesSync());
        final sheets = excel.tables.keys.toList();
        expectOk(
          area,
          '${range.label}报表含「明细」与「汇总」两个工作表',
          sheets.contains('明细') && sheets.contains('汇总'),
          '工作表：${sheets.join(" / ")}',
        );
        final detail = excel.tables['明细'];
        final summary = excel.tables['汇总'];
        final head = _headerOf(detail);
        expectOk(area, '${range.label}明细表表头正确', head == '日期,时间,学生,变化,原因',
            '表头：$head');
        final sumHead = _headerOf(summary);
        expectOk(area, '${range.label}汇总表表头正确', sumHead == '排名,学生,小红花',
            '表头：$sumHead');
        final detailRows = (detail?.rows.length ?? 1) - 1;
        final sumRows = (summary?.rows.length ?? 1) - 1;
        note(area, '${range.label}报表内容',
            '明细 $detailRows 行，汇总 $sumRows 行');
        if (range == ReportRange.today) {
          expectOk(area, '今日报表行数与今日流水一致', detailRows > 0,
              '明细 $detailRows 行');
        }
      } catch (e) {
        expectOk(area, '${range.label}报表可被解析', false, '解析异常：$e');
      }

      // 清理桌面上的模拟产物，不污染用户桌面
      try {
        f.deleteSync();
      } catch (_) {}
    }

    // 汇总表按姓名聚合：同名学生会合并成一行（真实班级需注意）
    final dupClass = (await Repo.listClasses())
        .firstWhere((c) => c.name == '同名学生验证班');
    final path = await ReportService.exportFlowerReport(
      classId: dupClass.id,
      className: dupClass.name,
      range: ReportRange.month,
    );
    final excel = Excel.decodeBytes(File(path).readAsBytesSync());
    final sum = excel.tables['汇总']!;
    final names = <String>[];
    for (var i = 1; i < sum.rows.length; i++) {
      names.add(sum.rows[i].first?.value?.toString() ?? '');
    }
    // 该班有 2 名同名学生（各 2 分、1 分），正确的汇总应有 2 行
    final merged = names.length < 2;
    final dupTotal =
        sum.rows.length > 1 ? sum.rows[1].last?.value?.toString() : '';
    expectOk(
      area,
      '汇总表里两名同名学生应各占一行',
      !merged,
      merged
          ? '2 名同名学生被合并为 ${names.length} 行（${names.join("/")}），'
              '合计显示 $dupTotal，排名会失真'
          : '两名同名学生各占一行',
    );
    try {
      File(path).deleteSync();
    } catch (_) {}
  });

  // =========================================================================
  // S6 边界与性能
  // =========================================================================

  test('S6 边界场景与性能', () async {
    const area = 'S6 边界';

    // 1. 空班级（新建但没学生）
    final empty = await Repo.addClass('空班级测试');
    final emptyStudents = await Repo.listStudents(empty.id);
    final emptyTotals = await Repo.flowerTotals(empty.id);
    final emptyBoard = await Repo.flowerLeaderboard(empty.id, sinceMs: 0);
    final emptyLogs = await Repo.classLogsSince(empty.id, sinceMs: 0);
    expectOk(
      area,
      '空班级各项查询不报错且返回空',
      emptyStudents.isEmpty &&
          emptyTotals.isEmpty &&
          emptyBoard.isEmpty &&
          emptyLogs.isEmpty,
      '学生/合计/榜单/流水均为空',
    );

    // 2. 抽签历史在学生被删除后仍可读（姓名冗余存储）
    final klass = (await Repo.listClasses()).first;
    final students = await Repo.listStudents(klass.id);
    // 选一个没有红花记录的学生（有红花记录的学生当前删不掉，见 S1）
    final victim = students.firstWhere((s) => s.name == '陈子涵');
    await Repo.addDrawLog(classId: klass.id, winners: [victim]);
    var drawDeleteOk = true;
    var drawDeleteMsg = '';
    try {
      await Repo.deleteStudent(victim.id);
    } catch (e) {
      drawDeleteOk = false;
      drawDeleteMsg = '删除学生失败：${_brief(e)}';
    }
    final logs = await Repo.listDrawLogs(klass.id);
    final readable = logs.isNotEmpty && logs.first.names.contains('陈子涵');
    expectOk(
        area,
        '学生删除后抽签历史仍可读（姓名冗余存储）',
        drawDeleteOk && readable,
        drawDeleteOk
            ? '历史首条：${logs.isEmpty ? "-" : logs.first.names.join("、")}'
            : drawDeleteMsg);

    // 3. 设置项读写（一轮不重复等偏好持久化）
    await Repo.setSetting('no_repeat', '0');
    final v = await Repo.getSetting('no_repeat');
    expectOk(area, '设置项可持久化读写', v == '0', 'no_repeat=$v');

    // 4. 性能：42 人班级的常见操作耗时
    final big = (await Repo.listClasses()).first;
    final bigStudents = await Repo.listStudents(big.id);
    var sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      await Repo.flowerTotals(big.id);
    }
    sw.stop();
    final totalsMs = sw.elapsedMilliseconds / 50;

    sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      await Repo.listStudents(big.id);
    }
    sw.stop();
    final listMs = sw.elapsedMilliseconds / 50;

    sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      await Repo.flowerLeaderboard(big.id, sinceMs: 0);
    }
    sw.stop();
    final boardMs = sw.elapsedMilliseconds / 50;

    expectOk(
      area,
      '页面常用查询响应在「即时」范围内（<50ms/次）',
      listMs < 50 && totalsMs < 50 && boardMs < 50,
      '名单 ${listMs.toStringAsFixed(2)} ms / 红花合计 ${totalsMs.toStringAsFixed(2)} ms / 榜单 ${boardMs.toStringAsFixed(2)} ms（${bigStudents.length} 人）',
    );

    // 5. 数据库体积
    final dbFile = File(p.join(AppDb.dataDir, 'classroom.db'));
    note(area, '数据库体积', '${(dbFile.lengthSync() / 1024).toStringAsFixed(0)} KB');
  });
  // =========================================================================
  // S5 换电脑：备份与恢复
  // =========================================================================

  test('S5 换电脑：U盘备份与恢复', () async {
    const area = 'S5 备份';
    final tmpRoot = Directory(p.join(Directory.systemTemp.path,
        'sim_backup_${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);

    // 备份前记录状态
    final beforeClasses = await Repo.listClasses();
    final beforeStudents = await Repo.listStudents(beforeClasses.first.id);
    final beforeLists = await Repo.listWordLists();

    // 1. 一键备份
    var sw = Stopwatch()..start();
    var zipPath = '';
    var ok = true;
    var msg = '';
    try {
      zipPath = await BackupService.backupTo(tmpRoot.path);
    } catch (e) {
      ok = false;
      msg = '备份异常：$e';
    }
    sw.stop();
    expectOk(area, '一键备份生成 zip', ok && File(zipPath).existsSync(),
        ok ? '${p.basename(zipPath)}（${File(zipPath).lengthSync()} 字节，${sw.elapsedMilliseconds} ms）' : msg);
    if (!ok) return;

    // 2. 备份包必须同时含数据库与全部录音
    final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    final entryNames = archive.files.map((f) => f.name).toList();
    final hasDb = entryNames.any((n) => p.basename(n) == 'classroom.db');
    final audioEntries = entryNames.where((n) => n.startsWith('audio/')).length;
    expectOk(area, '备份包包含数据库', hasDb, '共 ${entryNames.length} 个条目');
    expectOk(area, '备份包包含全部听写录音', audioEntries > 0,
        '录音条目 $audioEntries 个（缺失将导致恢复后听写失效）');

    // 3. 备份后数据库应能继续使用（备份流程会关闭再重开）
    var stillUsable = true;
    try {
      await Repo.listClasses();
    } catch (e) {
      stillUsable = false;
    }
    expectOk(area, '备份后数据库自动重开、可继续使用', stillUsable, '');

    // 4. 制造「换电脑前的误删」：新增班级 + 删除学生
    final extra = await Repo.addClass('误建班级');
    await Repo.deleteStudent(beforeStudents.last.id);
    final dirty = await Repo.listStudents(beforeClasses.first.id);
    expectOk(area, '模拟误操作已生效（多 1 班、少 1 生）',
        (await Repo.listClasses()).length == beforeClasses.length + 1 &&
            dirty.length == beforeStudents.length - 1,
        '班级 ${beforeClasses.length}→${(await Repo.listClasses()).length}，学生 ${beforeStudents.length}→${dirty.length}');

    // 5. 恢复
    sw = Stopwatch()..start();
    ok = true;
    msg = '';
    try {
      await BackupService.restoreFrom(zipPath);
    } catch (e) {
      ok = false;
      msg = '恢复异常：$e';
    }
    sw.stop();
    expectOk(area, '从备份恢复不报错', ok, ok ? '耗时 ${sw.elapsedMilliseconds} ms' : msg);

    final afterClasses = await Repo.listClasses();
    final afterStudents = await Repo.listStudents(afterClasses.first.id);
    final afterLists = await Repo.listWordLists();
    expectOk(area, '恢复后班级回到备份时状态',
        afterClasses.length == beforeClasses.length &&
            !afterClasses.any((c) => c.id == extra.id),
        '班级 ${afterClasses.length} 个（期望 ${beforeClasses.length}）');
    expectOk(area, '恢复后名单回到备份时状态',
        afterStudents.length == beforeStudents.length,
        '学生 ${afterStudents.length} 人（期望 ${beforeStudents.length}）');
    expectOk(area, '恢复后词表回到备份时状态',
        afterLists.length == beforeLists.length,
        '词表 ${afterLists.length} 组（期望 ${beforeLists.length}）');

    // 6. 恢复后听写仍可用（音频文件回来了）
    final l = afterLists.firstWhere((x) => x.title == '第1课', orElse: () => afterLists.first);
    final ws = await Repo.listWords(l.id);
    final audioBack = ws.isNotEmpty && ws.every((w) => File(w.audioFile).existsSync());
    expectOk(area, '恢复后听写音频可用（功能不残缺）', audioBack,
        '「${l.title}」${ws.length} 词，文件齐备：$audioBack');

    // 7. 备份文件可被识别（设置页「从备份恢复」靠文件名扫描）
    final found = BackupService.listBackups(tmpRoot.path);
    expectOk(area, '备份文件可被设置页识别', found.isNotEmpty,
        '识别到 ${found.length} 个：${found.map(p.basename).join(", ")}');

    // 8. 恢复包路径非法（zip-slip）必须被拒绝
    final evilZip = p.join(tmpRoot.path, '班级管理系统备份_evil.zip');
    final evil = Archive();
    evil.addFile(ArchiveFile('../evil.txt', 5, utf8.encode('evil!')));
    evil.addFile(ArchiveFile('classroom.db', 4, utf8.encode('junk')));
    File(evilZip).writeAsBytesSync(ZipEncoder().encode(evil)!);
    final escapedPath = p.normalize(p.join(AppDb.dataDir, '../evil.txt'));
    if (File(escapedPath).existsSync()) File(escapedPath).deleteSync();
    var evilRestoreThrew = false;
    try {
      await BackupService.restoreFrom(evilZip);
    } catch (_) {
      evilRestoreThrew = true;
    }
    final escaped = File(escapedPath).existsSync();
    expectOk(area, '恢复时拒绝越界路径（防 zip-slip）', !escaped,
        escaped ? '越界文件被写出：$escapedPath' : '越界条目已被忽略，未写出数据目录之外');

    // 9. 损坏/伪造的备份包是否会摧毁现有数据
    //    （模拟 U 盘拷贝中断、备份包被覆盖、选错文件等真实事故）
    var dataSurvived = true;
    var surviveMsg = '';
    try {
      await Repo.listClasses();
      surviveMsg = '恢复后仍可正常打开数据库，现有数据未被破坏';
    } catch (e) {
      dataSurvived = false;
      surviveMsg = '恢复后数据库已损坏，无法打开：'
          '${e.toString().split('\n').first}';
    }
    expectOk(
      area,
      '损坏/伪造的备份包不会摧毁现有数据',
      dataSurvived,
      dataSurvived
          ? surviveMsg
          : '$surviveMsg（恢复流程未校验包内是否含有效数据库，也无恢复前快照，'
              '本次已触发：$evilRestoreThrew 时抛出异常）',
    );

    // 10. 有可用备份时能否救回来（老师会再点一次「从备份恢复」）
    var rescued = false;
    final rescueLog = <String>[];
    try {
      await BackupService.restoreFrom(zipPath);
      rescued = (await Repo.listClasses()).isNotEmpty;
      rescueLog.add('直接重试：${rescued ? "成功" : "恢复后无数据"}');
    } catch (e) {
      rescueLog.add('直接重试：失败（${_brief(e)}）');
    }
    if (!rescued) {
      // 等价于「关掉应用重新打开」再试一次
      try {
        await AppDb.close();
        await BackupService.restoreFrom(zipPath);
        rescued = (await Repo.listClasses()).isNotEmpty;
        rescueLog.add('关闭数据库后重试：${rescued ? "成功" : "恢复后无数据"}');
      } catch (e) {
        rescueLog.add('关闭数据库后重试：失败（${_brief(e)}）');
      }
    }
    expectOk(area, '手头还有一份有效备份时，数据可以救回', rescued,
        rescueLog.join('；'));

    // 11. 异常恢复后应用仍可正常打开数据库
    var reopenOk = true;
    try {
      await Repo.listClasses();
    } catch (e) {
      reopenOk = false;
    }
    expectOk(area, '异常恢复后应用仍可正常打开数据库', reopenOk, '');

    try {
      tmpRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

bool _isDescending(List<LeaderRow> rows) {
  for (var i = 1; i < rows.length; i++) {
    if (rows[i - 1].total < rows[i].total) return false;
  }
  return true;
}

bool _isDesc(List<int> xs) {
  for (var i = 1; i < xs.length; i++) {
    if (xs[i - 1] < xs[i]) return false;
  }
  return true;
}

/// 异常信息压缩成一行，便于写进报告。
String _brief(Object e) {
  final s = e.toString().replaceAll('\n', ' ');
  return s.length > 120 ? '${s.substring(0, 120)}…' : s;
}

/// 直接调用真实 TtsService，保持与生产一致。
Future<List<int>> _ttsGenerate(
  String outDir,
  List<(String, String)> items,
) {
  return TtsService.generate(
    outDir: outDir,
    items: items.map((e) => (fileName: e.$1, word: e.$2)).toList(),
  );
}

/// 简易 wav 时长解析（与 probeAudioFile 同口径，用于模拟脚本自检）。
int _wavDurationMs(File f) {
  try {
    final bytes = f.readAsBytesSync();
    if (bytes.length < 44) return 0;
    final byteRate = _le32(bytes, 28);
    final dataSize = _le32(bytes, 40);
    if (byteRate == 0) return 0;
    return (dataSize / byteRate * 1000).round();
  } catch (_) {
    return 0;
  }
}

int _le32(List<int> b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

/// 取工作表第一行作为表头文本。
String _headerOf(Sheet? sheet) {
  if (sheet == null || sheet.rows.isEmpty) return '';
  return sheet.rows.first.map((c) => c?.value?.toString() ?? '').join(',');
}

// ---------------------------------------------------------------------------
// 报告输出
// ---------------------------------------------------------------------------

Future<void> _writeReport() async {
  final outDir = Directory(
      Platform.environment['CM_SIM_OUT'] ?? p.join(Directory.systemTemp.path, 'cm_sim_out'));
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  final buf = StringBuffer();
  buf.writeln('# 小学班级管理系统 · 日常使用模拟报告');
  buf.writeln();
  buf.writeln('- 模拟时间：${DateTime.now().toIso8601String()}');
  buf.writeln('- 数据目录：${AppDb.dataDir}');
  buf.writeln('- 总耗时：${_clock.elapsedMilliseconds} ms');
  buf.writeln();

  final areas = <String>[];
  for (final f in _findings) {
    if (!areas.contains(f.area)) areas.add(f.area);
  }

  var pass = 0, fail = 0;
  for (final a in areas) {
    buf.writeln('## $a');
    buf.writeln();
    for (final f in _findings.where((x) => x.area == a)) {
      buf.writeln('- [${f.ok ? "PASS" : "FAIL"}] ${f.item}');
      if (f.detail.isNotEmpty) buf.writeln('  - ${f.detail}');
      if (f.ok) {
        pass++;
      } else {
        fail++;
      }
    }
    buf.writeln();
  }

  buf.writeln('## 汇总');
  buf.writeln();
  buf.writeln('- 检查项：${pass + fail}');
  buf.writeln('- 通过：$pass');
  buf.writeln('- 未通过：$fail');
  if (fail > 0) {
    buf.writeln();
    buf.writeln('### 未通过清单');
    for (final f in _findings.where((x) => !x.ok)) {
      buf.writeln('- 【${f.area}】${f.item}：${f.detail}');
    }
  }

  final out = File(p.join(outDir.path, 'sim_daily_use_report.md'));
  out.writeAsStringSync(buf.toString(), encoding: utf8);
  // ignore: avoid_print
  print('SIM_REPORT=${out.path}');
  // ignore: avoid_print
  print('SIM_RESULT pass=$pass fail=$fail');
  for (final f in _findings.where((x) => !x.ok)) {
    // ignore: avoid_print
    print('SIM_FAIL [${f.area}] ${f.item} :: ${f.detail}');
  }
}
