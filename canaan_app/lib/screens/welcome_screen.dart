import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/animations.dart';
import 'login_screen.dart';

/// One-time first-launch welcome / onboarding screen.
///
/// Shown only when `canaan_onboarding_completed` is not set.
/// Plays a soft background track (best effort — the screen works
/// fine with no music if the file can't load).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const _fullText = 'Welcome to\nCanaan Sunday School';
  static const _musicAsset =
      'audio/paulyudin-piano-music-piano-485929.mp3';
  static const _musicVolume = 1.0;

  String _typed = '';
  bool _typingDone = false;
  bool _leaving = false;
  bool _musicStarted = false;
  Timer? _typingTimer;
  Timer? _fadeTimer;
  AudioPlayer? _player;

  late final AnimationController _arrowController;
  late final Animation<Offset> _arrowSlide;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _arrowSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.18, 0),
    ).animate(CurvedAnimation(
      parent: _arrowController,
      curve: Curves.easeInOut,
    ));
    _startMusic();
    _startTyping();
  }

  void _startTyping() {
    var i = 0;
    _typingTimer = Timer.periodic(const Duration(milliseconds: 55), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      i++;
      if (i >= _fullText.length) {
        t.cancel();
        setState(() {
          _typed = _fullText;
          _typingDone = true;
        });
        return;
      }
      setState(() => _typed = _fullText.substring(0, i));
    });
  }

  /// Best effort: any failure (missing file, offline, no decoder,
  /// browser autoplay block) leaves the screen fully usable.
  /// Browsers only allow audio after a user gesture, so this is also
  /// retried on the first tap anywhere via [ensureMusic].
  Future<void> _startMusic() async {
    await ensureMusic();
  }

  Future<void> ensureMusic() async {
    if (_leaving || !mounted) return;
    // Browser autoplay may leave the player paused: resume on tap.
    final existing = _player;
    if (existing != null) {
      try {
        if (existing.state != PlayerState.playing) {
          await existing.setVolume(_musicVolume);
          await existing.resume();
        }
      } catch (_) {}
      return;
    }
    if (_musicStarted) return;
    _musicStarted = true;
    try {
      final player = AudioPlayer();
      _player = player;
      await player.setVolume(_musicVolume);
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(_musicAsset));
    } catch (_) {
      _player = null;
      _musicStarted = false;
    }
  }

  /// Soft fade-out, then full stop + dispose.
  Future<void> _fadeAndStopMusic() async {
    _fadeTimer?.cancel();
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      var volume = _musicVolume;
      final done = Completer<void>();
      _fadeTimer =
          Timer.periodic(const Duration(milliseconds: 60), (t) async {
        volume -= 0.05;
        try {
          if (volume <= 0) {
            t.cancel();
            await player.stop();
            await player.dispose();
            if (!done.isCompleted) done.complete();
          } else {
            await player.setVolume(volume);
          }
        } catch (_) {
          t.cancel();
          try {
            await player.dispose();
          } catch (_) {}
          if (!done.isCompleted) done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {
        _fadeTimer?.cancel();
        try {
          player.dispose();
        } catch (_) {}
      });
    } catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    await _fadeAndStopMusic();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('canaan_onboarding_completed', true);
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      SlidePageRoute(page: const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _fadeTimer?.cancel();
    _arrowController.dispose();
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        player.stop();
      } catch (_) {}
      try {
        player.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      // First tap anywhere unlocks browser audio if autoplay was blocked.
      body: Listener(
        onPointerDown: (_) => ensureMusic(),
        child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text('Skip',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500)),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Color(0xFF0D47A1),
                          Color(0xFF42A5F5)
                        ]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.church_rounded,
                          size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      // Fixed height avoids layout jumps while typing,
                      // including when the line break appears.
                      height: 120,
                      child: Text(
                        _typed,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    if (_typingDone) ...[
                      FadeInSlide(
                        index: 0,
                        child: Text('Learn • Grow • Serve • Worship',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1565C0))),
                      ),
                      const SizedBox(height: 28),
                      FadeInSlide(
                        index: 1,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('What you can do',
                              style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FadeInSlide(
                        index: 2,
                        child: _featureCard(
                          Icons.menu_book_rounded,
                          const Color(0xFF6366F1),
                          "Learn God's Word",
                          'Explore Bible lessons and memory verses.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeInSlide(
                        index: 3,
                        child: _featureCard(
                          Icons.fact_check_rounded,
                          const Color(0xFF22C55E),
                          'Track Attendance',
                          'View your attendance and progress.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeInSlide(
                        index: 4,
                        child: _featureCard(
                          Icons.auto_stories_rounded,
                          const Color(0xFFFF9F0A),
                          'Memory Verses',
                          'Learn and practice your memory verses.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeInSlide(
                        index: 5,
                        child: _featureCard(
                          Icons.campaign_rounded,
                          const Color(0xFFA855F7),
                          'Stay Updated',
                          'Receive important Sunday School notices.',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
            if (_typingDone)
              FadeInSlide(
                index: 6,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _finish,
                        child: Text('Continue to Login',
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1565C0))),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _finish,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Color(0xFF1565C0),
                              Color(0xFF42A5F5)
                            ]),
                            shape: BoxShape.circle,
                          ),
                          child: SlideTransition(
                            position: _arrowSlide,
                            child: const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _featureCard(
      IconData icon, Color color, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
