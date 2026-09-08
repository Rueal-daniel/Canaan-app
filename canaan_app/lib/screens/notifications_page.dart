import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/notification_service.dart';
import '../widgets/animations.dart';

/// Full Notifications page (opened from the 🔔 bell on every dashboard).
///
/// White list on a soft background, unread rows in light lavender, read
/// rows in white, grouped by Today / Yesterday / date. Tapping a row
/// marks it read and navigates to the existing feature page via
/// [onNotificationTap]. Realtime: the list refreshes with no reload.
class NotificationsPage extends StatefulWidget {
  /// Supabase row id of the logged-in user (students/teachers/admin id).
  final String userId;

  /// 'admin' | 'teacher' | 'student'.
  final String role;

  /// Header gradient. Defaults to a deep-violet gradient per role theme.
  final List<Color>? gradient;

  /// Called AFTER the tapped notification is marked read. Dashboards
  /// navigate to the existing page here.
  final Future<void> Function(AppNotification notification)? onNotificationTap;

  const NotificationsPage({
    super.key,
    required this.userId,
    required this.role,
    this.gradient,
    this.onNotificationTap,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _lavenderSoft = Color(0xFFF4F1FF);
  static const _lavenderDeep = Color(0xFF6D28D9);

  List<Color> get _gradient =>
      widget.gradient ??
      const [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)];

  List<AppNotification> _items = [];
  bool _isLoading = true;
  StreamSubscription? _sub;
  Timer? _debounce;

  int get _unread => _items.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    _refresh();
    try {
      _sub = NotificationService.watchMine(widget.userId).listen(
        (_) {
          _debounce?.cancel();
          _debounce =
              Timer(const Duration(milliseconds: 700), _refresh);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final items =
          await NotificationService.fetchMine(widget.userId, limit: 200);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setLocalRead({String? recipientId, bool all = false}) {
    if (!mounted) return;
    setState(() {
      _items = [
        for (final n in _items)
          (all || n.recipientId == recipientId)
              ? AppNotification(
                  recipientId: n.recipientId,
                  notificationId: n.notificationId,
                  type: n.type,
                  title: n.title,
                  message: n.message,
                  relatedId: n.relatedId,
                  destination: n.destination,
                  audienceType: n.audienceType,
                  section: n.section,
                  isRead: true,
                  readAt: DateTime.now(),
                  createdAt: n.createdAt,
                  expiresAt: n.expiresAt,
                )
              : n,
      ];
    });
  }

  Future<void> _markAllRead() async {
    if (_unread == 0) return;
    try {
      await NotificationService.markAllAsRead(widget.userId);
    } catch (_) {}
    _setLocalRead(all: true);
  }

  Future<void> _onTap(AppNotification n) async {
    try {
      await NotificationService.markAsRead(n.recipientId);
    } catch (_) {}
    _setLocalRead(recipientId: n.recipientId);
    if (!mounted) return;
    Navigator.pop(context);
    try {
      await widget.onNotificationTap?.call(n);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          'Notifications${_unread > 0 ? ' ($_unread)' : ''}',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _unread == 0 ? null : _markAllRead,
            child: Text(
              'Mark all as read',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _unread == 0
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _lavenderDeep,
        onRefresh: _refresh,
        child: _isLoading
            ? const Center(
                child:
                    CircularProgressIndicator(color: Color(0xFF6D28D9)))
            : _items.isEmpty
                ? ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    children: [_emptyState()],
                  )
                : ListView.builder(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final n = _items[i];
                      final showGroup = i == 0 ||
                          NotificationService.dayGroup(_items[i - 1]
                                  .createdAt
                                  ?.toLocal()) !=
                              NotificationService.dayGroup(
                                  n.createdAt?.toLocal());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showGroup)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                  4, i == 0 ? 4 : 18, 4, 8),
                              child: Text(
                                NotificationService.dayGroup(
                                    n.createdAt?.toLocal()),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          _tile(n),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 90, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: _lavenderSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              size: 52,
              color: _lavenderDeep,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Notifications',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "You're all caught up! 🎉",
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppNotification n) {
    final icon = _iconFor(n.type);
    final color = _colorFor(n.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: n.isRead ? Colors.white : _lavenderSoft,
        borderRadius: BorderRadius.circular(18),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _onTap(n),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: n.isRead
                    ? const Color(0xFFE8EEF6)
                    : _lavenderDeep.withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: n.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            n.timeLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      if (n.message.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          n.message,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            height: 1.55,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case NotificationService.typeAttendance:
        return Icons.fact_check_rounded;
      case NotificationService.typeNotice:
        return Icons.campaign_rounded;
      case NotificationService.typeLeave:
        return Icons.event_note_rounded;
      case NotificationService.typeLessonPlan:
        return Icons.menu_book_rounded;
      case NotificationService.typeMemoryVerse:
        return Icons.auto_stories_rounded;
      case NotificationService.typeAuthentication:
        return Icons.lock_person_rounded;
      case NotificationService.typeStudentApplication:
        return Icons.assignment_ind_rounded;
      case NotificationService.typeDownload:
        return Icons.download_rounded;
      case NotificationService.typeWebsiteUpdate:
        return Icons.system_update_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case NotificationService.typeAttendance:
        return const Color(0xFF22C55E);
      case NotificationService.typeNotice:
        return const Color(0xFFB45309);
      case NotificationService.typeLeave:
        return const Color(0xFF0E9F6E);
      case NotificationService.typeLessonPlan:
        return const Color(0xFFFF9F0A);
      case NotificationService.typeMemoryVerse:
        return const Color(0xFF6366F1);
      case NotificationService.typeAuthentication:
        return const Color(0xFF0B2A5B);
      case NotificationService.typeStudentApplication:
        return const Color(0xFF0E9F6E);
      case NotificationService.typeDownload:
        return const Color(0xFF1565C0);
      case NotificationService.typeWebsiteUpdate:
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF64748B);
    }
  }
}

/// Opens [NotificationsPage] with the app's standard slide transition.
Future<void> openNotificationsPage(
  BuildContext context, {
  required String userId,
  required String role,
  List<Color>? gradient,
  Future<void> Function(AppNotification notification)? onNotificationTap,
}) {
  return Navigator.push(
    context,
    SlidePageRoute(
      page: NotificationsPage(
        userId: userId,
        role: role,
        gradient: gradient,
        onNotificationTap: onNotificationTap,
      ),
    ),
  );
}
