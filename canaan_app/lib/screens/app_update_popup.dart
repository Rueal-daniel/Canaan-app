import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_update_service.dart';
import '../services/language_service.dart';
import '../widgets/notice_rich_text.dart';
import 'updating_screen.dart';

String _prettyDate(String? raw) {
  final src = (raw ?? '').trim();
  if (src.isEmpty) return '';
  try {
    final d = DateTime.parse(src).toLocal();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return src.split('T').first;
  }
}

/// Update Available popup shared by Admin / Teacher / Student.
///
/// Shows the Canaan logo, Admin's title, version, formatted
/// description and release date. Update downloads the exact APK URL
/// the Admin published (real byte progress lives in [UpdatingScreen]).
Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdate update,
) {
  return showDialog(
    context: context,
    barrierDismissible: !update.forceUpdate,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'images/canaan logo.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                          Icons.system_update_rounded,
                          size: 40,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('🚀 ${tr('upd_available')}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text('Canaan Sunday School',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${tr('upd_version')} ${update.versionName}',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(update.title,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 10),
                  Text(tr('upd_whats_new'),
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1565C0))),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: NoticeContentView(update.descriptionHtml),
                  ),
                  if ((update.publishedAt ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Released: ${_prettyDate(update.publishedAt)}',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade600)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UpdatingScreen(
                                update: update.toRemote()),
                          ),
                        );
                      },
                      icon: const Icon(Icons.system_update_rounded,
                          size: 20),
                      label: Text(tr('upd_update'),
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  if (!update.forceUpdate) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: TextButton(
                        onPressed: () {
                          AppUpdateService.markSkipped(
                              update.versionCode);
                          Navigator.pop(ctx);
                        },
                        child: Text(tr('upd_later'),
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1565C0))),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Checks Supabase for a newer published update and shows the popup.
/// Silent on failure/offline. Respects "Later" dismissals.
/// When [announceUpToDate] is true (explicit bell tap), a message
/// confirms there is nothing new instead of doing nothing.
Future<void> showAppUpdateIfAvailable(BuildContext context,
    {bool announceUpToDate = false}) async {
  try {
    final installed = await AppUpdateService.installedVersionCode();
    final active = await AppUpdateService.fetchActiveUpdate();
    if (!context.mounted) return;
    if (!AppUpdateService.shouldUpdate(installed, active)) {
      if (announceUpToDate && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You already have the latest version. ✅',
              style: GoogleFonts.poppins(fontSize: 13)),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt('canaan_update_skipped_code') ==
        active!.versionCode) {
      if (announceUpToDate && context.mounted) {
        // Explicit tap overrides a previous "Later".
        await showAppUpdateDialog(context, active);
      }
      return;
    }
    if (!context.mounted) return;
    await showAppUpdateDialog(context, active);
  } catch (_) {
    if (announceUpToDate && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not check for updates. Please try again.',
            style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }
}

/// Realtime "Update Available" popup watcher for the dashboards —
/// same behaviour as the alert popups.
///
/// Checks immediately on start (so already-published updates pop up
/// without waiting for the next event), re-checks on every
/// `app_updates` change AND every 60 seconds (covers tables where
/// realtime is not enabled). Each update id pops up AT MOST ONCE per
/// device, and only while its dashboard route is visible.
class AppUpdatePopupWatcher {
  StreamSubscription? _sub;
  Timer? _timer;
  bool _showing = false;
  bool _started = false;

  /// Safe to call once per dashboard lifetime.
  Future<void> start(BuildContext context) async {
    if (_started) return;
    _started = true;
    await _check(context);
    try {
      _sub = Supabase.instance.client
          .from(AppUpdateService.table)
          .stream(primaryKey: ['id']).listen((_) {
        _check(context);
      });
    } catch (_) {}
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      _check(context);
    });
  }

  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _started = false;
  }

  Future<Set<String>> _popupSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('seen_update_popups')?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _markPopupSeen(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set =
          prefs.getStringList('seen_update_popups')?.toSet() ??
              <String>{};
      if (set.add(id)) {
        await prefs.setStringList('seen_update_popups', set.toList());
      }
    } catch (_) {}
  }

  Future<void> _check(BuildContext context) async {
    if (_showing || !context.mounted) return;
    // Only pop up while the dashboard itself is the visible route.
    try {
      if (ModalRoute.of(context)?.isCurrent != true) return;
    } catch (_) {}
    try {
      final installed =
          await AppUpdateService.installedVersionCode();
      final active = await AppUpdateService.fetchActiveUpdate();
      if (!context.mounted) return;
      if (!AppUpdateService.shouldUpdate(installed, active)) return;
      final id = active!.id;
      if (id.isEmpty) return;
      final seen = await _popupSeen();
      if (seen.contains(id)) return;
      // Honour "Later" tapped anywhere (e.g. the startup prompt).
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getInt('canaan_update_skipped_code') ==
            active.versionCode) {
          await _markPopupSeen(id);
          return;
        }
      } catch (_) {}
      try {
        if (ModalRoute.of(context)?.isCurrent != true) return;
      } catch (_) {}
      _showing = true;
      if (!context.mounted) return;
      await showAppUpdateDialog(context, active);
      await _markPopupSeen(id);
    } catch (_) {
    } finally {
      _showing = false;
    }
  }
}
