import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/alert_service.dart';
import '../services/language_service.dart';
import 'animations.dart';

/// Realtime "New Alert" popup for the Teacher/Student dashboards.
///
/// Watches the `alerts` table; when a fresh ACTIVE alert targeted at the
/// viewer arrives, shows a one-time dialog (prominent for Urgent) with
/// View Alert / Close. Each alert pops up AT MOST ONCE per device
/// (persisted popup-seen set) — never again after viewed or closed, and
/// expired alerts never pop up.
class AlertPopupWatcher {
  StreamSubscription? _sub;
  Timer? _timer;
  bool _showing = false;
  bool _started = false;

  /// Starts watching. [inboxPage] builds the Alerts inbox opened by
  /// "View Alert". Safe to call once per dashboard lifetime.
  Future<void> start(
    BuildContext context, {
    required String role,
    required String userId,
    required Widget Function() inboxPage,
  }) async {
    if (_started) return;
    _started = true;
    await _check(context,
        role: role, userId: userId, inboxPage: inboxPage);
    try {
      _sub = Supabase.instance.client
          .from(AlertService.table)
          .stream(primaryKey: ['id']).listen((_) {
        _check(context,
            role: role, userId: userId, inboxPage: inboxPage);
      });
    } catch (_) {}
    // Expiry sweep doubles as a popup trigger for late logins.
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      _check(context,
          role: role, userId: userId, inboxPage: inboxPage);
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
      return prefs.getStringList('seen_alert_popups')?.toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _markPopupSeen(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final set =
          prefs.getStringList('seen_alert_popups')?.toSet() ??
              <String>{};
      if (set.add(id)) {
        await prefs.setStringList('seen_alert_popups', set.toList());
      }
    } catch (_) {}
  }

  Future<void> _check(
    BuildContext context, {
    required String role,
    required String userId,
    required Widget Function() inboxPage,
  }) async {
    if (_showing || !context.mounted) return;
    // Only pop up while the dashboard itself is the visible route.
    try {
      if (ModalRoute.of(context)?.isCurrent != true) return;
    } catch (_) {}
    try {
      final scope = await AlertService.resolveScope(
        role: role,
        userId: userId,
      );
      if (scope.userId.isEmpty || scope.section.isEmpty) return;
      final active = await AlertService.fetchActive(
        role: role,
        section: scope.section,
      );
      if (active.isEmpty || !context.mounted) return;
      final ids = [
        for (final a in active) (a['id'] ?? '').toString()
      ].where((s) => s.isNotEmpty).toList();
      final states =
          await AlertService.readStates(scope.userId, ids);
      final seenPopups = await _popupSeen();
      Map<String, dynamic>? candidate;
      for (final a in active) {
        final id = (a['id'] ?? '').toString();
        if (id.isEmpty ||
            states[id] == true ||
            seenPopups.contains(id)) {
          continue;
        }
        candidate = a; // newest-first order → first match wins
        break;
      }
      if (candidate == null || !context.mounted) return;
      _showing = true;
      await _markPopupSeen((candidate['id'] ?? '').toString());
      if (!context.mounted) {
        _showing = false;
        return;
      }
      await showAlertPopup(
        context,
        alert: candidate,
        onView: () {
          Navigator.push(context, SlidePageRoute(page: inboxPage()));
        },
      );
      _showing = false;
    } catch (_) {
      _showing = false;
    }
  }
}

/// The popup dialog itself (also reusable elsewhere).
Future<void> showAlertPopup(
  BuildContext context, {
  required Map<String, dynamic> alert,
  required VoidCallback onView,
}) {
  final urgent =
      AlertService.normalizeType((alert['alert_type'] ?? '').toString()) ==
          AlertService.typeUrgent;
  final color = urgent
      ? const Color(0xFFDC2626)
      : const Color(0xFFB45309);
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(urgent ? '🚨' : '🔔',
              style: const TextStyle(fontSize: 32)),
        ),
        const SizedBox(height: 12),
        Text(
            urgent
                ? '🚨 ${tr('alert_new')} — ${AlertService.prettyType((alert['alert_type'] ?? '').toString())}'
                : '🔔 ${tr('alert_new')}',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color)),
        const SizedBox(height: 8),
        Text((alert['title'] ?? '').toString(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text((alert['message'] ?? '').toString(),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 13.5, color: Colors.grey.shade600)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(vertical: 13),
              ),
              child: Text(tr('c_close'),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onView();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(vertical: 13),
                elevation: 0,
              ),
              child: Text(tr('alert_view'),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    ),
  );
}
