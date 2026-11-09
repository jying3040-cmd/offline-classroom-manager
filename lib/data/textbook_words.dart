/// 可选教材词表。默认不包含预置词语。
///
/// 每个词的普通话发音随应用打包在 `assets/tts_seed/<dir>/wNN.wav`，
/// 「一键导入教材词表」时复制进应用数据目录；个别缺失时回退现场 TTS 合成。
class TextbookGroup {
  const TextbookGroup(this.title, this.dir, this.words);

  /// 词表标题（列表页展示，也用于重复导入判断）。
  final String title;

  /// assets/tts_seed 下该组音频的子目录名。
  final String dir;

  /// 听写顺序 = 书写顺序。
  final List<String> words;
}

const List<TextbookGroup> textbookGroups = [];

/// 词表总数。
final int textbookGroupCount = textbookGroups.length;

/// 词语总数。
final int textbookWordCount =
    textbookGroups.fold(0, (sum, g) => sum + g.words.length);
