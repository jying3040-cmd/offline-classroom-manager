// 场景 B：数据库文件损坏后，应用**已经尝试打开过**（打开失败）再恢复备份。
//
// 这一场景对应真实事故：老师断电 → 数据库损坏 → 打开应用报错 →
// 老师按提示点「从备份恢复」。检验这条路还能不能走通。
//
// 与 sim_backup_corrupt_test.dart（场景 A：损坏后未打开过，直接恢复）成对，
// 两者结果不同即说明「一次失败的打开会污染后续所有恢复尝试」。
//
// 运行：APPDATA=<临时目录> flutter test test/sim_backup_corrupt_poisoned_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:classroom_manager/data/db.dart';
import 'package:classroom_manager/data/repo.dart';
import 'package:classroom_manager/services/backup_service.dart';

final List<String> _log = [];
void record(String item, bool ok, [String detail = '']) {
  _log.add('- [${ok ? "PASS" : "FAIL"}] $item'
      '${detail.isEmpty ? "" : "\n  - $detail"}');
}

String _brief(Object e) {
  final s = e.toString().replaceAll('\n', ' ');
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
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
    final out =
        File(p.join(outDir.path, 'sim_backup_poisoned_report.md'));
    out.writeAsStringSync(
        '# 数据损坏 + 已尝试打开 后的备份救援验证\n\n${_log.join("\n")}\n');
    // ignore: avoid_print
    print('SIM_POISON_REPORT=${out.path}');
    for (final l in _log) {
      // ignore: avoid_print
      print('SIM_POISON ${l.split("\n").first}');
    }
  });

  test('损坏并已尝试打开后，用备份还能否救回', () async {
    final tmpRoot = Directory(p.join(Directory.systemTemp.path,
        'poison_backup_${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);

    final klass = await Repo.addClass('四年级1班');
    await Repo.addStudentsByName(
        classId: klass.id,
        names: const ['甲同学', '乙同学', '丙同学']);
    final students = await Repo.listStudents(klass.id);
    await Repo.awardFlower(studentId: students[0].id, delta: 5, reason: '课堂表现');

    final zip = await BackupService.backupTo(tmpRoot.path);
    record('备份成功', File(zip).existsSync(), p.basename(zip));

    // 损坏数据文件
    await AppDb.close();
    File(p.join(AppDb.dataDir, 'classroom.db'))
        .writeAsBytesSync([0x6A, 0x75, 0x6E, 0x6B]); // 'junk'

    // 关键一步：应用启动时尝试打开损坏的数据库（等价于老师打开应用）
    var openFailed = false;
    var openErr = '';
    try {
      await AppDb.init();
      await Repo.listClasses();
    } catch (e) {
      openFailed = true;
      openErr = _brief(e);
    }
    record('损坏的数据库打开失败（复现启动异常）', openFailed, openErr);

    // 现在再点「从备份恢复」
    var restored = false;
    var restoreErr = '';
    try {
      await BackupService.restoreFrom(zip);
      restored = true;
    } catch (e) {
      restoreErr = _brief(e);
    }
    record('打开失败一次之后，再点「从备份恢复」仍能成功', restored, restoreErr);

    // 再试一次（老师会反复点）
    var restored2 = false;
    var restoreErr2 = '';
    if (!restored) {
      try {
        await AppDb.close();
        await BackupService.restoreFrom(zip);
        restored2 = true;
      } catch (e) {
        restoreErr2 = _brief(e);
      }
      record('连关库后重试也无效（只能彻底重启应用进程）', restored2,
          restored2 ? '重试成功' : restoreErr2);
    }

    if (restored || restored2) {
      final classes = await Repo.listClasses();
      record('恢复后数据完整', classes.length == 1, '班级 ${classes.length} 个');
    }

    try {
      tmpRoot.deleteSync(recursive: true);
    } catch (_) {}
  });
}
