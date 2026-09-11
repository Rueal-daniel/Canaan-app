import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'welcome_audio.dart';

WelcomeAudio createWelcomeAudio() => WebWelcomeAudio();

/// Web implementation using a plain `<audio>` element with NO
/// `crossorigin` attribute and no WebAudio routing, so files play on
/// servers that send no CORS headers (e.g. `flutter run`).
///
/// Note: browsers block AUDIBLE autoplay until the user interacts with
/// the page, so the first `play()` in `initState` will stay paused on a
/// fresh visit — the welcome screen retries on every tap (a real
/// gesture) via [ensurePlaying], and offers a speaker button that
/// starts the music without leaving the page.
class WebWelcomeAudio implements WelcomeAudio {
  web.HTMLAudioElement? _element;
  bool _playRequested = false;

  web.HTMLAudioElement _ensureElement(String asset) {
    var element = _element;
    if (element == null) {
      element = web.HTMLAudioElement()
        ..src = 'assets/$asset'
        ..loop = true
        ..preload = 'auto';
      element.style.display = 'none';
      // Attached elements behave more reliably across browsers than
      // detached ones (load events, autoplay bookkeeping).
      try {
        web.document.body?.appendChild(element);
      } catch (_) {}
      // If the first play() raced the download, start as soon as the
      // browser has enough data — no tap needed for that case.
      try {
        element.addEventListener(
          'canplay',
          ((web.Event _) {
            if (_playRequested) {
              unawaited(_tryPlay());
            }
          }).toJS,
        );
      } catch (_) {}
      try {
        element.addEventListener(
          'error',
          ((web.Event _) {
            try {
              web.console.warn(
                'Canaan welcome music could not be loaded.'.toJS,
              );
            } catch (_) {}
          }).toJS,
        );
      } catch (_) {}
      _element = element;
    }
    return element;
  }

  Future<void> _tryPlay() async {
    final element = _element;
    if (element == null || !_playRequested) return;
    try {
      await element.play().toDart;
    } catch (_) {
      // Autoplay block or transient failure: the canplay listener and
      // the next tap (ensurePlaying) retry. The element is KEPT so a
      // retry is always possible.
    }
  }

  @override
  Future<void> play({required String asset, required double volume}) async {
    _playRequested = true;
    try {
      final element = _ensureElement(asset);
      element.volume = volume;
      await _tryPlay();
    } catch (_) {}
  }

  @override
  Future<void> ensurePlaying(double volume) async {
    final element = _element;
    if (element == null || !_playRequested) return;
    try {
      element.volume = volume;
    } catch (_) {}
    try {
      if (element.paused) {
        await element.play().toDart;
      }
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      final element = _element;
      if (element != null) element.volume = volume;
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _playRequested = false;
    try {
      _element?.pause();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _playRequested = false;
    final element = _element;
    _element = null;
    if (element == null) return;
    try {
      element.pause();
    } catch (_) {}
    try {
      element.remove();
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
