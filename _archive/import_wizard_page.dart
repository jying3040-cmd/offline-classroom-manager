import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/audio_import.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../services/audio_engine.dart';

/// 导入向导：
/// ① 扫描微信文件目录（自动探测，可手动改）→ ② 勾选音频、拖动排序 →
/// ③ 粘贴词表按顺序对齐 → ④ 连续试听校对 → ⑤ 复制入库。
class ImportWizardPage extends StatefulWidget {
  const ImportWizardPage({super.key, required this.list});

  final WordList list;

  @override
  State<ImportWizardPage> createState() => _ImportWizardPageState();
}

class _ImportWizardPageState extends State<ImportWizardPage> {
  final TextEditingController _paste = TextEditingController();

  String? _dir;
  List<CandidateAudio> _candidates = [];
  bool _scanning = true;
  String? _scanError;
  final List<String> _order = []; // 已选路径，即听写顺序
  final Map<String, CandidateAudio> _byPath = {};
  List<WordImportItem>? _aligned;
  String? _alignError;
  int? _previewIndex;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _resolveDir();
  }

  @override
  void dispose() {
    audioEngine.onCompleted = null;
    audioEngine.stop();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _resolveDir() async {
    var dir = await Repo.getSetting('wechat_audio_dir');
    if (dir == null || !Directory(dir).existsSync()) {
      dir = null;
      for (final c in wechatDirCandidates()) {
        if (Directory(c).existsSync() && findWechatFileDirs(c).isNotEmpty) {
          dir = c;
          break;
        }
      }
    }
    if (dir == null) {
      if (mounted) setState(() => _scanning = false);
      return;
    }
    await Repo.setSetting('wechat_audio_dir', dir);
    await _scan(dir);
  }

  Future<void> _scan(String dir) async {
    setState(() => _scanning = true);
    final candidates = await scanWechatAudio(findWechatFileDirs(dir));
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _candidates = candidates;
      _byPath
        ..clear()
        ..addEntries([for (final c in candidates) MapEntry(c.path, c)]);
      _order
        ..clear()
        ..addAll([for (final c in candidates) if (c.ok) c.path]);
      _aligned = null;
      _alignError = null;
      _previewIndex = null;
      _scanning = false;
      _scanError = candidates.isEmpty ? '最近 30 天在这个目录里没有找到音频文件' : null;
    });
  }

  Future<void> _pickDir() async {
    final controller = TextEditingController(text: _dir ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动指定微信文件目录'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('填微信根目录（下面会自动找 msg\\file 或 FileStorage\\File 的月份文件夹），'
                  '例如 C:\\app\\wechat'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (result == null || result.isEmpty || !mounted) return;
    if (!Directory(result).existsSync()) {
      _toast('目录不存在');
      return;
    }
    if (findWechatFileDirs(result).isEmpty) {
      _toast('该目录下没找到微信月份文件夹');
      return;
    }
    await Repo.setSetting('wechat_audio_dir', result);
    await _scan(result);
  }

  void _toggle(CandidateAudio c) {
    setState(() {
      if (_order.contains(c.path)) {
        _order.remove(c.path);
      } else {
        // 保持按时间顺序插入。
        var insertAt = _order.length;
        for (var i = 0; i < _order.length; i++) {
          final other = _byPath[_order[i]];
          if (other != null && other.mtimeMs > c.mtimeMs) {
            insertAt = i;
            break;
          }
        }
        _order.insert(insertAt, c.path);
      }
      _aligned = null;
      _alignError = null;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final path = _order.removeAt(oldIndex);
      _order.insert(newIndex, path);
      _aligned = null;
    });
  }

  void _align() {
    final lines = _paste.text
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      setState(() {
        _aligned = null;
        _alignError = '请先粘贴词表（一行一个词）';
      });
      return;
    }
    if (lines.length != _order.length) {
      setState(() {
        _aligned = null;
        _alignError = '音频 ${_order.length} 条，词 ${lines.length} 个，数量不一致';
      });
      return;
    }
    final items = <WordImportItem>[];
    for (var i = 0; i < lines.length; i++) {
      final c = _byPath[_order[i]]!;
      final line = lines[i];
      final sep = RegExp(r'[,，:：]').firstMatch(line);
      final word = sep == null ? line : line.substring(0, sep.start).trim();
      final meaning =
          sep == null ? null : line.substring(sep.end).trim();
      if (word.isEmpty) {
        setState(() {
          _aligned = null;
          _alignError = '第 ${i + 1} 行没有词语';
        });
        return;
      }
      items.add(
        WordImportItem(
          sourcePath: c.path,
          ext: '.${c.ext}',
          word: word,
          meaning: meaning == null || meaning.isEmpty ? null : meaning,
          durationMs: c.durationMs,
          origFilename: c.name,
        ),
      );
    }
    setState(() {
      _aligned = items;
      _alignError = null;
    });
  }

  Future<bool> _playAndWait(String path, {required Duration timeout}) async {
    final completer = Completer<void>();
    audioEngine.onCompleted = () {
      if (!completer.isCompleted) completer.complete();
    };
    try {
      await audioEngine.play(path);
    } catch (_) {
      return false;
    }
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    timer.cancel();
    return true;
  }

  Future<void> _previewAll() async {
    for (var i = 0; i < _order.length; i++) {
      if (!mounted) return;
      setState(() => _previewIndex = i);
      await _playAndWait(_order[i], timeout: const Duration(seconds: 20));
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (mounted) setState(() => _previewIndex = null);
  }

  Future<void> _doImport() async {
    final aligned = _aligned;
    if (aligned == null || _importing) return;
    setState(() => _importing = true);
    try {
      final count = await Repo.importWords(listId: widget.list.id, items: aligned);
      if (!mounted) return;
      Navigator.pop(context, count);
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      _toast('导入失败，请重试');
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _fmtTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
  }

  String _fmtDur(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('导入录音 · ${widget.list.title}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sourceCard(theme),
          const SizedBox(height: 12),
          _orderCard(theme),
          const SizedBox(height: 12),
          _pasteCard(theme),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _aligned == null || _importing ? null : _doImport,
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_importing ? '正在导入…' : '完成导入'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _sourceCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _sectionTitle(theme, '第 1 步 · 微信录音文件'),
                const Spacer(),
                TextButton.icon(
                  onPressed: _dir == null ? null : () => _scan(_dir!),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新扫描'),
                ),
                TextButton.icon(
                  onPressed: _pickDir,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('更换文件夹'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              )
            else if (_dir == null)
              const Text(
                '没有自动找到微信文件目录，请点「更换文件夹」手动指定（填微信根目录即可）。',
                style: TextStyle(color: Colors.red),
              )
            else ...[
              SelectableText(
                _dir!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (_scanError != null)
                Text(_scanError!, style: const TextStyle(color: Colors.red))
              else
                ..._candidates.map(_candidateTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _candidateTile(CandidateAudio c) {
    final checked = _order.contains(c.path);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: checked,
        onChanged: c.ok ? (_) => _toggle(c) : null,
      ),
      title: Text(c.name),
      subtitle: Text(
        '${_fmtTime(c.mtimeMs)} · ${c.ext} · ${c.sizeKb}KB'
        '${c.durationMs > 0 ? ' · ${_fmtDur(c.durationMs)}' : ''}'
        '${c.problem == null ? '' : ' · ${c.problem}'}',
        style: TextStyle(
          color: c.problem == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Colors.red,
        ),
      ),
      onTap: c.ok ? () => _toggle(c) : null,
    );
  }

  Widget _orderCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _sectionTitle(theme, '第 2 步 · 听写顺序'),
                const SizedBox(width: 8),
                Text(
                  '${_order.length} 条（默认按录音时间排序，可拖动调整）',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_order.isEmpty)
              const Text('请在上面勾选要导入的音频')
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                itemCount: _order.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, i) {
                  final c = _byPath[_order[i]]!;
                  final highlighted = _previewIndex == i;
                  return ListTile(
                    key: ValueKey(c.path),
                    dense: true,
                    tileColor: highlighted
                        ? theme.colorScheme.primaryContainer
                        : null,
                    leading: Text(
                      '${i + 1}',
                      style: theme.textTheme.titleMedium,
                    ),
                    title: Text(c.name),
                    trailing: c.durationMs > 0
                        ? Text(_fmtDur(c.durationMs))
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _pasteCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, '第 3 步 · 粘贴词表'),
            const SizedBox(height: 4),
            const Text('一行一个词，支持「无价之宝,成语」格式（逗号后为备注）。粘贴后点「对齐」，'
                '会按顺序和上面的音频一一配对。'),
            const SizedBox(height: 8),
            TextField(
              controller: _paste,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '桂花\n无价之宝\n（一行一个，可加逗号备注）',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_aligned != null) setState(() => _aligned = null);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _order.isEmpty ? null : _align,
                  icon: const Icon(Icons.align_horizontal_left, size: 18),
                  label: const Text('对齐'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _order.isEmpty ? null : _previewAll,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('连续试听'),
                ),
                const SizedBox(width: 12),
                if (_aligned != null)
                  const Text(
                    '✓ 已对齐',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            if (_alignError != null) ...[
              const SizedBox(height: 8),
              Text(_alignError!, style: const TextStyle(color: Colors.red)),
            ],
            if (_aligned != null) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < _aligned!.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${i + 1}. ${_aligned![i].word}'
                    '${_aligned![i].meaning == null ? '' : '（${_aligned![i].meaning}）'}'
                    '  ← ${_aligned![i].origFilename}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
