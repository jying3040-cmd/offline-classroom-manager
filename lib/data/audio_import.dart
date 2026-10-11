import 'dart:io';
import 'dart:typed_data';

/// 听写录音导入：微信文件目录发现 + 音频格式体检（不信任扩展名）。

class CandidateAudio {
  CandidateAudio({
    required this.path,
    required this.name,
    required this.ext,
    required this.sizeKb,
    required this.mtimeMs,
    required this.durationMs,
    required this.ok,
    this.problem,
  });

  final String path;
  final String name;
  final String ext;
  final int sizeKb;
  final int mtimeMs;
  final int durationMs;
  final bool ok;
  final String? problem;
}

class AudioProbe {
  const AudioProbe({
    required this.ok,
    required this.format,
    required this.durationMs,
    this.problem,
  });

  final bool ok;
  final String format;
  final int durationMs;
  final String? problem;
}

const Set<String> _audioExts = {'.m4a', '.mp3', '.wav', '.aac', '.amr'};

/// 常见微信安装/文件根目录（新版 4.x 与旧版 3.x 结构都覆盖）。
List<String> wechatDirCandidates() {
  final user = Platform.environment['USERPROFILE'] ?? r'C:\Users\7';
  return [
    r'C:\app\wechat',
    '$user\\Documents',
    r'C:\Program Files\Tencent\WeChat',
    r'C:\Program Files (x86)\Tencent\WeChat',
  ];
}

String _fileNameOf(String path) {
  final i = path.lastIndexOf('\\');
  return i < 0 ? path : path.substring(i + 1);
}

List<Directory> _monthDirs(Directory base) {
  final re = RegExp(r'^\d{4}-\d{2}$');
  final out = <Directory>[];
  for (final e in base.listSync()) {
    if (e is Directory && re.hasMatch(_fileNameOf(e.path))) {
      out.add(e);
    }
  }
  return out;
}

/// 在微信根目录下寻找所有月份文件目录：
/// 新版: <root>\xwechat_files\<账号>\msg\file\<年-月>
/// 旧版: <root>\WeChat Files\<账号>\FileStorage\File\<年-月>
List<Directory> findWechatFileDirs(String root) {
  final out = <Directory>[];
  final parent = Directory(root);
  if (!parent.existsSync()) return out;
  for (final lvl1 in parent.listSync()) {
    if (lvl1 is! Directory) continue;
    final name = _fileNameOf(lvl1.path);
    if (name == 'xwechat_files') {
      for (final lvl2 in lvl1.listSync()) {
        if (lvl2 is! Directory) continue;
        final mf = Directory('${lvl2.path}\\msg\\file');
        if (mf.existsSync()) out.addAll(_monthDirs(mf));
      }
    } else if (name == 'WeChat Files') {
      for (final lvl2 in lvl1.listSync()) {
        if (lvl2 is! Directory) continue;
        final fs = Directory('${lvl2.path}\\FileStorage\\File');
        if (fs.existsSync()) out.addAll(_monthDirs(fs));
      }
    }
  }
  return out;
}

/// 扫描月份目录里的音频文件（默认最近 30 天），按修改时间倒序。
Future<List<CandidateAudio>> scanWechatAudio(
  List<Directory> monthDirs, {
  int withinDays = 30,
}) async {
  final cutoff =
      DateTime.now().millisecondsSinceEpoch - withinDays * 86400000;
  final seen = <String>{};
  final out = <CandidateAudio>[];
  for (final d in monthDirs) {
    for (final e in d.listSync()) {
      if (e is! File) continue;
      if (seen.contains(e.path)) continue;
      seen.add(e.path);
      final dot = e.path.lastIndexOf('.');
      final ext = dot < 0 ? '' : e.path.substring(dot).toLowerCase();
      if (!_audioExts.contains(ext)) continue;
      final st = e.statSync();
      final mtime = st.modified.millisecondsSinceEpoch;
      if (mtime < cutoff) continue;
      final probe = probeAudioFile(e.path);
      out.add(
        CandidateAudio(
          path: e.path,
          name: _fileNameOf(e.path),
          ext: ext.substring(1),
          sizeKb: (st.size / 1024).round(),
          mtimeMs: mtime,
          durationMs: probe.durationMs,
          ok: probe.ok,
          problem: probe.problem,
        ),
      );
    }
  }
  out.sort((a, b) => b.mtimeMs.compareTo(a.mtimeMs));
  return out;
}

