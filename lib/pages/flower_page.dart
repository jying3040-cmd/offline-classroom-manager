import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../services/report_service.dart';

const List<String> _awardReasons = [
  '课堂表现',
  '作业优秀',
  '进步明显',
  '帮助同学',
  '积极发言',
  '朗读优秀',
];

const List<String> _deductReasons = [
  '上课讲话',
  '未交作业',
  '课堂纪律',
  '追逐打闹',
  '迟到早退',
  '与人争吵',
];

enum _FlowerView { award, board, today }

enum _BoardRange { week, month, all }

String _two(int v) => v.toString().padLeft(2, '0');

String _hm(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

String _mdhm(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}

int _startOfTodayMs() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
}

/// 本周一 00:00（中国习惯周一为一周开始）。
int _startOfWeekMs() {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return day.subtract(Duration(days: now.weekday - 1)).millisecondsSinceEpoch;
}

int _startOfMonthMs() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
}

/// 小红花奖励：授奖网格 / 榜单 / 今日时间线。
class FlowerPage extends StatefulWidget {
  const FlowerPage({super.key});

  @override
  State<FlowerPage> createState() => _FlowerPageState();
}

class _FlowerPageState extends State<FlowerPage> {
  List<Klass> _classes = [];
  List<Student> _students = [];
  Map<String, int> _totals = {};
  String? _classId;
  bool _loading = true;

  _FlowerView _view = _FlowerView.award;
  _BoardRange _range = _BoardRange.week;
  List<LeaderRow> _boardRows = [];
  List<FlowerEntry> _todayRows = [];

