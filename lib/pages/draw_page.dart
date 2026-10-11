import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/repo.dart';

enum _DrawPhase { idle, rolling, result }

/// 随机抽签：结果在动画开始前已由安全随机数确定，滚动动画仅为展示。
class DrawPage extends StatefulWidget {
  const DrawPage({super.key});

  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  List<Klass> _classes = [];
  List<Student> _allStudents = [];
  String? _classId;
  bool _loading = true;

  int _pickCount = 1;
  String _scope = '全班';
  String _groupFilter = '';
  int _memberNoFilter = -1;
  bool _noRepeat = true;
  Set<String> _drawnIds = {};

  _DrawPhase _phase = _DrawPhase.idle;
  List<Student> _winners = [];
  List<String> _rollingNames = [];
  Timer? _rollTimer;

  List<Student> get _pool {
    Iterable<Student> s = _allStudents;
    if (_scope == '男') s = s.where((x) => x.gender == '男');
    if (_scope == '女') s = s.where((x) => x.gender == '女');
    if (_groupFilter != '') s = s.where((x) => x.groupName == _groupFilter);
    if (_memberNoFilter >= 0) {
      s = s.where((x) => x.memberNo == _memberNoFilter);
    }
    return s.toList();
  }

  List<String> get _groups {
    final values = _allStudents
        .map((s) => s.groupName)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['', ...values];
  }

