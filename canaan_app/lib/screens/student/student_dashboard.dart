import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/dashboard_design.dart';
import '../../services/auth_service.dart';
import '../../services/download_center_service.dart';
import '../../services/notice_service.dart';
import '../../services/notification_navigation.dart';
import '../../services/seen_store.dart';
import '../../services/session_service.dart';
import '../../widgets/notification_bell.dart';
import '../login_screen.dart';
import 'download_center.dart';
import 'leave_application.dart';
import 'memory_verse.dart';
import 'my_attendance.dart';
import 'notice_board.dart';

class StudentDashboard extends StatefulWidget {
  final String fullName;
  final String? photoUrl;
  final String? section;
  const StudentDashboard({
    super.key,
    required this.fullName,
    this.photoUrl,
    this.section,
  });

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final _client = Supabase.instance.client;
  Timer? _suspensionTimer;

  int _memoryVerseCount = 0;
  int _lessonPlanCount = 0;
  int _presentCount = 0;
  int _totalSessions = 0;
  int _noticeUnread = 0;
  int _verseUnread = 0;
  int _dcUnread = 0;
  int _leaveUnread = 0;
  bool _isLoading = true;
  String _notifUserId = '';
  final List<StreamSubscription> _realtimeSubs = [];

  double get _attendanceRate =>
      _totalSessions == 0 ? 0 : (_presentCount / _totalSessions) * 100;