/// 读文件头魔数验证格式并解析时长。文件都很小（几百 KB），整读无压力。
AudioProbe probeAudioFile(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 12) {
      return const AudioProbe(ok: false, format: '?', durationMs: 0, problem: '文件太小，疑似不完整');
    }
    if (String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      return _probeM4a(bytes);
    }
    if (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE') {
      return _probeWav(bytes);
    }
    if (String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
      return _probeMp3(bytes);
    }
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return _probeMp3(bytes);
    }
    if (String.fromCharCodes(bytes.sublist(0, 5)) == '#!AMR') {
      return const AudioProbe(
        ok: false,
        format: 'amr',
        durationMs: 0,
        problem: 'AMR 无法直接播放，请在手机录音设置改为 m4a 或 wav',
      );
    }
    return const AudioProbe(ok: false, format: '未知', durationMs: 0, problem: '无法识别的文件格式');
  } on FileSystemException {
    return const AudioProbe(ok: false, format: '?', durationMs: 0, problem: '读取失败：文件被占用或正在下载');
  } catch (_) {
    return const AudioProbe(ok: false, format: '?', durationMs: 0, problem: '读取失败');
  }
}

int _u32(Uint8List b, int o) =>
    ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) &
    0xFFFFFFFF;

int _u64(Uint8List b, int o) => _u32(b, o) * 4294967296 + _u32(b, o + 4);

int _indexOf(List<int> b, List<int> pattern, [int start = 0]) {
  outer:
  for (var i = start; i <= b.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (b[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

AudioProbe _probeM4a(Uint8List b) {
  final idx = _indexOf(b, 'mvhd'.codeUnits);
  if (idx < 0 || idx + 36 > b.length) {
    return const AudioProbe(ok: true, format: 'm4a', durationMs: 0);
  }
  final version = b[idx + 4];
  int timescale;
  int duration;
  if (version == 0) {
    timescale = _u32(b, idx + 16);
    duration = _u32(b, idx + 20);
  } else {
    timescale = _u32(b, idx + 24);
    duration = _u64(b, idx + 28);
  }
  final ms = timescale > 0 ? (duration / timescale * 1000).round() : 0;
  return AudioProbe(ok: true, format: 'm4a', durationMs: ms);
}

AudioProbe _probeWav(Uint8List b) {
  if (b.length < 44) {
    return const AudioProbe(ok: false, format: 'wav', durationMs: 0, problem: 'WAV 文件不完整');
  }
  final fmtSize = _u32(b, 16);
  final byteRate = _u32(b, 28);
  var pos = 20 + fmtSize;
  while (pos + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(pos, pos + 4));
    final chunkSize = _u32(b, pos + 4);
    if (id == 'data') {
      final ms = byteRate > 0 ? (chunkSize / byteRate * 1000).round() : 0;
      return AudioProbe(ok: true, format: 'wav', durationMs: ms);
    }
    pos += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  return const AudioProbe(ok: true, format: 'wav', durationMs: 0);
}

AudioProbe _probeMp3(Uint8List b) {
  var offset = 0;
  if (b.length >= 10 && String.fromCharCodes(b.sublist(0, 3)) == 'ID3') {
    offset =
        10 + ((b[6] & 0x7F) << 21 | (b[7] & 0x7F) << 14 | (b[8] & 0x7F) << 7 | (b[9] & 0x7F));
  }
  var i = offset;
  while (i < b.length - 4 && !(b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0)) {
    i++;
  }
  if (i >= b.length - 4) {
    return const AudioProbe(ok: false, format: 'mp3', durationMs: 0, problem: 'MP3 帧头解析失败');
  }
  const bitratesV1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
  const bitratesV2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
  const ratesV1 = [44100, 48000, 32000];
  const ratesV2 = [22050, 24000, 16000];
  const ratesV25 = [11025, 12000, 8000];
  final versionBits = (b[i + 1] >> 3) & 3;
  final bitrateIdx = (b[i + 2] >> 4) & 0xF;
  final rateIdx = (b[i + 2] >> 2) & 3;
  final int kbps;
  final int hz;
  if (versionBits == 3) {
    kbps = bitratesV1[bitrateIdx];
    hz = rateIdx < 3 ? ratesV1[rateIdx] : 0;
  } else if (versionBits == 2) {
    kbps = bitratesV2[bitrateIdx];
    hz = rateIdx < 3 ? ratesV2[rateIdx] : 0;
  } else if (versionBits == 0) {
    kbps = bitratesV2[bitrateIdx];
    hz = rateIdx < 3 ? ratesV25[rateIdx] : 0;
  } else {
    return const AudioProbe(ok: false, format: 'mp3', durationMs: 0, problem: 'MP3 版本不支持');
  }
  if (kbps == 0 || hz == 0) {
    return const AudioProbe(ok: false, format: 'mp3', durationMs: 0, problem: 'MP3 参数异常');
  }
  final ms = ((b.length - offset) * 8 / (kbps * 1000) * 1000).round();
  return AudioProbe(ok: true, format: 'mp3', durationMs: ms);
}
