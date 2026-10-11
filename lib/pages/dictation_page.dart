import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../data/textbook_words.dart';
import '../services/textbook_seed_service.dart';
import 'dictation_player_page.dart';
import 'tts_input_page.dart';

/// 听写模块：词表列表 → 词表详情 →（输入词语 / 开始听写）。
class DictationPage extends StatefulWidget {
  const DictationPage({super.key});

  @override
  State<DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<DictationPage> {
  List<WordList> _lists = [];
  WordList? _current;
  List<Word> _words = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadLists();
  }

  Future<void> _reloadLists() async {
    final lists = await Repo.listWordLists();
    if (!mounted) return;
    setState(() {
      _lists = lists;
      _loading = false;
    });
  }

  Future<void> _openList(WordList list) async {
    setState(() => _current = list);
    final words = await Repo.listWords(list.id);
    if (!mounted) return;
    setState(() => _words = words);
  }

  Future<void> _back() async {
    setState(() => _current = null);
    await _reloadLists();
  }

  Future<void> _createList() async {
    final title = await _promptText('新建词表', '例如：第四单元 / 期中复习');
    if (title == null || title.trim().isEmpty) return;
    final list = await Repo.createWordList(title);
    if (!mounted) return;
    await _openList(list);
  }

  /// 一键导入教材《词语表》：按课文建组，内置离线普通话发音。
  Future<void> _importTextbook() async {
    final ok = await _confirm(
      '一键导入教材词表',
      '将按课文创建 ${textbookGroups.length} 组词表，共 $textbookWordCount 个词语，'
          '自动配好内置的离线普通话发音。\n\n'
          '已有的同名词表会自动跳过，不影响任何现有数据。',
    );
    if (!ok) return;
    if (!mounted) return;

    final state = ValueNotifier<(double, String)>((0, '准备导入…'));
    var done = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在导入教材词表'),
          content: ValueListenableBuilder<(double, String)>(
            valueListenable: state,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: value.$1, minHeight: 10),
                const SizedBox(height: 16),
                Text(value.$2),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final res = await TextbookSeedService.run(
        onProgress: (d, total, title) {
          done = d;
          state.value = (d / total, '正在导入「$title」（$d/$total）…');
        },
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (res.createdLists == 0) {
        _toast('教材词表已齐全，本次未新增（跳过 ${res.skippedLists} 组）');
      } else {
        _toast(
          '已新建 ${res.createdLists} 组词表、共 ${res.createdWords} 个词语'
          '${res.skippedLists > 0 ? '，跳过已存在的 ${res.skippedLists} 组' : ''}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast('导入失败（已完成 $done/${textbookGroups.length} 组，可重新点导入续传）：$e');
    }
    if (mounted) await _reloadLists();
  }

  Future<void> _inputWords(WordList list) async {
    final count = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => TtsInputPage(list: list)),
    );
    if (!mounted) return;
    if (count != null && count > 0) {
      _toast('已生成并添加 $count 个词语');
    }
    await _openList(list);
  }

  /// 词表行上直接开始听写（省一次进入详情的点击）。
  Future<void> _startFromList(WordList list) async {
    final words = await Repo.listWords(list.id);
    if (!mounted) return;
    if (words.isEmpty) {
      _toast('这个词表还没有词条');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DictationPlayerPage(list: list, words: words),
      ),
    );
    if (mounted) await _reloadLists();
  }

  Future<void> _startDictation() async {
    final list = _current;
    if (list == null) return;
    if (_words.isEmpty) {
      _toast('这个词表还没有词条，请先输入词语');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DictationPlayerPage(list: list, words: _words),
      ),
    );
    if (mounted) await _openList(list);
  }

  Future<void> _deleteList(WordList list) async {
    final ok = await _confirm(
      '删除词表',
      '确定删除「${list.title}」及其全部 ${list.wordCount} 个词条和录音吗？不可恢复。',
    );
    if (!ok) return;
    await Repo.deleteWordList(list.id);
    if (!mounted) return;
    _toast('已删除');
    if (_current?.id == list.id) {
      setState(() => _current = null);
    }
    await _reloadLists();
  }

  Future<void> _deleteWord(Word w) async {
    final ok = await _confirm('删除词条', '确定删除「${w.text}」吗？');
    if (!ok) return;
    await Repo.deleteWord(w);
    if (!mounted) return;
    setState(() => _words.remove(w));
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
          if (_current != null)
            IconButton(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回词表列表',
            ),
          Text(
            _current?.title == null
              ? '🔊 听写'
              : _current!.title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (_current != null) ...[
            const SizedBox(width: 8),
            Text(
              '${_words.length} 个词',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const Spacer(),
          if (_current == null) ...[
            OutlinedButton.icon(
              onPressed: _importTextbook,
              icon: const Icon(Icons.menu_book),
              label: const Text('一键导入教材词表'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _createList,
              icon: const Icon(Icons.playlist_add),
              label: const Text('新建词表'),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: () => _deleteList(_current!),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除词表'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _inputWords(_current!),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('输入词语'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _startDictation,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始听写'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_current == null) {
      if (_lists.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.record_voice_over,
                  size: 72, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              const Text(
                '还没有词表。一键导入教材《词语表》，'
                '每课一组、自动配好普通话发音；\n也可以新建词表自己录入词语。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: _importTextbook,
                    icon: const Icon(Icons.menu_book),
                    label: const Text('一键导入教材词表'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _createList,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('新建词表'),
                  ),
                ],
              ),
            ],
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _lists.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final l = _lists[i];
          return ListTile(
            leading: const Text('📋', style: TextStyle(fontSize: 26)),
            title: Text(l.title, style: theme.textTheme.titleMedium),
            subtitle: Text(
              '${l.wordCount} 个词'
              '${(l.subject == null || l.subject!.isEmpty) ? '' : ' · ${l.subject}'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _startFromList(l),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始听写'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除词表',
                  onPressed: () => _deleteList(l),
                ),
              ],
            ),
            onTap: () => _openList(l),
          );
        },
      );
    }
    // 词表详情
    if (_words.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            const Text('一行输入一个词语，即可自动生成标准普通话发音'),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _inputWords(_current!),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('输入词语'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _words.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final w = _words[i];
        final dur = w.durationMs;
        return ListTile(
          leading: Text(
            '${i + 1}',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          title: Text(w.text, style: theme.textTheme.titleMedium),
          subtitle: w.meaning == null ? null : Text(w.meaning!),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dur != null && dur > 0)
                Text(
                  '${(dur / 1000).toStringAsFixed(1)}s',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteWord(w),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _promptText(String title, String? hint) {
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
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
