import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/audio_import.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../services/tts_service.dart';

const _uuid = Uuid();

/// 输入词语 → 自动生成标准普通话发音 → 加入词表。
/// 词表分类归纳逻辑与录音导入完全一致。
class TtsInputPage extends StatefulWidget {
  const TtsInputPage({super.key, required this.list});

  final WordList list;

  @override
  State<TtsInputPage> createState() => _TtsInputPageState();
}

class _TtsInputPageState extends State<TtsInputPage> {
  final TextEditingController _paste = TextEditingController();
  bool _generating = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final lines = _paste.text
        .split(RegExp(r'[\n\r;；]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      _toast('请先输入词语（一行一个）');
      return;
    }
    setState(() {
      _generating = true;
    });

    final tmpDir = Directory(
        p.join(Directory.systemTemp.path, 'tts_gen_${DateTime.now().millisecondsSinceEpoch}'));
    final items = <({String fileName, String word})>[];
    final parsed = <({String word, String? meaning})>[];
    for (final line in lines) {
      final m = RegExp(r'[,，:：]').firstMatch(line);
      final word = m == null ? line : line.substring(0, m.start).trim();
      final meaning = m == null ? null : line.substring(m.end).trim();
      if (word.isEmpty) continue;
      final fileName = _uuid.v4();
      items.add((fileName: fileName, word: word));
      parsed.add((
        word: word,
        meaning: meaning == null || meaning.isEmpty ? null : meaning,
      ));
    }

    try {
      final okIdx = await TtsService.generate(outDir: tmpDir.path, items: items);
      final importItems = <WordImportItem>[];
      for (final i in okIdx) {
        final wav = File(p.join(tmpDir.path, '${items[i].fileName}.wav'));
        final probe = probeAudioFile(wav.path);
        importItems.add(WordImportItem(
          sourcePath: wav.path,
          ext: '.wav',
          word: parsed[i].word,
          meaning: parsed[i].meaning,
          durationMs: probe.durationMs,
          origFilename: '${parsed[i].word}.wav',
        ));
      }
      if (importItems.isEmpty) {
        _toast('语音生成失败：系统可能缺少中文语音组件');
        return;
      }
      final count =
          await Repo.importWords(listId: widget.list.id, items: importItems);
      if (!mounted) return;
      Navigator.pop(context, count);
    } catch (_) {
      if (!mounted) return;
      _toast('生成失败，请重试');
    } finally {
      try {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('输入词语 · ${widget.list.title}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('输入词语，自动生成标准普通话发音',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                      '一行一个词语，支持「无价之宝,四字词语」格式（逗号后为备注，可不填）。'
                      '生成使用 Windows 内置的标准中文语音，全程离线、无需录音。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paste,
            maxLines: 12,
            enabled: !_generating,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '桂花\n故乡,课文第一课\n（换行或分号分隔）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generating || _paste.text.trim().isEmpty
                ? null
                : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _generating ? '正在生成语音，请稍候…' : '生成语音并添加',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}
