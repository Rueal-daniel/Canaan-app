import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/notifications_page.dart';
import '../services/language_service.dart';
import '../services/notification_service.dart';
import 'animations.dart';

/// 🔔 Notification bell for the dashboard headers (Admin / Teacher /
/// Student). Shows an unread badge, glows soft lavender when there is
/// something new, and opens the full Notifications page on tap.
///
/// Realtime: subscribes to the user's own `notification_recipients`
/// rows — the badge updates with no page refresh. If the notification
/// tables do not exist yet, the bell quietly renders nothing.
class NotificationBell extends StatefulWidget {
  /// Supabase row id of the logged-in user (students/teachers/admin id).
  final String userId;

  /// 'admin' | 'teacher' | 'student'.
  final String role;

  /// Header gradient for the Notifications page. Defaults per role theme.
  final List<Color>? gradient;

  /// Called AFTER the tapped notification is marked read and the
  /// Notifications page is closed. Dashboards navigate to the existing
  /// page here.
  final Future<void> Function(AppNotification notification)? onNotificationTap;

  const NotificationBell({
    super.key,
    required this.userId,
    required this.role,
    this.gradient,
    this.onNotificationTap,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  static const _lavender = Color(0xFFEDE9FE);
  static const _lavenderDeep = Color(0xFF6D28D9);

  int _unread = 0;
  bool _loadedOnce = false;
  StreamSubscription? _sub;
  Timer? _debounce;
  Timer? _glowTimer;
  bool _justArrived = false;
  String _watchingUserId = '';

  bool get _highlight => _unread > 0 || _justArrived;

  @override
  void initState() {
    super.initState();
    _watchingUserId = widget.userId;
    LanguageService.current.addListener(_onLang);
    if (_watchingUserId.isNotEmpty) {
      _refresh();
      _subscribe();
      NotificationService.archiveOldIfDue();
    }
  }

  @override
  void didUpdateWidget(NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != _watchingUserId) {
      _watchingUserId = widget.userId;
      _sub?.cancel();
      _sub = null;
      if (_watchingUserId.isNotEmpty) {
        _refresh();
        _subscribe();
      } else if (mounted) {
        setState(() => _unread = 0);
      }
    }
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LanguageService.current.removeListener(_onLang);
    _sub?.cancel();
    _debounce?.cancel();
    _glowTimer?.cancel();
    super.dispose();
  }

  void _subscribe() {
    try {
      _sub = NotificationService.watchMine(_watchingUserId).listen(
        (_) {
          _debounce?.cancel();
          _debounce =
              Timer(const Duration(milliseconds: 700), _refresh);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _refresh() async {
    if (_watchingUserId.isEmpty) return;
    try {
      final unread =
          await NotificationService.unreadCount(_watchingUserId);
      if (!mounted) return;
      final isNew = _loadedOnce && unread > _unread;
      setState(() {
        _unread = unread;
        _loadedOnce = true;
      });
      if (isNew) {
        _glowTimer?.cancel();
        if (mounted) setState(() => _justArrived = true);
        _glowTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _justArrived = false);
        });
      }
    } catch (_) {}
  }

  Future<void> _openPage() async {
    await Navigator.push(
      context,
      SlidePageRoute(
        page: NotificationsPage(
          userId: _watchingUserId,
          role: widget.role,
          gradient: widget.gradient,
          onNotificationTap: widget.onNotificationTap,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_watchingUserId.isEmpty) return const SizedBox.shrink();
    final countLabel = _unread > 99 ? '99+' : '$_unread';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _highlight
            ? _lavender
            : Colors.white.withValues(alpha: 0.18),
        boxShadow: _highlight
            ? [
                BoxShadow(
                  color: _lavenderDeep.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_rounded),
            color: _highlight ? _lavenderDeep : Colors.white,
            tooltip: tr('nav_notifications'),
            onPressed: _openPage,
          ),
          if (_unread > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  countLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