  @override
  void initState() {
    super.initState();
    // Block access if this account has been suspended — including
    // suspension that happened while already logged in.
    _guardSuspension();
    _suspensionTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _guardSuspension(),
    );
    _loadNotifIdentity();
    _loadAll();
  }

  @override
  void dispose() {
    _suspensionTimer?.cancel();
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Resolves the logged-in student's row id for the notification bell.
  /// Falls back to a `students` lookup by name: on shared devices the
  /// single saved session may belong to another role's last login.
  Future<void> _loadNotifIdentity() async {
    try {
      final session = await SessionService.getSession();
      if (!mounted) return;
      final role = (session?.role ?? '').trim().toLowerCase();
      if (session != null &&
          role == UserRole.student.name &&
          session.userId.isNotEmpty) {
        setState(() => _notifUserId = session.userId);
        return;
      }
    } catch (_) {}
    try {
      final rows = await _client
          .from('students')
          .select('id')
          .eq('full_name', widget.fullName)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isNotEmpty && mounted) {
        final id = (list.first['id'] ?? '').toString();
        if (id.isNotEmpty) setState(() => _notifUserId = id);
      }
    } catch (_) {}
  }

  Future<void> _guardSuspension() async {
    try {
      final session = await SessionService.getSession();
      if (session == null || session.role != UserRole.student.name) return;
      final auth = AuthService();
      final profile = await auth.getUserById(
        userId: session.userId,
        role: UserRole.student,
      );
      if (!AuthService.isSuspended(profile)) return;
      await auth.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(suspendedNotice: true),
        ),
        (_) => false,
      );
    } catch (_) {}
  }

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  Future<void> _loadAll() async {
    try {
      // Memory verses for this section.
      int verses = 0;
      final section = widget.section;
      if (section != null && section.isNotEmpty) {
        try {
          final rows = await _client
              .from('memory_verses')
              .select('id')
              .eq('section', section);
          verses = rows.length;
        } catch (_) {}

        // Published lesson plans for this section.
        try {
          final plans = await _client
              .from('lesson_plans')
              .select('id')
              .eq('grade', section)
              .eq('status', 'published');
          _lessonPlanCount = plans.length;
        } catch (_) {
          try {
            final plans = await _client
                .from('lesson_plans')
                .select('id')
                .eq('grade', section);
            _lessonPlanCount = plans.length;
          } catch (_) {}
        }
      }

      // Attendance rate — same matching as MyAttendance:
      // attendance_reports rows hold a `students` JSON array.
      int present = 0;
      int total = 0;
      try {
        final rows = await _client
            .from('attendance_reports')
            .select('date, students')
            .order('date', ascending: false);
        final me = _norm(widget.fullName);
        for (final row in (rows as List)) {
          final students = row['students'];
          if (students is! List) continue;
          for (final s in students) {
            if (s is! Map) continue;
            if (_norm(s['name']?.toString()) != me) continue;
            total++;
            final st = _norm(s['status']?.toString());
            if (st == 'present' || st == 'late') present++;
            break; // one entry per report row
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _memoryVerseCount = verses;
          _presentCount = present;
          _totalSessions = total;
          _isLoading = false;
        });
        _loadNoticeUnread();
        _loadBadges();
        _watchBadges();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Red number badges: anything new since the student last opened it.
  /// Leave badge counts decided (approved/rejected) applications the
  /// student hasn't opened yet.
  Future<void> _loadBadges() async {
    if (!mounted) return;
    final section = widget.section;
    try {
      List<String> verseIds = [];
      if (section != null && section.isNotEmpty) {
        try {
          final rows = await _client
              .from('memory_verses')
              .select('id')
              .eq('section', section);
          verseIds = (rows as List)
              .map((r) => (r as Map)['id'].toString())
              .toList();
        } catch (_) {}
      }
      List<String> dcIds = [];
      try {
        final rows = await _client
            .from('download_center')
            .select('id')
            .inFilter('audience',
                DownloadCenterService.visibleAudiencesFor('student'));
        dcIds = (rows as List)
            .map((r) => (r as Map)['id'].toString())
            .toList();
      } catch (_) {
        try {
          final rows =
              await _client.from('download_center').select('id');
          dcIds = (rows as List)
              .map((r) => (r as Map)['id'].toString())
              .toList();
        } catch (_) {}
      }
      final decidedIds = await _decidedLeaveIds();
      final seen = await Future.wait([
        SeenStore.getSeen('seen_student_verses'),
        SeenStore.getSeen('seen_student_downloads'),
        SeenStore.getSeen('seen_student_leavedecisions'),
      ]);
      if (!mounted) return;
      setState(() {
        _verseUnread = SeenStore.unseenCount(verseIds, seen[0]);
        _dcUnread = SeenStore.unseenCount(dcIds, seen[1]);
        _leaveUnread = SeenStore.unseenCount(decidedIds, seen[2]);
      });
    } catch (_) {}
  }

  /// Ids of my own decided leave applications.
  Future<List<String>> _decidedLeaveIds() async {
    try {
      String myId = '';
      try {
        final session = await SessionService.getSession();
        if (session != null && session.role == UserRole.student.name) {
          myId = session.userId;
        }
      } catch (_) {}
      List<Map<String, dynamic>> mine = [];
      if (myId.isNotEmpty) {
        try {
          final res = await _client
              .from('student_leave_applications')
              .select('id,status')
              .eq('student_id', myId);
          mine = List<Map<String, dynamic>>.from(res);
        } catch (_) {}
      }
      if (mine.isEmpty && widget.fullName.trim().isNotEmpty) {
        try {
          final res = await _client
              .from('student_leave_applications')
              .select('id,status,student_name')
              .order('created_at', ascending: false)
              .limit(100);
          final want = _norm(widget.fullName);
          for (final r in (res as List)) {
            final m = Map<String, dynamic>.from(r as Map);
            if (_norm(m['student_name']?.toString()) == want) mine.add(m);
          }
        } catch (_) {}
      }
      return mine
          .where((m) =>
              (m['status'] ?? '').toString() == 'approved' ||
              (m['status'] ?? '').toString() == 'rejected')
          .map((m) => (m['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Live badge refresh for anything new.
  void _watchBadges() {
    if (_realtimeSubs.isNotEmpty) return;
    for (final t in [
      'memory_verses',
      'download_center',
      'student_leave_applications',
      'notices',
    ]) {
      try {
        _realtimeSubs.add(_client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) {
                _loadBadges();
                if (t == 'notices') _loadNoticeUnread();
              }
            }));
      } catch (_) {}
    }
  }

  /// Unread notice count for the Notice Board quick-link badge.
  Future<void> _loadNoticeUnread() async {
    try {
      String key = '';
      try {
        final session = await SessionService.getSession();
        key = session?.userId ?? '';
      } catch (_) {}
      key = key.isEmpty ? 'name:${widget.fullName}' : key;
      final rows = await _client
          .from('notices')
          .select('id,read_by')
          .inFilter(
              'audience', NoticeService.visibleAudiencesFor('student'));
      int count = 0;
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        if (NoticeService.isUnread(m, key)) count++;
      }
      if (mounted) setState(() => _noticeUnread = count);
    } catch (_) {}
  }

  void _openAttendance() {
    Navigator.push(
      context,
      SlidePageRoute(page: MyAttendance(fullName: widget.fullName)),
    );
  }

  Future<void> _openMemoryVerse() async {
    final section = widget.section;
    if (section == null || section.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No section assigned yet', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      SlidePageRoute(page: StudentMemoryVerse(section: section)),
    );
    if (mounted) _loadBadges();
  }

  @override
  Widget build(BuildContext context) {
    final sectionLabel = dashPrettySection(widget.section);
    final photo = widget.photoUrl != null && widget.photoUrl!.isNotEmpty
        ? 'https://pjytoxyddfrsrkzappbb.supabase.co/storage/v1/object/public/student-photos/${widget.photoUrl}'
        : null;

    return Scaffold(
      backgroundColor: DashColors.bg,
      drawer: CanaanSidebar(
        gradient: DashColors.studentGradient,
        fullName: widget.fullName,
        roleLabel: 'Student',
        role: 'student',
        photoUrl: photo,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: const Color(0xFF0E9F6E),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 250,
              floating: false,
              pinned: true,
              elevation: 0,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  color: Colors.white,
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: DashboardHero(
                  gradient: DashColors.studentGradient,
                  greeting: dashGreeting(),
                  name: widget.fullName,
                  roleLabel: 'Student',
                  sectionLabel: sectionLabel,
                  photoUrl: photo,
                ),
              ),
              actions: [
                NotificationBell(
                  userId: _notifUserId,
                  role: 'student',
                  gradient: DashColors.studentGradient,
                  onNotificationTap: (n) =>
                      NotificationNavigation.handleTap(
                    context,
                    role: 'student',
                    notification: n,
                    fullName: widget.fullName,
                    section: widget.section,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  color: Colors.white,
                  tooltip: 'Log out',
                  onPressed: () => confirmLogout(context),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.only(top: 90),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF0E9F6E))),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeInSlide(index: 0, child: _welcomeCard()),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 1,
                              child: DashSectionHeading('Overview',
                                  trailing: dashTodayLabel())),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 2,
                            child: GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: 158,
                              children: [
                                DashStat(
                                  label: 'Attendance Rate',
                                  value:
                                      '${_attendanceRate.toStringAsFixed(0)}%',
                                  subtitle: '$_presentCount of $_totalSessions days',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: const Color(0xFF22C55E),
                                  onTap: _openAttendance,
                                ),
                                DashStat(
                                  label: 'Days Present',
                                  value: '$_presentCount',
                                  subtitle: 'Keep it up!',
                                  icon: Icons.calendar_month_rounded,
                                  color: const Color(0xFF1565C0),
                                  onTap: _openAttendance,
                                ),
                                DashStat(
                                  label: 'Memory Verses',
                                  value: '$_memoryVerseCount',
                                  subtitle: sectionLabel,
                                  icon: Icons.menu_book_rounded,
                                  color: const Color(0xFF6366F1),
                                  badge: SeenStore.badgeFor(_verseUnread),
                                  onTap: _openMemoryVerse,
                                ),
                                DashStat(
                                  label: 'Lesson Plans',
                                  value: '$_lessonPlanCount',
                                  subtitle: 'Published',
                                  icon: Icons.auto_stories_rounded,
                                  color: const Color(0xFFFF9F0A),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 3,
                              child: const DashSectionHeading('Quick Links')),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 4,
                            child: DashQuickLink(
                              icon: Icons.calendar_month_rounded,
                              title: 'Attendance',
                              subtitle: 'View your attendance records',
                              color: const Color(0xFF22C55E),
                              colorEnd: const Color(0xFF4ADE80),
                              onTap: _openAttendance,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 5,
                            child: DashQuickLink(
                              icon: Icons.menu_book_rounded,
                              title: 'Memory Verse',
                              subtitle:
                                  'View your $sectionLabel memory verses',
                              color: const Color(0xFF6366F1),
                              colorEnd: const Color(0xFF8B5CF6),
                              badge: SeenStore.badgeFor(_verseUnread),
                              onTap: _openMemoryVerse,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 6,
                            child: DashQuickLink(
                              icon: Icons.download_rounded,
                              title: '📥 Download Center',
                              subtitle: 'Resources shared with you',
                              color: const Color(0xFF0E9F6E),
                              colorEnd: const Color(0xFF4ADE80),
                              badge: SeenStore.badgeFor(_dcUnread),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page:
                                          const StudentDownloadCenterPage())).then(
                                  (_) => _loadBadges()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 7,
                            child: DashQuickLink(
                              icon: Icons.event_note_rounded,
                              title: 'Leave Application',
                              subtitle: 'Explain an absence to the Admin',
                              color: const Color(0xFF0E9F6E),
                              colorEnd: const Color(0xFF34D399),
                              badge: SeenStore.badgeFor(_leaveUnread),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: StudentLeaveApplicationPage(
                                          fullName: widget.fullName,
                                          section: widget.section))).then(
                                  (_) => _loadBadges()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 8,
                            child: DashQuickLink(
                              icon: Icons.campaign_rounded,
                              title: '📢 Notice Board',
                              subtitle: 'Important notices from the Admin',
                              color: const Color(0xFFB45309),
                              colorEnd: const Color(0xFFF59E0B),
                              badge: _noticeUnread > 0
                                  ? '🔴 $_noticeUnread'
                                  : null,
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: StudentNoticeBoardPage(
                                          studentName:
                                              widget.fullName))).then(
                                  (_) => _loadNoticeUnread()),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _welcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DashColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0E9F6E), Color(0xFF4ADE80)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0E9F6E).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back!',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DashColors.ink)),
                const SizedBox(height: 2),
                Text('Ready to learn something new today?',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: DashColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
