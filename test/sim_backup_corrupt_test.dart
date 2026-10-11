// 独立进程验证：数据文件被损坏（模拟断电 / 磁盘故障 / U盘故障）后，
// 用一份完好的备份能否把数据完整救回来。
//
// 为什么要单独一个文件：损坏的数据库会在 sqflite 的「单实例」缓存里留下
// 一个坏连接，同一次进程内无法恢复。放在独立进程里跑，等价于「老师关掉
// 应用、重新打开，再点『从备份恢复』」。
//
// 运行：APPDATA=<临时目录> flutter test test/sim_backup_corrupt_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:classroom_manager/data/db.dart';
import 'package:classroom_manager/data/models.dart';
import 'package:classroom_manager/data/repo.dart';
import 'package:classroom_manager/services/backup_service.dart';

final List<String> _log = [];
void record(String item, bool ok, [String detail = '']) {
  _log.add('- [${ok ? "PASS" : "FAIL"}] $item${detail.isEmpty ? "" : "\n  - $detail"}');
}

void main() {
  setUpAll(() async {
    final appData =
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dataDir = Directory(p.join(appData, 'classroom_manager', 'data'));
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    dataDir.createSync(recursive: true);
    await AppDb.init();
  });

  tearDownAll(() async {
    final outDir = Directory(Platform.environment['CM_SIM_OUT'] ??
        p.join(Directory.systemTemp.path, 'cm_sim_out'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final out = File(p.join(outDir.path, 'sim_backup_corrupt_report.md'));
    out.writeAsStringSync('# 数据损坏后的备份救援验证\n\n${_log.join("\n")}\n');
    // ignore: avoid_print
    print('SIM_CORRUPT_REPORT=${out.path}');
    for (final l in _log) {
      // ignore: avoid_print
      print('SIM_CORRUPT ${l.split("\n").first}');
    }
  });

  test('数据文件损坏后，用备份能否救回', () async {
    final tmpRoot = Directory(p.join(Directory.systemTemp.path,
        'corrupt_backup_${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);

    // ---- 1. 造一份真实数据 ----
    final klass = await Repo.addClass('四年级1班');
    await Repo.addStudentsByName(
        classId: klass.id,
        names: const ['甲同学', '乙同学', '丙同学', '丁同学', '戊同学']);
    final students = await Repo.listStudents(klass.id);
    await Repo.awardFlower(studentId: students[0].id, delta: 5, reason: '课堂表现');
    await Repo.awardFlower(studentId: students[1].id, delta: 2, reason: '作业优秀');

    final list = await Repo.createWordList('第1课', subject: '语文');
    final audioDir = Directory(p.join(AppDb.dataDir, 'audio', list.id))
      ..createSync(recursive: true);
    final wav = File(p.join(audioDir.path, 'w1.wav'))..writeAsBytesSync(_wav());
    await Repo.importWords(listId: list.id, items: [
      WordImportItem(
        sourcePath: wav.path,
        ext: '.wav',
        word: '桂花',
        durationMs: 200,
        origFilename: '桂花.wav',
      ),
    ]);

    final beforeTotals = await Repo.flowerTotals(klass.id);
    final beforeSum = beforeTotals.values.fold<int>(0, (a, b) => a + b);

    // ---- 2. 备份 ----
    final zip = await BackupService.backupTo(tmpRoot.path);
    record('备份成功', File(zip).existsSync(),
        '${p.basename(zip)}（${File(zip).lengthSync()} 字节）');

    // ---- 3. 模拟数据文件损坏 ----
    await AppDb.close();
    File(p.join(AppDb.dataDir, 'classroom.db'))
        .writeAsBytesSync([0x6A, 0x75, 0x6E, 0x6B]); // 'junk'
    final brokenBytes = File(p.join(AppDb.dataDir, 'classroom.db')).lengthSync();
    record('数据文件已被损坏（模拟断电/磁盘损坏）', brokenBytes < 100,
        'classroom.db 现为 $brokenBytes 字节');

    // ---- 4. 重启应用后用备份恢复 ----
    // 注意：这里刻意**不**先去打开损坏的数据库——因为一旦打开失败，
    // sqflite 的单实例缓存会留下坏连接（见 sim_backup_corrupt_poisoned_test.dart）。
    await AppDb.close();
    var restored = false;
    var err = '';
    try {
      await BackupService.restoreFrom(zip);
      restored = true;
    } catch (e) {
      err = e.toString().split('\n').first;
    }
    record('损坏后能用备份恢复', restored, err);

    if (restored) {
      final classes = await Repo.listClasses();
      final students2 = await Repo.listStudents(classes.first.id);
      final totals2 = await Repo.flowerTotals(classes.first.id);
      final sum2 = totals2.values.fold<int>(0, (a, b) => a + b);
      final lists = await Repo.listWordLists();
      final words =
          lists.isEmpty ? <Word>[] : await Repo.listWords(lists.first.id);
      final audioBack = words.isNotEmpty &&
          words.every((w) => File(w.audioFile).existsSync());

      record('恢复后班级完整', classes.length == 1, '班级 ${classes.length} 个');
      record('恢复后名单完整', students2.length == 5, '学生 ${students2.length} 人（期望 5）');
      record('恢复后红花记录完整', sum2 == beforeSum,
          '合计 $sum2（备份前 $beforeSum）');
      record('恢复后听写词表与录音完整', lists.isNotEmpty && audioBack,
          '词表 ${lists.length} 组，录音文件存在：$audioBack');
    }

    try {
      tmpRoot.deleteSync(recursive: true);
    } catch (_) {}
  });
}

/// 生成一个 0.2 秒静音 WAV。
List<int> _wav() {
  const sampleRate = 8000;
  const samples = 1600;
  final dataSize = samples * 2;
  final b = <int>[];
  void str(String s) => b.addAll(s.codeUnits);
  void u32(int v) =>
      b.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u16(int v) => b.addAll([v & 0xFF, (v >> 8) & 0xFF]);
  str('RIFF');
  u32(36 + dataSize);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  str('data');
  u32(dataSize);
  b.addAll(List<int>.filled(dataSize, 0));
  return b;
}
