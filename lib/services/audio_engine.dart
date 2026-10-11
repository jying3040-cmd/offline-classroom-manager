import 'package:flutter/services.dart';

/// 音频播放引擎抽象。听写页只依赖此接口。
///
/// 当前实现：原生 MFPlay 通道（windows/runner/audio_player.cpp），
/// 播放完成通过 'completed' 方法回调通知。
abstract class AudioEngine {
  /// 播放完成回调（每次新 play 前仍会触发上一次的完成前先被覆盖）。
  void Function()? onCompleted;

  Future<void> play(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

class NativeAudioEngine implements AudioEngine {
  NativeAudioEngine() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'completed') {
        onCompleted?.call();
      }
      return null;
    });
  }

  static const MethodChannel _channel = MethodChannel('classroom/audio');

  @override
  void Function()? onCompleted;

  @override
  Future<void> play(String path) => _channel.invokeMethod('play', path);

  @override
  Future<void> pause() => _channel.invokeMethod('pause');

  @override
  Future<void> resume() => _channel.invokeMethod('resume');

  @override
  Future<void> stop() => _channel.invokeMethod('stop');
}

/// 应用级单例：MethodChannel 的 handler 全局唯一，避免多页面互相覆盖。
/// 使用方在 initState 挂 onCompleted、dispose 置空即可。
final AudioEngine audioEngine = NativeAudioEngine();
