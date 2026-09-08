import 'welcome_audio_io.dart'
    if (dart.library.js_interop) 'welcome_audio_web.dart' as impl;

/// Tiny looping-jingle player for the welcome screen.
///
/// Why this exists: audioplayers routes web playback through the WebAudio
/// API and forces `crossOrigin = 'anonymous'` on its `<audio>` element.
/// Servers without an `Access-Control-Allow-Origin` header (e.g. the
/// `flutter run` dev server) then fail the load with
/// `MEDIA_ELEMENT_ERROR: Format error (Code: 4)`. A plain audio element
/// without the CORS attribute plays the same file fine — so on web we
/// use one directly, while mobile/desktop keep audioplayers.
abstract class WelcomeAudio {
  factory WelcomeAudio() => impl.createWelcomeAudio();

  /// Starts looping [asset] (a Flutter asset path like
  /// `audio/song.mp3`) at [volume]. Never throws: autoplay blocks and
  /// load failures are swallowed so the screen always stays usable.
  Future<void> play({required String asset, required double volume});

  /// Resumes [volume] after a user gesture if playback never started
  /// (browser autoplay policy). Never throws.
  Future<void> ensurePlaying(double volume);

  /// Sets the output volume (used for the fade-out). Never throws.
  Future<void> setVolume(double volume);

  /// Stops playback. Never throws.
  Future<void> stop();

  /// Releases resources. Never throws.
  Future<void> dispose();

  bool get isPlaying;
}
