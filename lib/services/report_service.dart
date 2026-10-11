import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../data/repo.dart';

enum ReportRange { today, week, month }

extension ReportRangeLabel on ReportRange {
  String get label => switch (this) {
        ReportRange.today => '今日',
        ReportRange.week => '本周',
        ReportRange.month => '本月',
      };
}

/// 红花报表导出：生成 xlsx（明细 + 汇总两个工作表），保存到桌面。
class ReportService {
  static int _sinceMs(ReportRange range) {
    final now = DateTime.now();
    switch (range) {
      case ReportRange.today:
        return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      case ReportRange.week:
        final day = DateTime(now.year, now.month, now.day);
        return day
            .subtract(Duration(days: now.weekday - 1))
            .millisecondsSinceEpoch;
      case ReportRange.month:
        return DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');

  static String _desktopDir() {
    final user = Platform.environment['USERPROFILE'] ?? '';
    final candidates = [
      '$user\\Desktop',
      '$user\\Documents',
      r'C:\Users\Public\Desktop',
    ];
    for (final c in candidates) {
      if (c.isNotEmpty && Directory(c).existsSync()) return c;
    }
    return Directory.systemTemp.path;
  }

  /// 生成报表并返回文件完整路径。
  static Future<String> exportFlowerReport({
    required String classId,
    required String className,
    required ReportRange range,
  }) async {
    final entries = await Repo.classLogsSince(classId,
        sinceMs: _sinceMs(range), limit: 100000);

    final excel = Excel.createExcel();
    final now = DateTime.now();

    // Sheet1: 明细
    final detail = excel['明细'];
    detail.appendRow([
      TextCellValue('日期'),
      TextCellValue('时间'),
      TextCellValue('学生'),
      TextCellValue('变化'),
      TextCellValue('原因'),
    ]);
    for (final e in entries) {
      final t = DateTime.fromMillisecondsSinceEpoch(e.log.createdAt);
      detail.appendRow([
        TextCellValue('${t.year}-${_two(t.month)}-${_two(t.day)}'),
        TextCellValue('${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'),
        TextCellValue(e.studentName),
        IntCellValue(e.log.delta),
        TextCellValue(e.log.reason ?? (e.log.delta > 0 ? '奖励' : '扣减')),
      ]);
    }

    // Sheet2: 汇总（净得分排行）
    final sum = excel['汇总'];
    sum.appendRow([
      TextCellValue('排名'),
      TextCellValue('学生'),
      TextCellValue('小红花'),
    ]);
    final totals = <String, int>{};
    for (final e in entries) {
      totals[e.studentName] = (totals[e.studentName] ?? 0) + e.log.delta;
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var i = 0; i < ranked.length; i++) {
      sum.appendRow([
        IntCellValue(i + 1),
        TextCellValue(ranked[i].key),
        IntCellValue(ranked[i].value),
      ]);
    }
    excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('生成报表失败');
    }
    final dateTag =
        '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final fileName =
        '红花报表_${_sanitize(className)}_${dateTag}_${range.label}.xlsx';
    final file = File(p.join(_desktopDir(), fileName));
    file.writeAsBytesSync(bytes);
    return file.path;
  }
}
