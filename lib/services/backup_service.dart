import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../data/db.dart';

/// 备份与恢复：数据目录（SQLite + 全部听写录音）打成 zip，可存 U 盘。
/// 恢复时覆盖本地数据并重启应用。
class BackupService {
  static String _two(int v) => v.toString().padLeft(2, '0');

  static String backupFileName() {
    final t = DateTime.now();
    return '班级管理系统备份_${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}${_two(t.second)}.zip';
  }

  /// 检测可移动磁盘（U盘）。PowerShell 不可用时返回空列表，用户可手输路径。
  static Future<List<String>> removableDrives() async {
    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" '
              '| Select-Object -ExpandProperty DeviceID',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode != 0) return [];
      return r.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 没有 U 盘时的兜底备份位置（桌面 → 文档 → 临时目录）。
  static String fallbackDir() {
    final user = Platform.environment['USERPROFILE'] ?? '';
    for (final c in ['$user\\Desktop', '$user\\Documents']) {
      if (c.isNotEmpty && Directory(c).existsSync()) return c;
    }
    return Directory.systemTemp.path;
  }

  /// 备份到目标文件夹，返回 zip 完整路径。
  /// 备份前关闭数据库确保 WAL 全部落盘，完成后重新打开。
  static Future<String> backupTo(String targetDir) async {
    final dir = Directory(targetDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final zipPath = p.join(dir.path, backupFileName());
    await AppDb.close();
    try {
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addFile(File(p.join(AppDb.dataDir, 'classroom.db')));
      final audio = Directory(p.join(AppDb.dataDir, 'audio'));
      if (audio.existsSync()) {
        encoder.addDirectory(audio);
      }
      encoder.close();
    } finally {
      await AppDb.init();
    }
    return zipPath;
  }

  /// 扫描目标文件夹里的备份文件（新→旧）。
  static List<String> listBackups(String targetDir) {
    final dir = Directory(targetDir);
    if (!dir.existsSync()) return [];
    final re = RegExp(r'^班级管理系统备份_.+\.zip$');
    final out = <String>[];
    for (final e in dir.listSync()) {
      if (e is File && re.hasMatch(p.basename(e.path))) {
        out.add(e.path);
      }
    }
    out.sort((a, b) => b.compareTo(a));
    return out;
  }

  /// 从备份恢复：关闭数据库 → 清空现有数据 → 解压 → 重开。
  static Future<void> restoreFrom(String zipPath) async {
    await AppDb.close();
    try {
      for (final name in ['classroom.db', 'classroom.db-wal', 'classroom.db-shm']) {
        final f = File(p.join(AppDb.dataDir, name));
        if (f.existsSync()) f.deleteSync();
      }
      final audio = Directory(p.join(AppDb.dataDir, 'audio'));
      if (audio.existsSync()) {
        audio.deleteSync(recursive: true);
      }
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        final outPath = p.normalize(p.join(AppDb.dataDir, f.name));
        if (!p.isWithin(AppDb.dataDir, outPath)) {
          continue; // 防 zip-slip：忽略越界路径
        }
        if (f.isFile) {
          File(outPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(f.content as List<int>);
        }
      }
    } finally {
      await AppDb.init();
    }
  }

  /// 启动一个新的应用实例并退出当前实例（恢复数据后使用）。
  static Future<void> restartApp() async {
    final exe = Platform.resolvedExecutable;
    await Process.start(
      exe,
      const [],
      workingDirectory: File(exe).parent.path,
      mode: ProcessStartMode.detached,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}
