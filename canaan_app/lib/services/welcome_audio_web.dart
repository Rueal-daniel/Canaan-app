import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'welcome_audio.dart';

WelcomeAudio createWelcomeAudio() => WebWelcomeAudio();

/// Web implementation using a plain `<audio>` element with NO
/// `crossorigin` attribute and no WebAudio routing, so files play on
/// servers that send no CORS headers (e.g. `flutter run`).
class WebWelcomeAudio implements WelcomeAudio {
  web.HTMLAudioElement? _element;
  bool _started = false;

  static String _urlFor(String asset) => 'assets/$asset';

  @override
  Future<void> play({required String asset, required double volume}) async {
    if (_started) return;
    _started = true;
    try {
      final element = web.HTMLAudioElement()
        ..src = _urlFor(asset)
        ..loop = true
        ..volume = volume
        ..preload = 'auto';
      _element = element;
      try {
        await element.play().toDart;
      } catch (_) {
        // Autoplay block: the welcome screen retries on first tap
        // via [ensurePlaying], which counts as a user gesture.
      }
    } catch (_) {
      _element = null;
    }
  }

  @override
  Future<void> ensurePlaying(double volume) async {
    final element = _element;
    if (element == null) return;
    try {
      element.volume = volume;
      if (element.paused) {
        await element.play().toDart;
      }
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      _element?.volume = volume;
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      _element?.pause();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    final element = _element;
    _element = null;
    if (element == null) return;
    try {
      element.pause();
    } catch (_) {}
    try {
      element.src = '';
      element.load();
    } catch (_) {}
  }

  @override
  bool get isPlaying {
    final element = _element;
    if (element == null) return false;
    try {
      return !element.paused;
    } catch (_) {
      return false;
    }
  }
}
