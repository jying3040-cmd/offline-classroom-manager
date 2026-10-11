import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/repo.dart';

/// 名单管理：班级切换、学生增删改、批量导入。
class RosterPage extends StatefulWidget {
  const RosterPage({super.key});

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  List<Klass> _classes = [];
  List<Student> _students = [];
  Map<String, int> _flowerTotals = const {};
  String? _currentClassId;
  bool _loading = true;

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
      if (_currentClassId == null ||
          !_classes.any((c) => c.id == _currentClassId)) {
        _currentClassId = classes.isEmpty ? null : classes.first.id;
      }
      _loading = false;
    });
    await _loadStudents();
  }

  Future<void> _loadStudents() async {
    final classId = _currentClassId;
    if (classId == null) {
      if (!mounted) return;
      setState(() {
        _students = [];
        _flowerTotals = const {};
      });
      return;
    }
    final students = await Repo.listStudents(classId);
    final flowerTotals = await Repo.flowerTotals(classId);
    if (!mounted) return;
    setState(() {
      _students = students;
      _flowerTotals = flowerTotals;
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
            '👦 学生名单',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),
          if (_classes.isNotEmpty)
            DropdownButton<String>(
              value: _currentClassId,
              underline: const SizedBox.shrink(),
              items: [
                for (final c in _classes)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) {
                if (id == null) return;
                setState(() => _currentClassId = id);
                _loadStudents();
              },
            ),
          if (_currentClassId != null) ...[
            const SizedBox(width: 8),
            Text(
              '${_students.length} 人',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: _currentClassId == null ? null : _batchImport,
            icon: const Icon(Icons.upload),
            label: const Text('批量导入'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed:
                _currentClassId == null ? null : () => _openStudentDialog(),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('添加学生'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _addClass,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('新建班级'),
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
    if (_classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_2, size: 80, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            const Text('还没有班级，先新建一个班级吧'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addClass,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新建班级'),
            ),
          ],
        ),
      );
    }
    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('这个班级还没有学生'),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _openStudentDialog(),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('添加学生'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _batchImport,
                  icon: const Icon(Icons.upload),
                  label: const Text('批量导入'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
      ),
      itemCount: _students.length,
      itemBuilder: (context, i) {
        final s = _students[i];
        return _StudentCard(
          student: s,
          accent: ClassManagerApp
              .candyColors[i % ClassManagerApp.candyColors.length],
          flowerCount: _flowerTotals[s.id] ?? 0,
          onTap: () => _openStudentDialog(s),
        );
      },
    );
  }

  // ---------- 班级操作 ----------

  Future<void> _addClass() async {
    final name = await _promptText(title: '新建班级', hint: '例如：三年级2班');
    if (name == null || name.trim().isEmpty) return;
    final klass = await Repo.addClass(name);
    if (!mounted) return;
    setState(() => _currentClassId = klass.id);
    await _reload();
  }

  // ---------- 学生操作 ----------

  /// [existing] 为空表示新增，否则为编辑。
  Future<void> _openStudentDialog([Student? existing]) async {
    if (_currentClassId == null) return;
    final result =
        await showDialog<(String, String?, int?, String?, String?, int?)>(
      context: context,
      builder: (_) => _StudentDialog(student: existing),
    );
    if (!mounted || result == null) return;
    final (action, name, seat, gender, group, member) = result;
    if (action == 'delete') {
      if (existing == null) return;
      final ok = await _confirm('删除学生', '确定删除「${existing.name}」吗？');
      if (!ok) return;
      await Repo.deleteStudent(existing.id);
      if (!mounted) return;
      _toast('已删除 ${existing.name}');
    } else if (action == 'save') {
      if (name == null || name.trim().isEmpty) return;
      if (existing == null) {
        await Repo.addStudent(
          classId: _currentClassId!,
          name: name,
          seatNo: seat,
          gender: gender,
          groupName: group,
          memberNo: member,
        );
        if (!mounted) return;
        _toast('已添加 ${name.trim()}');
      } else {
        await Repo.updateStudent(
          existing: existing,
          name: name,
          seatNo: seat,
          gender: gender,
          groupName: group,
          memberNo: member,
        );
        if (!mounted) return;
        _toast('已保存');
      }
    }
    await _loadStudents();
  }

  Future<void> _batchImport() async {
    final classId = _currentClassId;
    if (classId == null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _BatchImportDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    if (!mounted) return;
    // 支持换行或中英文逗号分隔，自动去重并保持顺序。
    final names = text
        .split(RegExp(r'[\n\r,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final count = await Repo.addStudentsByName(classId: classId, names: names);
    if (!mounted) return;
    _toast('已导入 $count 名学生');
    await _loadStudents();
  }

  // ---------- 通用小部件与工具 ----------

  Future<String?> _promptText({
    required String title,
    String? hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<bool> _confirm(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _BatchImportDialog extends StatefulWidget {
  const _BatchImportDialog();

  @override
  State<_BatchImportDialog> createState() => _BatchImportDialogState();
}

class _BatchImportDialogState extends State<_BatchImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('批量导入学生'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('每行一个名字（也支持逗号分隔），重复名字自动忽略：'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: '张小明\n李小红\n王小刚',
                border: OutlineInputBorder(),
              ),
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
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('导入'),
        ),
      ],
    );
  }
}

class _StudentDialog extends StatefulWidget {
  const _StudentDialog({this.student});

  final Student? student;

  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<_StudentDialog> {
  late final TextEditingController _name;
  late final TextEditingController _seat;
  late final TextEditingController _group;
  late final TextEditingController _member;
  String? _memberError;
  String? _gender;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.student?.name ?? '');
    _seat = TextEditingController(
      text: widget.student?.seatNo?.toString() ?? '',
    );
    _gender = widget.student?.gender;
    _group = TextEditingController(text: widget.student?.groupName ?? '');
    _member =
        TextEditingController(text: widget.student?.memberNo?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _seat.dispose();
    _group.dispose();
    _member.dispose();
    super.dispose();
  }

  void _pop(String action) {
    final memberText = _member.text.trim();
    final member = int.tryParse(memberText);
    if (action == 'save' &&
        memberText.isNotEmpty &&
        (member == null || member <= 0)) {
      setState(() => _memberError = '请输入正整数');
      return;
    }
    final seat = int.tryParse(_seat.text.trim());
    Navigator.pop(
      context,
      (action, _name.text.trim(), seat, _gender, _group.text.trim(), member),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.student == null;
    return AlertDialog(
      title: Text(isNew ? '添加学生' : '编辑学生'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '姓名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _seat,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '学号（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: '性别',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('未设置')),
                      DropdownMenuItem(value: '男', child: Text('男')),
                      DropdownMenuItem(value: '女', child: Text('女')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: TextField(
                  controller: _group,
                  decoration: const InputDecoration(
                    labelText: '小组名称（可选）',
                    hintText: '例如：阳光 或 1',
                    suffixText: '小组',
                    border: OutlineInputBorder(),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                  controller: _member,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '组员号（可选）',
                    suffixText: '号组员',
                    errorText: _memberError,
                    border: const OutlineInputBorder(),
                  ),
                )),
              ],
            ),
          ],
        )),
      ),
      actions: [
        if (!isNew)
          TextButton(
            onPressed: () => _pop('delete'),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _pop('save'),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.accent,
    required this.flowerCount,
    required this.onTap,
  });

  final Student student;
  final Color accent;
  final int flowerCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (student.seatNo != null) '学号 ${student.seatNo}',
      if (student.gender != null && student.gender!.isNotEmpty) student.gender!,
      if (student.groupLabel.isNotEmpty) student.groupLabel,
      if (flowerCount > 0) '🌸 $flowerCount',
    ].join(' · ');
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent, width: 3),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: accent,
                child: Text(
                  student.name.substring(0, 1),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.isEmpty ? '点击编辑' : subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