  List<int> get _memberNumbers {
    final values = _allStudents
        .map((s) => s.memberNo)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return [-1, ...values];
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final classes = await Repo.listClasses();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      if (_classId == null || !_classes.any((c) => c.id == _classId)) {
        _classId = classes.isEmpty ? null : classes.first.id;
      }
    });
    await _loadStudents();
  }

  Future<void> _loadStudents() async {
    final classId = _classId;
    if (classId == null) {
      if (mounted) {
        setState(() {
          _allStudents = [];
          _loading = false;
        });
      }
      return;
    }
    final students = await Repo.listStudents(classId);
    if (!mounted) return;
    setState(() {
      _allStudents = students;
      if (_groupFilter != '' &&
          !students.any((s) => s.groupName == _groupFilter)) {
        _groupFilter = '';
      }
      if (_memberNoFilter >= 0 &&
          !students.any((s) => s.memberNo == _memberNoFilter)) {
        _memberNoFilter = -1;
      }
      _drawnIds.removeWhere((id) => !students.any((s) => s.id == id));
      _loading = false;
    });
  }

  void _switchClass(String id) {
    if (_loading || _phase == _DrawPhase.rolling || id == _classId) return;
    setState(() {
      _classId = id;
      _drawnIds = {};
      _phase = _DrawPhase.idle;
      _winners = [];
      _groupFilter = '';
      _memberNoFilter = -1;
      _loading = true;
    });
    _loadStudents();
  }

  Future<void> _startDraw() async {
    if (_loading || _phase == _DrawPhase.rolling) return;
    final pool = _pool;
    if (pool.isEmpty) {
      _toast('当前范围内没有学生');
      return;
    }
    if (pool.length < _pickCount) {
      _toast('当前范围内不足 $_pickCount 人，请减少抽取人数');
      return;
    }
    var candidates =
        pool.where((s) => !_noRepeat || !_drawnIds.contains(s.id)).toList();
    if (candidates.length < _pickCount) {
      // 一轮抽完：自动重置，开始新一轮。
      _drawnIds.clear();
      candidates = pool.toList();
      if (candidates.length < _pickCount) {
        _toast('当前范围内不足 $_pickCount 人，请减少抽取人数');
        return;
      }
      _toast('本轮已抽完，自动开始新一轮');
    }
    final rng = Random.secure();
    candidates.shuffle(rng);
    _winners = candidates.take(_pickCount).toList();
    _rollingNames = _winners.map((s) => s.name).toList();
    _drawnIds.addAll(_winners.map((s) => s.id));
    // 写历史期间也锁定抽签与切班，避免快速双击覆盖本次结果。
    setState(() => _phase = _DrawPhase.rolling);
    try {
      await Repo.addDrawLog(classId: _classId!, winners: _winners);
    } catch (_) {
      // 历史记录失败不影响抽签本身。
    }
    if (mounted) _beginRoll();
  }

  void _beginRoll() {
    final poolNames = _pool.map((s) => s.name).toList();
    _rollingNames = [for (final w in _winners) w.name];
    setState(() {
      _phase = _DrawPhase.rolling;
    });
    // 每个槽位约 2 秒后停定，多槽位依次错开，最后一起切到结果页。
    const tickMs = 55;
    final settleTicks = [
      for (var i = 0; i < _winners.length; i++) 36 + i * 9,
    ];
    final maxTick = settleTicks.last;
    _rollTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final names = List<String>.from(_rollingNames);
      for (var i = 0; i < _winners.length; i++) {
        if (t.tick >= settleTicks[i]) {
          names[i] = _winners[i].name;
        } else if (poolNames.isNotEmpty) {
          names[i] = poolNames[(t.tick * 7 + i * 5 + 3) % poolNames.length];
        }
      }
      setState(() => _rollingNames = names);
      if (t.tick >= maxTick) {
        t.cancel();
        if (mounted) setState(() => _phase = _DrawPhase.result);
      }
    });
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Text(
            '🎲 抽签',
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
              onChanged: _loading || _phase == _DrawPhase.rolling
                  ? null
                  : (id) {
                      if (id == null) return;
                      _switchClass(id);
                    },
            ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _classId == null ? null : _showHistory,
            icon: const Icon(Icons.history),
            label: const Text('历史'),
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
    if (_classId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.casino, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            const Text('请先在「名单」页创建班级和学生'),
          ],
        ),
      );
    }
    if (_allStudents.isEmpty) {
      return const Center(child: Text('这个班级还没有学生，请先到「名单」页添加'));
    }
    switch (_phase) {
      case _DrawPhase.idle:
        return _buildIdle(context);
      case _DrawPhase.rolling:
        return _buildRolling(context);
      case _DrawPhase.result:
        return _buildResult(context);
    }
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    final pool = _pool;
    final remaining =
        pool.where((s) => !_noRepeat || !_drawnIds.contains(s.id)).length;
    final drawnNames = [
      for (final id in _drawnIds)
        if (_allStudents.any((s) => s.id == id))
          _allStudents.firstWhere((s) => s.id == id).name,
    ];
    return Column(
      children: [
        const Spacer(),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('抽取人数'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: Slider(
                    value: _pickCount.toDouble(),
                    min: 1,
                    max: 6,
                    divisions: 5,
                    label: '$_pickCount 人',
                    onChanged: (v) => setState(() => _pickCount = v.round()),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$_pickCount 人',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SegmentedButton<String>(
              selected: {_scope},
              onSelectionChanged: _phase == _DrawPhase.rolling
                  ? null
                  : (s) => setState(() => _scope = s.first),
              segments: const [
                ButtonSegment(value: '全班', label: Text('全班')),
                ButtonSegment(value: '男', label: Text('男生')),
                ButtonSegment(value: '女', label: Text('女生')),
              ],
            ),
            DropdownButton<String>(
              value: _groups.contains(_groupFilter) ? _groupFilter : '',
              underline: const SizedBox.shrink(),
              onChanged: _phase == _DrawPhase.rolling
                  ? null
                  : (value) {
                      if (value != null) setState(() => _groupFilter = value);
                    },
              items: [
                for (final group in _groups)
                  DropdownMenuItem(
                      value: group,
                      child: Text(group.isEmpty ? '小组：全部' : '小组：$group')),
              ],
            ),
            DropdownButton<int>(
              value: _memberNumbers.contains(_memberNoFilter)
                  ? _memberNoFilter
                  : -1,
              underline: const SizedBox.shrink(),
              onChanged: _phase == _DrawPhase.rolling
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _memberNoFilter = value);
                      }
                    },
              items: [
                for (final number in _memberNumbers)
                  DropdownMenuItem(
                    value: number,
                    child: Text(number < 0 ? '组员号：全部' : '组员号：$number'),
                  ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _noRepeat,
                  onChanged: (v) => setState(() => _noRepeat = v),
                ),
                const Text('一轮不重复'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 48),
        FilledButton.icon(
          onPressed: _startDraw,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 28),
            textStyle:
                const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          icon: const Text('🎲', style: TextStyle(fontSize: 30)),
          label: const Text('开始抽签'),
        ),
        const SizedBox(height: 32),
        Text(
          '当前范围 ${pool.length} 人 · 本轮剩余 $remaining 人',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (drawnNames.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final name in drawnNames) Chip(label: Text(name)),
            ],
          ),
        if (_drawnIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() => _drawnIds = {}),
            icon: const Icon(Icons.refresh),
            label: const Text('重置本轮'),
          ),
        ],
        const Spacer(),
      ],
    );
  }

  Widget _buildRolling(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Wrap(
        spacing: 28,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < _winners.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              decoration: BoxDecoration(
                color: _rollingNames[i] == _winners[i].name
                    ? ClassManagerApp.yellow
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _rollingNames[i] == _winners[i].name
                      ? ClassManagerApp.ink
                      : ClassManagerApp
                          .candyColors[i % ClassManagerApp.candyColors.length],
                  width: 3,
                ),
              ),
              child: Text(
                _rollingNames[i],
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: _rollingNames[i] == _winners[i].name
                      ? ClassManagerApp.ink
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final nameSize = _winners.length > 2 ? 56.0 : 96.0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _pickCount > 1
                ? '🎉 恭喜这 ${_winners.length} 位同学 🎉'
                : '🎉 恭喜这位同学 🎉',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: ClassManagerApp.ink),
          ),
          const SizedBox(height: 24),
          for (final w in _winners)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutBack,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
                  decoration: BoxDecoration(
                    color: ClassManagerApp.yellow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ClassManagerApp.ink,
                      width: 3,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        w.name,
                        style: TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.bold,
                          color: ClassManagerApp.ink,
                        ),
                      ),
                      if (_studentDetails(w).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _studentDetails(w),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ClassManagerApp.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 40),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _startDraw,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  textStyle: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.replay),
                label: const Text('再抽一次'),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() => _phase = _DrawPhase.idle),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  textStyle: const TextStyle(fontSize: 22),
                ),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showHistory() async {
    final classId = _classId;
    if (classId == null) return;
    final rows = await Repo.listDrawLogs(classId);
    if (!mounted) return;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('抽签历史'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: rows.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return ListTile(
                      dense: true,
                      leading: Text(_fmtTime(r.createdAt),
                          style: theme.textTheme.bodySmall),
                      title: Text(r.names.join('、')),
                      trailing: Text('${r.count} 人'),
                    );
                  },
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _fmtTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  String _studentDetails(Student student) {
    return student.groupLabel;
  }
}
