import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../data/audio_import.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../data/textbook_words.dart';
import 'tts_service.dart';

/// 导入结果：新建组数 / 新建词数 / 因重名跳过的组数。
class SeedResult {
  SeedResult({
    required this.createdLists,
    required this.createdWords,
    required this.skippedLists,
  });

  final int createdLists;
  final int createdWords;
  final int skippedLists;
}

/// 一键导入教材《词语表》：
/// - 只新增：已有同名词表的组自动跳过，绝不触碰用户数据；
/// - 发音优先取应用内打包的离线语音（assets/tts_seed），缺失才现场 TTS；
/// - 中途失败可重跑，已导入的组不会重复。
class TextbookSeedService {
  static const String _subject = '语文';

  static String _assetPath(TextbookGroup g, int wordIndex) =>
      'assets/tts_seed/${g.dir}/w${(wordIndex + 1).toString().padLeft(2, '0')}.wav';

  static Future<SeedResult> run({
    void Function(int done, int total, String title)? onProgress,
  }) async {
    final existingTitles =
        (await Repo.listWordLists()).map((e) => e.title).toSet();
    var createdLists = 0;
    var createdWords = 0;
    var skippedLists = 0;
    var done = 0;
    final total = textbookGroups.length;

    // 倒序创建：词表列表按创建时间倒序展示，倒序插入后第1课排在最前。
    for (final g in textbookGroups.reversed) {
      try {
        if (existingTitles.contains(g.title)) {
          skippedLists++;
        } else {
          createdWords += await _importGroup(g);
          createdLists++;
          // 保证各组创建时间错开（列表按时间排序）。
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      } finally {
        done++;
        onProgress?.call(done, total, g.title);
      }
    }
    return SeedResult(
      createdLists: createdLists,
      createdWords: createdWords,
      skippedLists: skippedLists,
    );
  }

  static Future<int> _importGroup(TextbookGroup g) async {
    final list = await Repo.createWordList(g.title, subject: _subject);
    final tmpDir = Directory(p.join(
      Directory.systemTemp.path,
      'seed_${g.dir}_${DateTime.now().millisecondsSinceEpoch}',
    ));
    tmpDir.createSync(recursive: true);
    final items = <WordImportItem>[];
    final missing = <({String fileName, String word})>[];
    try {
      // 先取打包发音；缺失的收集起来最后一次性 TTS 兜底。
      for (var i = 0; i < g.words.length; i++) {
        final word = g.words[i];
        final fileName = 'w${(i + 1).toString().padLeft(2, '0')}';
        final target = p.join(tmpDir.path, '$fileName.wav');
        try {
          final data = await rootBundle.load(_assetPath(g, i));
          File(target).writeAsBytesSync(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        } catch (_) {
          missing.add((fileName: fileName, word: word));
          continue;
        }
        items.add(_item(target, word));
      }
      if (missing.isNotEmpty) {
        final ok = await TtsService.generate(outDir: tmpDir.path, items: missing);
        for (final i in ok) {
          final m = missing[i];
          items.add(_item(p.join(tmpDir.path, '${m.fileName}.wav'), m.word));
        }
      }
      if (items.isEmpty) {
        throw Exception('「${g.title}」没有任何可用语音');
      }
      await Repo.importWords(listId: list.id, items: items);
    } finally {
      try {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {
        // 临时目录清理失败不阻塞（系统会回收）。
      }
    }
    return items.length;
  }

  static WordImportItem _item(String sourcePath, String word) {
    final probe = probeAudioFile(sourcePath);
    return WordImportItem(
      sourcePath: sourcePath,
      ext: '.wav',
      word: word,
      durationMs: probe.durationMs,
      origFilename: '$word.wav',
    );
  }
}
