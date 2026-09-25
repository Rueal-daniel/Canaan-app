import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_update_service.dart';
import 'auth_gate.dart';
import 'app_update_popup.dart';
import 'update_success_screen.dart';
import 'welcome_screen.dart';

/// App entry point: splash → Admin-controlled update check →
/// first-launch welcome or the existing login/session flow.
///
/// Update behaviour (Supabase `app_updates` table):
/// - Newer published APK → Update Available popup (force blocks).
/// - Just updated       → one-time success box, then normal flow.
/// - Up to date/offline → straight through, nothing shown.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    bool completed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      completed = prefs.getBool('canaan_onboarding_completed') ?? false;
    } catch (_) {}
    if (!mounted) return;

    // 1. Admin-controlled update check (silent on failure/offline).
    final result = await AppUpdateService.checkAtStartup();
    if (!mounted) return;

    // 2. Newer APK published → update popup (blocks when Required).
    if (result.update != null) {
      await showAppUpdateDialog(context, result.update!);
      if (!mounted) return;
    }

    // 3. Just updated → one-time success box with the Admin's text.
    if (result.updatedSinceLastRun &&
        result.previousName != null &&
        result.previousName != result.installedName) {
      final alreadyShown = await AppUpdateService.successAlreadyShown(
          result.installedName);
      if (!mounted) return;
      if (!alreadyShown) {
        String whatsNewHtml = '';
        try {
          final active = await AppUpdateService.fetchActiveUpdate();
          if (active != null &&
              active.versionCode == result.installedCode) {
            whatsNewHtml = active.descriptionHtml;
          }
        } catch (_) {}
        if (!mounted) return;
        await showUpdateSuccessDialog(
          context,
          previousName: result.previousName!,
          currentName: result.installedName,
          descriptionHtml: whatsNewHtml,
        );
        await AppUpdateService.markSuccessShown(result.installedName);
        if (!mounted) return;
      }
    }

    // 4. Normal flow, exactly as before.
    if (completed) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
      return;
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading Canaan…',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Color(0xFF1565C0)),
          ],
        ),
      ),
    );
  }
}
