import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services/audio_engine.dart';

enum _Phase { config, playing, waiting, paused, finished }

/// 听写播放器。
/// 状态机：播放单词 →（重复遍数）→ 作答间隔 → 下一题 → … → 对答案。
/// 界面只显示题号，绝不显示单词内容，防止偷看。
class DictationPlayerPage extends StatefulWidget {
  const DictationPlayerPage({super.key, required this.list, required this.words});

  final WordList list;
  final List<Word> words;

  @override
  State<DictationPlayerPage> createState() => _DictationPlayerPageState();
}

class _DictationPlayerPageState extends State<DictationPlayerPage> {
  bool _shuffle = false;
  int _intervalSec = 15;
  int _repeats = 2;

  List<Word> _order = [];
  int _pos = 0;
  int _repeatLeft = 0;
  _Phase _phase = _Phase.config;
  Timer? _timer;
  Timer? _ticker;
  int _remainMs = 0;
  int _remainStart = 0;
  bool _pausedDuringWait = false;
  void Function()? _waitNext;

  @override
  void initState() {
    super.initState();
    audioEngine.onCompleted = _onAudioCompleted;
  }

  @override
  void dispose() {
    audioEngine.onCompleted = null;
    audioEngine.stop();
    _timer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Word get _current => _order[_pos];

  void _begin() {
    _order = [...widget.words];
    if (_shuffle) {
      _order.shuffle(Random.secure());
    }
    _pos = 0;
    _repeatLeft = _repeats - 1;
    setState(() => _phase = _Phase.playing);
    _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (!mounted) return;
    setState(() => _phase = _Phase.playing);
    try {
      await audioEngine.play(_current.audioFile);
    } catch (_) {
      _toast('「${_current.text}」音频播放失败，已跳过');
      _advance();
    }
  }

  void _onAudioCompleted() {
    if (!mounted || _phase != _Phase.playing) return;
    if (_repeatLeft > 0) {
      _repeatLeft--;
      _wait(const Duration(seconds: 2), _playCurrent);
    } else {
      _wait(Duration(seconds: _intervalSec), _advance);
    }
  }

  void _advance() {
    if (!mounted) return;
    if (_pos < _order.length - 1) {
      setState(() => _pos++);
      _repeatLeft = _repeats - 1;
      _playCurrent();
    } else {
      _finish();
    }
  }

  void _wait(Duration d, void Function() next) {
    _waitNext = next;
    _timer?.cancel();
    _remainMs = d.inMilliseconds;
    _remainStart = DateTime.now().millisecondsSinceEpoch;
    setState(() => _phase = _Phase.waiting);
    _timer = Timer(d, _fireWait);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _phase == _Phase.waiting) {
        setState(() {});
      }
    });
  }

  void _fireWait() {
    _ticker?.cancel();
    final next = _waitNext;
    _waitNext = null;
    if (next != null && mounted) next();
  }

  void _pause() {
    if (_phase == _Phase.waiting) {
      _pausedDuringWait = true;
      _timer?.cancel();
      final elapsed = DateTime.now().millisecondsSinceEpoch - _remainStart;
      _remainMs = (_remainMs - elapsed).clamp(0, _remainMs);
      setState(() => _phase = _Phase.paused);
    } else if (_phase == _Phase.playing) {
      _pausedDuringWait = false;
      audioEngine.pause();
      setState(() => _phase = _Phase.paused);
    }
  }

  void _resume() {
    if (_phase != _Phase.paused) return;
    if (_pausedDuringWait) {
      setState(() => _phase = _Phase.waiting);
      _remainStart = DateTime.now().millisecondsSinceEpoch;
      _timer = Timer(Duration(milliseconds: _remainMs), _fireWait);
    } else {
      setState(() => _phase = _Phase.playing);
      audioEngine.resume();
    }
  }

  void _replayCurrent() {
    _timer?.cancel();
    _ticker?.cancel();
    _waitNext = null;
    _repeatLeft = _repeats - 1;
    audioEngine.stop();
    _playCurrent();
  }

  void _previous() {
    if (_pos <= 0) return;
    _timer?.cancel();
    _ticker?.cancel();
    _waitNext = null;
    setState(() => _pos--);
    _repeatLeft = _repeats - 1;
    _playCurrent();
  }

  void _finish() {
    _ticker?.cancel();
    _timer?.cancel();
    audioEngine.stop();
    if (mounted) setState(() => _phase = _Phase.finished);
  }

  int get _remainDisplay {
    if (_phase != _Phase.waiting) return _intervalSec;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _remainStart;
    return ((_remainMs - elapsed) / 1000).ceil().clamp(0, _intervalSec);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('听写 · ${widget.list.title}'),
      ),
      body: Center(
        child: switch (_phase) {
          _Phase.config => _buildConfig(theme),
          _Phase.finished => _buildAnswers(theme),
          _ => _buildPlayer(theme),
        },
      ),
    );
  }

  Widget _buildConfig(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${widget.words.length} 个词',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('播放顺序'),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              selected: {_shuffle},
              onSelectionChanged: (s) => setState(() => _shuffle = s.first),
              segments: const [
                ButtonSegment(value: false, label: Text('顺序')),
                ButtonSegment(value: true, label: Text('随机')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('作答间隔'),
            const SizedBox(width: 12),
            SegmentedButton<int>(
              selected: {_intervalSec},
              onSelectionChanged: (s) => setState(() => _intervalSec = s.first),
              segments: const [
                ButtonSegment(value: 5, label: Text('5 秒')),
                ButtonSegment(value: 10, label: Text('10 秒')),
                ButtonSegment(value: 15, label: Text('15 秒')),
                ButtonSegment(value: 20, label: Text('20 秒')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('每词遍数'),
            const SizedBox(width: 12),
            SegmentedButton<int>(
              selected: {_repeats},
              onSelectionChanged: (s) => setState(() => _repeats = s.first),
              segments: const [
                ButtonSegment(value: 1, label: Text('1 遍')),
                ButtonSegment(value: 2, label: Text('2 遍')),
                ButtonSegment(value: 3, label: Text('3 遍')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: _begin,
          style: FilledButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 64, vertical: 24),
            textStyle:
                const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          icon: const Icon(Icons.play_arrow, size: 32),
          label: const Text('开始听写'),
        ),
      ],
    );
  }

  Widget _buildPlayer(ThemeData theme) {
    final hint = switch (_phase) {
      _Phase.playing => _repeatLeft >= _repeats - 1 ? '🔊 正在播放…' : '🔊 再读一遍…',
      _Phase.waiting => '✏️ 请作答，$_remainDisplay 秒后读下一题',
      _Phase.paused => '⏸ 已暂停',
      _ => '',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '第 ${_pos + 1} 题',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          '${_pos + 1} / ${_order.length}',
          style: theme.textTheme.displayLarge
              ?.copyWith(fontSize: 88, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 480,
          child: LinearProgressIndicator(value: (_pos + 1) / _order.length),
        ),
        const SizedBox(height: 32),
        Text(
          hint,
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(
              onPressed: _pos > 0 ? _previous : null,
              icon: const Icon(Icons.skip_previous, size: 32),
              iconSize: 40,
              tooltip: '重读上一题',
            ),
            const SizedBox(width: 20),
            IconButton.filled(
              onPressed: _replayCurrent,
              icon: const Icon(Icons.replay, size: 32),
              iconSize: 48,
              tooltip: '重读本词',
            ),
            const SizedBox(width: 20),
            IconButton.filled(
              onPressed: _phase == _Phase.paused ? _resume : _pause,
              icon: Icon(
                _phase == _Phase.paused ? Icons.play_arrow : Icons.pause,
                size: 40,
              ),
              iconSize: 64,
              tooltip: _phase == _Phase.paused ? '继续' : '暂停',
            ),
            const SizedBox(width: 20),
            IconButton.outlined(
              onPressed: _advance,
              icon: const Icon(Icons.skip_next, size: 32),
              iconSize: 40,
              tooltip: '跳过',
            ),
          ],
        ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: _finish,
          child: const Text('结束听写'),
        ),
      ],
    );
  }

  Widget _buildAnswers(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Text(
          '听写结束 · 对答案',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          _shuffle ? '（随机顺序）' : '（按导入顺序）',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            itemCount: _order.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = _order[i];
              return ListTile(
                dense: true,
                leading: Text(
                  '${i + 1}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                title: Text(
                  w.text,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                trailing: w.meaning == null
                    ? null
                    : Text(
                        w.meaning!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: const Text('完成'),
          ),
        ),
      ],
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