  bool get _hasClass => _classId != null;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final classes = await Repo.listClasses();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      if (_classId == null || !_classes.any((c) => c.id == _classId)) {
        _classId = classes.isEmpty ? null : classes.first.id;
      }
      _loading = false;
    });
    if (_classId == null) {
      setState(() {
        _students = [];
        _totals = {};
      });
      return;
    }
    final students = await Repo.listStudents(_classId!);
    final totals = await Repo.flowerTotals(_classId!);
    if (!mounted) return;
    setState(() {
      _students = students;
      _totals = totals;
    });
    if (_view != _FlowerView.award) {
      await _refreshView();
    }
  }

  Future<void> _refreshView() async {
    final classId = _classId;
    if (classId == null) return;
    if (_view == _FlowerView.board) {
      final rows = await Repo.flowerLeaderboard(classId, sinceMs: _sinceMs());
      if (!mounted) return;
      setState(() => _boardRows = rows);
    } else if (_view == _FlowerView.today) {
      final rows =
          await Repo.classLogsSince(classId, sinceMs: _startOfTodayMs());
      if (!mounted) return;
      setState(() => _todayRows = rows);
    }
  }

  int _sinceMs() {
    switch (_range) {
      case _BoardRange.week:
        return _startOfWeekMs();
      case _BoardRange.month:
        return _startOfMonthMs();
      case _BoardRange.all:
        return 0;
    }
  }

  Future<void> _selectView(_FlowerView v) async {
    setState(() => _view = v);
    await _refreshView();
  }

  Future<void> _selectRange(_BoardRange r) async {
    setState(() => _range = r);
    await _refreshView();
  }

  /// 加/减一朵（加减制：正数奖励，负数扣减，各自直接写入流水）。
  Future<void> _award(Student s, int delta, [String? reason]) async {
    if (_classId == null) return;
    try {
      await Repo.awardFlower(studentId: s.id, delta: delta, reason: reason);
    } catch (_) {
      if (mounted) _toast('保存失败，请重试');
      return;
    }
    if (!mounted) return;
    setState(() => _totals[s.id] = (_totals[s.id] ?? 0) + delta);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final totalFlowers = _totals.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Text(
            '🌸 小红花',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),
          if (_classes.isNotEmpty)
            DropdownButton<String>(
              value: _classId,
              underline: const SizedBox.shrink(),
              items: [
                for (final c in _classes)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) async {
                if (id == null) return;
                setState(() => _classId = id);
                await _reload();
              },
            ),
          if (_hasClass) ...[
            const SizedBox(width: 8),
            Text(
              '累计 🌸 $totalFlowers',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const Spacer(),
          IconButton(
            onPressed: _hasClass ? _exportReport : null,
            icon: const Icon(Icons.table_view),
            tooltip: '导出 Excel 报表',
          ),
          const SizedBox(width: 4),
          SegmentedButton<_FlowerView>(
            selected: {_view},
            onSelectionChanged: (s) => _selectView(s.first),
            segments: const [
              ButtonSegment(
                value: _FlowerView.award,
                icon: Icon(Icons.local_florist),
                label: Text('授奖'),
              ),
              ButtonSegment(
                value: _FlowerView.board,
                icon: Icon(Icons.emoji_events_outlined),
                label: Text('榜单'),
              ),
              ButtonSegment(
                value: _FlowerView.today,
                icon: Icon(Icons.today_outlined),
                label: Text('今日'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasClass) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_florist, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            const Text('请先在「名单」页创建班级和学生'),
          ],
        ),
      );
    }
    switch (_view) {
      case _FlowerView.award:
        if (_students.isEmpty) {
          return const Center(child: Text('这个班级还没有学生，请先到「名单」页添加'));
        }
        return _buildAward(context);
      case _FlowerView.board:
        return _buildBoard(context);
      case _FlowerView.today:
        return _buildToday(context);
    }
  }

  Widget _buildAward(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: _students.length,
      itemBuilder: (context, i) {
        final s = _students[i];
        return _FlowerCard(
          student: s,
          accent: ClassManagerApp.candyColors[i % ClassManagerApp.candyColors.length],
          total: _totals[s.id] ?? 0,
          onPlus: () => _reasonDialog(s, negative: false),
          onMinus: () => _reasonDialog(s, negative: true),
          onMore: () => _showDetail(s),
        );
      },
    );
  }

  Widget _buildBoard(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              SegmentedButton<_BoardRange>(
                selected: {_range},
                onSelectionChanged: (s) => _selectRange(s.first),
                segments: const [
                  ButtonSegment(value: _BoardRange.week, label: Text('本周')),
                  ButtonSegment(value: _BoardRange.month, label: Text('本月')),
                  ButtonSegment(value: _BoardRange.all, label: Text('累计')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _boardRows.isEmpty
              ? Center(
                  child: Text(
                    '暂无数据',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _boardRows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = _boardRows[i];
                    final medal = switch (i) {
                      0 => '🥇',
                      1 => '🥈',
                      2 => '🥉',
                      _ => '${i + 1}',
                    };
                    return ListTile(
                      leading: SizedBox(
                        width: 44,
                        child: Center(
                          child: Text(medal, style: theme.textTheme.titleMedium),
                        ),
                      ),
                      title: Text(r.name, style: theme.textTheme.titleMedium),
                      trailing: Text(
                        '🌸 ${r.total}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToday(BuildContext context) {
    final theme = Theme.of(context);
    var flowers = 0;
    var persons = 0;
    var deductions = 0;
    for (final e in _todayRows) {
      if (e.log.delta > 0) {
        flowers += e.log.delta;
        persons += 1;
      } else {
        deductions += 1;
      }
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _SummaryCard(label: '今日奖励', value: '🌸 $flowers'),
              const SizedBox(width: 12),
              _SummaryCard(label: '奖励人次', value: '$persons 次'),
              const SizedBox(width: 12),
              _SummaryCard(label: '扣减', value: '$deductions 次'),
            ],
          ),
        ),
        Expanded(
          child: _todayRows.isEmpty
              ? const Center(child: Text('今天还没有记录'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _todayRows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _todayRows[i];
                    final d = e.log.delta;
                    return ListTile(
                      dense: true,
                      leading: Text(
                        _hm(e.log.createdAt),
                        style: theme.textTheme.bodyMedium,
                      ),
                      title: Text(
                        '${e.studentName}  ${d > 0 ? '+$d' : '$d'}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: d > 0 ? null : Colors.red.shade700),
                      ),
                      subtitle: e.log.reason == null ? null : Text(e.log.reason!),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------- 报表导出 ----------

  Future<void> _exportReport() async {
    final classId = _classId;
    if (classId == null) return;
    var className = '';
    for (final c in _classes) {
      if (c.id == classId) className = c.name;
    }
    final range = await showDialog<ReportRange>(
      context: context,
      builder: (context) => const _ExportRangeDialog(),
    );
    if (range == null || !mounted) return;
    try {
      final path = await ReportService.exportFlowerReport(
        classId: classId,
        className: className,
        range: range,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green),
          title: const Text('导出成功'),
          content: SelectableText(path),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Process.run('explorer.exe', ['/select,', path]);
                Navigator.pop(context);
              },
              child: const Text('打开所在文件夹'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _toast('导出失败，请重试');
    }
  }

  // ---------- 学生操作 ----------

  Future<void> _reasonDialog(Student s, {required bool negative}) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) =>
          _ReasonAwardDialog(studentName: s.name, negative: negative),
    );
    if (!mounted || result == null) return;
    final (qty, reason) = result;
    if (qty <= 0) return;
    await _award(s, negative ? -qty : qty, reason.isEmpty ? null : reason);
  }

  Future<void> _refreshTotals() async {
    if (_classId == null) return;
    final totals = await Repo.flowerTotals(_classId!);
    if (!mounted) return;
    setState(() => _totals = totals);
  }

  Future<void> _showDetail(Student s) async {
    var entries = await Repo.studentLogs(s.id);
    if (!mounted) return;
    final theme = Theme.of(context);
    final deleted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${s.name} 的红花明细（点垃圾桶可删除该条）'),
          content: SizedBox(
            width: 480,
            height: 420,
            child: entries.isEmpty
                ? const Center(child: Text('暂无记录'))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final d = e.log.delta;
                      return ListTile(
                        dense: true,
                        leading: Text(
                          d > 0 ? '+$d' : '$d',
                          style: TextStyle(
                            color: d > 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        title: Text(e.log.reason ?? (d > 0 ? '奖励' : '扣减')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _mdhm(e.log.createdAt),
                              style: theme.textTheme.bodySmall,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除这条记录',
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除记录'),
                                    content: Text(
                                        '确定删除这条「${e.log.reason ?? (d > 0 ? '奖励' : '扣减')} $d 朵」的记录吗？'
                                        '该学生的合计会随之减少。'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                await Repo.deleteFlowerLog(e.log.id);
                                setDialogState(() => entries.removeAt(i));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
    if (deleted == true && mounted) {
      await _refreshTotals();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _ExportRangeDialog extends StatefulWidget {
  const _ExportRangeDialog();

  @override
  State<_ExportRangeDialog> createState() => _ExportRangeDialogState();
}

class _ExportRangeDialogState extends State<_ExportRangeDialog> {
  ReportRange _range = ReportRange.week;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出 Excel 报表'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择统计范围（文件将保存到桌面）：'),
            const SizedBox(height: 12),
            SegmentedButton<ReportRange>(
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
              segments: const [
                ButtonSegment(value: ReportRange.today, label: Text('今日')),
                ButtonSegment(value: ReportRange.week, label: Text('本周')),
                ButtonSegment(value: ReportRange.month, label: Text('本月')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _range),
          child: const Text('导出'),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowerCard extends StatelessWidget {
  const _FlowerCard({
    required this.student,
    required this.accent,
    required this.total,
    required this.onPlus,
    required this.onMinus,
    required this.onMore,
  });

  final Student student;
  final Color accent;
  final int total;
  final VoidCallback onPlus;
  final VoidCallback onMinus;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = BorderSide(color: ClassManagerApp.ink, width: 2);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent, width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: accent,
                  child: Text(
                    student.name.substring(0, 1),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    student.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: onMore,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: ClassManagerApp.ink,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onMinus,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      side: side,
                      shape: const CircleBorder(),
                      backgroundColor: Colors.white,
                    ),
                    child: const Text(
                      '－',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: ClassManagerApp.ink,
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🌸', style: TextStyle(fontSize: 24)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Text(
                        '$total',
                        key: ValueKey<int>(total),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: ClassManagerApp.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: FilledButton(
                    onPressed: onPlus,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      side: side,
                      shape: const CircleBorder(),
                    ),
                    child: const Text(
                      '＋',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonAwardDialog extends StatefulWidget {
  const _ReasonAwardDialog({
    required this.studentName,
    required this.negative,
  });

  final String studentName;
  final bool negative;

  @override
  State<_ReasonAwardDialog> createState() => _ReasonAwardDialogState();
}

class _ReasonAwardDialogState extends State<_ReasonAwardDialog> {
  int _qty = 1;
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.negative ? '扣减小红花 · ${widget.studentName}' : '奖励小红花 · ${widget.studentName}',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数量', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              selected: {_qty},
              onSelectionChanged: (s) => setState(() => _qty = s.first),
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: '原因（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in widget.negative ? _deductReasons : _awardReasons)
                  ChoiceChip(
                    label: Text(r),
                    selected: _reason.text == r,
                    onSelected: (_) => setState(() => _reason.text = r),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_qty, _reason.text.trim())),
          child: Text(widget.negative ? '扣减' : '奖励'),
        ),
      ],
    );
  }
}
