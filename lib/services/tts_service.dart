import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Windows SAPI 文字转语音（离线）：词语 → 标准普通话发音 wav。
/// 通过 PowerShell 调 .NET System.Speech，一次进程批量合成整批词语。
/// 语音优先选 zh-CN（如 Microsoft Huihui），没有中文语音时退回系统默认。
class TtsService {
  /// 为每个条目生成 <fileName>.wav 到 [outDir]。
  /// 返回成功生成的条目下标列表（文件存在即视为成功）。
  static Future<List<int>> generate({
    required String outDir,
    required List<({String fileName, String word})> items,
  }) async {
    if (items.isEmpty) return const [];
    Directory(outDir).createSync(recursive: true);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final listFile = File(p.join(Directory.systemTemp.path, 'tts_list_$stamp.txt'));
    final scriptFile = File(p.join(Directory.systemTemp.path, 'tts_batch_$stamp.ps1'));
    listFile.writeAsStringSync(
      items.map((e) => '${e.fileName}|${e.word}').join('\r\n'),
      encoding: utf8,
      flush: true,
    );
    scriptFile.writeAsStringSync(_psScript, encoding: utf8, flush: true);

    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
          '-listPath',
          listFile.path,
          '-outDir',
          outDir,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode != 0) {
        throw Exception('TTS 生成失败: ${r.stderr}');
      }
    } finally {
      try {
        listFile.deleteSync();
        scriptFile.deleteSync();
      } catch (_) {}
    }

    final ok = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (File(p.join(outDir, '${items[i].fileName}.wav')).existsSync()) {
        ok.add(i);
      }
    }
    return ok;
  }

  static const String _psScript = r'''
param([string]$listPath, [string]$outDir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
  $zh = $synth.GetInstalledVoices() |
    Where-Object { $_.VoiceInfo.Culture.Name -like 'zh*' } |
    Sort-Object { if ($_.VoiceInfo.Culture.Name -eq 'zh-CN') { 0 } else { 1 } } |
    Select-Object -First 1
  if ($zh) { $synth.SelectVoice($zh.VoiceInfo.Name) }
  # 略慢于常速，课堂听写更清晰。
  $synth.Rate = -1
  Get-Content -Path $listPath -Encoding UTF8 | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    $idx = $_.IndexOf('|')
    if ($idx -lt 1) { return }
    $file = $_.Substring(0, $idx)
    $word = $_.Substring($idx + 1)
    $synth.SetOutputToWaveFile((Join-Path $outDir ($file + '.wav')))
    $synth.Speak($word)
  }
} finally {
  $synth.Dispose()
}
''';
}
