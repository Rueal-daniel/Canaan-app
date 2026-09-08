import 'package:audioplayers/audioplayers.dart';

import 'welcome_audio.dart';

WelcomeAudio createWelcomeAudio() => IoWelcomeAudio();

/// Mobile/desktop implementation backed by audioplayers.
class IoWelcomeAudio implements WelcomeAudio {
  AudioPlayer? _player;

  @override
  Future<void> play({required String asset, required double volume}) async {
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setVolume(volume);
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(asset));
    } catch (_) {
      _player = null;
    }
  }

  @override
  Future<void> ensurePlaying(double volume) async {
    final player = _player;
    if (player == null) return;
    try {
      if (player.state != PlayerState.playing) {
        await player.setVolume(volume);
        await player.resume();
      }
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _player?.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  @override
  bool get isPlaying => _player?.state == PlayerState.playing;
}
