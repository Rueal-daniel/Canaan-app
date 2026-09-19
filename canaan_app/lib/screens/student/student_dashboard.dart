import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/dashboard_design.dart';
import '../../services/auth_service.dart';
import '../../services/alert_service.dart';
import '../../services/download_center_service.dart';
import '../../services/language_service.dart';
import '../../services/linked_student_service.dart';
import '../../services/notice_service.dart';
import '../../services/notification_navigation.dart';
import '../../services/progress_service.dart';
import '../../services/seen_store.dart';
import '../../services/session_service.dart';
import '../../widgets/alert_popup.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/switch_student_sheet.dart';
import 'progress_page.dart';
import '../login_screen.dart';
import 'alerts.dart';
import 'canaan_gallery.dart';
import 'certificates.dart';
import 'download_center.dart';
import 'events_calendar.dart';
import 'leave_application.dart';
import 'prayer_requests.dart';
import 'memory_verse.dart';
import 'my_attendance.dart';
import 'notice_board.dart';

class StudentDashboard extends StatefulWidget {
  final String fullName;
  final String? photoUrl;
  final String? section;

  /// Active (viewed) student id — the verified linked selection whose data
  /// this dashboard shows. Falls back to the login session when empty.
  final String? studentId;

  /// Secure login (authenticated) student id. NEVER changed by switching;
  /// used for server-side link verification.
  final String? loginStudentId;

  const StudentDashboard({
    super.key,
    required this.fullName,
    this.photoUrl,
    this.section,
    this.studentId,
    this.loginStudentId,
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
  int _alertUnread = 0;
  bool _isLoading = true;
  String _notifUserId = '';
  String _studentId = '';
  String _loginStudentId = '';
  bool _hasLinked = false;
  bool _isViewingLinked = false;
  double _attPct = 0;
  double _memPct = 0;
  double _partPct = 0;
  double _discPct = 0;
  int _stars = 0;
  bool _hasEvaluation = false;
  final List<StreamSubscription> _realtimeSubs = [];
  final _alertPopups = AlertPopupWatcher();

  double get _attendanceRate =>
      _totalSessions == 0 ? 0 : (_presentCount / _totalSessions) * 100;

  @override
  void initState() {
    super.initState();
    // Active student starts as the constructor's verified selection.
    if ((widget.studentId ?? '').trim().isNotEmpty) {
      _studentId = widget.studentId!.trim();
    }
    if ((widget.loginStudentId ?? '').trim().isNotEmpty) {
      _loginStudentId = widget.loginStudentId!.trim();
    }
    // Block access if this account has been suspended — including
    // suspension that happened while already logged in.
    _resolveIdentity().then((_) {
      _guardSuspension();
      _loadLinkedState();
    });
    _suspensionTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _guardSuspension(),
    );
    _loadNotifIdentity();
    _loadAll();
    _loadProgress();
    // Realtime alert popups for this (active) student.
    _alertPopups.start(
      context,
      role: 'student',
      userId: _studentId,
      inboxPage: () => StudentAlertsPage(
        studentName: widget.fullName,
        studentId: _activeIdOrNull,
      ),
    );
  }

  @override
  void dispose() {
    _alertPopups.dispose();
    _suspensionTimer?.cancel();
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Resolves login vs active student ids.
  ///
  /// The LOGIN id is the secure authenticated identity (never changed by
  /// switching). The ACTIVE id is the verified linked selection whose
  /// dashboard is being viewed. All data queries use the active id.
  Future<void> _resolveIdentity() async {
    try {
      var loginId = _loginStudentId.trim();
      if (loginId.isEmpty) {
        try {
          final session = await SessionService.getSession();
          if (session != null &&
              session.role == UserRole.student.name &&
              session.userId.trim().isNotEmpty) {
            loginId = session.userId.trim();
          }
        } catch (_) {}
      }
      var active = _studentId.trim();
      if (active.isEmpty) {
        active = await LinkedStudentService.effectiveStudentId(
            loginStudentId: loginId);
      } else if (loginId.isNotEmpty && active != loginId) {
        // Constructor-provided active id: honour only while still linked.
        final ok = await LinkedStudentService.isLinked(
            loginStudentId: loginId, targetId: active);
        if (!ok) active = loginId;
      }
      if (active.isEmpty) active = loginId;
      if (!mounted) return;
      setState(() {
        _loginStudentId = loginId;
        _studentId = active;
        _notifUserId = active;
        _isViewingLinked =
            loginId.isNotEmpty && active.isNotEmpty && loginId != active;
      });
      if (active.isNotEmpty) {
        LanguageService.bind(role: 'student', userId: active);
      }
    } catch (_) {}
  }

  /// Loads whether this login has linked family accounts (drives the
  /// conditional "Switch Student" button — hidden otherwise).
  Future<void> _loadLinkedState() async {
    try {
      var loginId = _loginStudentId.trim();
      if (loginId.isEmpty) {
        loginId = await LinkedStudentService.getLoginStudentId();
      }
      if (loginId.isEmpty || !mounted) return;
      final linked =
          await LinkedStudentService.fetchLinkedStudents(loginId);
      if (!mounted) return;
      setState(() {
        _hasLinked = linked.length >= 2;
        if (_loginStudentId.isEmpty) _loginStudentId = loginId;
        if (_studentId.isEmpty) {
          _studentId = loginId;
          _notifUserId = loginId;
        }
        _isViewingLinked = _studentId.isNotEmpty &&
            _loginStudentId.isNotEmpty &&
            _studentId != _loginStudentId;
      });
    } catch (_) {}
  }

  /// Opens the Switch Student sheet and swaps to the verified selection
  /// instantly — no logout, no credentials.
  Future<void> _openSwitcher() async {
    var loginId = _loginStudentId.trim();
    if (loginId.isEmpty) {
      loginId = await LinkedStudentService.getLoginStudentId();
    }
    if (loginId.isEmpty || !mounted) return;
    final row = await showSwitchStudentSheet(
      context,
      loginStudentId: loginId,
      activeStudentId:
          _studentId.trim().isEmpty ? loginId : _studentId.trim(),
    );
    if (row == null || !mounted) return;
    final targetId = (row['id'] ?? '').toString().trim();
    if (targetId.isEmpty) return;
    if (targetId == _studentId.trim()) return;
    final photoRaw = (row['photo_url'] ?? '').toString();
    Navigator.pushReplacement(
      context,
      SlidePageRoute(
        page: StudentDashboard(
          fullName: ((row['full_name'] ?? '').toString().trim().isEmpty)
              ? (row['username'] ?? widget.fullName).toString()
              : (row['full_name'] ?? '').toString(),
          photoUrl: photoRaw,
          section: (row['section'] ?? '').toString(),
          studentId: targetId,
          loginStudentId: loginId,
        ),
      ),
    );
  }

  /// Resolves the ACTIVE student's row id for the notification bell.
  /// Falls back to a `students` lookup by name: on shared devices the
  /// single saved session may belong to another role's last login.
  Future<void> _loadNotifIdentity() async {
    try {
      await _resolveIdentity();
      if (!mounted) return;
      if (_studentId.isNotEmpty) {
        setState(() => _notifUserId = _studentId);
        LanguageService.bind(role: 'student', userId: _studentId);
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

  /// Suspends access when the ACTIVE student is suspended (§13 — the
  /// switch feature never bypasses suspension). The login account is
  /// checked too, so a suspended login cannot linger either.
  Future<void> _guardSuspension() async {
    try {
      await _resolveIdentity();
      if (!mounted) return;
      final auth = AuthService();
      final idsToCheck = <String>{
        if (_studentId.trim().isNotEmpty) _studentId.trim(),
        if (_loginStudentId.trim().isNotEmpty) _loginStudentId.trim(),
      };
      if (idsToCheck.isEmpty) {
        final session = await SessionService.getSession();
        if (session == null || session.role != UserRole.student.name) return;
        idsToCheck.add(session.userId);
      }
      for (final id in idsToCheck) {
        final profile = await auth.getUserById(
          userId: id,
          role: UserRole.student,
        );
        if (!AuthService.isSuspended(profile)) continue;
        await LinkedStudentService.clearActiveStudent();
        await auth.logout();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const LoginScreen(suspendedNotice: true),
          ),
          (_) => false,
        );
        return;
      }
    } catch (_) {}
  }

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  /// Your Progress card data: live attendance + memory percentages and
  /// the Admin's participation / discipline / star evaluation — always
  /// for the ACTIVE (viewed) student, never the login account.
  Future<void> _loadProgress() async {
    try {
      var sid = _studentId.trim();
      if (sid.isEmpty) {
        sid = await LinkedStudentService.effectiveStudentId(
            loginStudentId: _loginStudentId);
      }
      sid = sid.trim();
      if (sid.isEmpty && widget.fullName.trim().isNotEmpty) {
        try {
          final rows = await _client
              .from('students')
              .select('id')
              .eq('full_name', widget.fullName)
              .limit(1);
          final list = List<Map<String, dynamic>>.from(rows);
          if (list.isNotEmpty) {
            sid = (list.first['id'] ?? '').toString();
          }
        } catch (_) {}
      }
      final section =
          ProgressService.normalizeSection(widget.section ?? '');
      final results = await Future.wait([
        ProgressService.attendanceFor(widget.fullName),
        ProgressService.memoryFor(sid, section),
        ProgressService.evaluationFor(sid),
      ]);
      if (!mounted) return;
      final att = results[0] as AttendanceSummary;
      final mem = results[1] as MemorySummary;
      final eval = results[2] as Map<String, dynamic>?;
      setState(() {
        _studentId = sid;
        _attPct = att.percent;
        _memPct = mem.percent;
        _hasEvaluation = eval != null;
        _partPct =
            ProgressService.evalInt(eval, 'participation_percentage')
                .toDouble();
        _discPct = ProgressService.evalInt(eval, 'discipline_percentage')
            .toDouble();
        _stars = ProgressService.evalInt(eval, 'overall_star_rating')
            .clamp(0, 5);
      });
      if (sid.isNotEmpty) {
        LanguageService.bind(role: 'student', userId: sid);
      }
    } catch (_) {}
  }

  void _openProgress() {
    if (_studentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('err_relogin'),
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      SlidePageRoute(
        page: StudentProgressPage(
          fullName: widget.fullName,
          studentId: _studentId,
          section: widget.section,
        ),
      ),
    ).then((_) {
      if (mounted) _loadProgress();
    });
  }

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
        _loadAlertBadge();
        _loadProgress();
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

  /// Ids of the ACTIVE student's decided leave applications.
  Future<List<String>> _decidedLeaveIds() async {
    try {
      String myId = _studentId.trim();
      if (myId.isEmpty) {
        try {
          myId = await LinkedStudentService.effectiveStudentId(
              loginStudentId: _loginStudentId);
        } catch (_) {}
      }
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

  /// Live badge + progress refresh for anything new.
  void _watchBadges() {
    if (_realtimeSubs.isNotEmpty) return;
    for (final t in [
      'memory_verses',
      'download_center',
      'student_leave_applications',
      'notices',
      'events',
      'gallery_posts',
      'gallery_photos',
      'prayer_requests',
      'prayer_request_replies',
      'student_updates',
      'attendance_reports',
      'student_progress_evaluations',
      'alerts',
      'alert_recipients',
      'recitation_sub_junior',
      'recitation_junior',
      'recitation_senior',
    ]) {
      try {
        _realtimeSubs.add(_client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) {
                _loadBadges();
                _loadProgress();
                _loadAlertBadge();
                if (t == 'notices') _loadNoticeUnread();
              }
            }));
      } catch (_) {}
    }
  }

  /// Unread alert count for the Alerts quick-link badge (active
  /// student, non-expired alerts only).
  Future<void> _loadAlertBadge() async {
    try {
      var uid = _studentId.trim();
      if (uid.isEmpty) {
        uid = await LinkedStudentService.effectiveStudentId(
            loginStudentId: _loginStudentId);
      }
      final section = (widget.section ?? '').trim();
      if (uid.isEmpty || section.isEmpty || !mounted) return;
      final count = await AlertService.unreadCount(
        role: 'student',
        section: section,
        userId: uid,
      );
      if (mounted) setState(() => _alertUnread = count);
    } catch (_) {}
  }

  /// Unread notice count for the Notice Board quick-link badge.
  /// Uses the ACTIVE student id so the bell follows the viewed dashboard.
  Future<void> _loadNoticeUnread() async {
    try {
      String key = _studentId.trim();
      if (key.isEmpty) {
        try {
          key = await LinkedStudentService.effectiveStudentId(
              loginStudentId: _loginStudentId);
        } catch (_) {}
      }
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
      SlidePageRoute(
          page: MyAttendance(
        fullName: widget.fullName,
        studentId: _studentId.trim().isEmpty ? null : _studentId.trim(),
      )),
    );
  }

  Future<void> _openMemoryVerse() async {
    final section = widget.section;
    if (section == null || section.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('err_no_section'),
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      SlidePageRoute(
          page: StudentMemoryVerse(
        section: section,
        studentId: _studentId.trim().isEmpty ? null : _studentId.trim(),
      )),
    );
    if (mounted) _loadBadges();
  }

  /// Active student id for sub-pages (never empty-string).
  String? get _activeIdOrNull =>
      _studentId.trim().isEmpty ? null : _studentId.trim();

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
        roleLabel: tr('role_student'),
        role: 'student',
        photoUrl: photo,
        userId: _studentId,
      ),
      body: LangBuilder(
        builder: (_) => RefreshIndicator(
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
                  roleLabel: tr('role_student'),
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
                if (_hasLinked)
                  IconButton(
                    icon: const Icon(Icons.switch_account_rounded),
                    color: Colors.white,
                    tooltip: 'Switch Student',
                    onPressed: _openSwitcher,
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
                          if (_hasLinked) ...[
                            const SizedBox(height: 12),
                            FadeInSlide(
                                index: 0,
                                child: _switchStudentCard()),
                          ],
                          if (_isViewingLinked) ...[
                            const SizedBox(height: 12),
                            FadeInSlide(
                                index: 0,
                                child: _viewingAsBanner()),
                          ],
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 1,
                              child: DashSectionHeading(tr('nav_your_progress'))),
                          const SizedBox(height: 12),
                          FadeInSlide(index: 2, child: _progressCard()),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 1,
                              child: DashSectionHeading(tr('dash_overview'),
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
                                  label: tr('dash_att_rate'),
                                  value:
                                      '${_attendanceRate.toStringAsFixed(0)}%',
                                  subtitle: trp('dash_att_sub', {
                                    'p': '$_presentCount',
                                    't': '$_totalSessions'
                                  }),
                                  icon: Icons.check_circle_outline_rounded,
                                  color: const Color(0xFF22C55E),
                                  onTap: _openAttendance,
                                ),
                                DashStat(
                                  label: tr('dash_days_present'),
                                  value: '$_presentCount',
                                  subtitle: tr('dash_keep_up'),
                                  icon: Icons.calendar_month_rounded,
                                  color: const Color(0xFF1565C0),
                                  onTap: _openAttendance,
                                ),
                                DashStat(
                                  label: tr('nav_memory_verses'),
                                  value: '$_memoryVerseCount',
                                  subtitle: sectionLabel,
                                  icon: Icons.menu_book_rounded,
                                  color: const Color(0xFF6366F1),
                                  badge: SeenStore.badgeFor(_verseUnread),
                                  onTap: _openMemoryVerse,
                                ),
                                DashStat(
                                  label: tr('nav_lesson_plans'),
                                  value: '$_lessonPlanCount',
                                  subtitle: tr('dash_published'),
                                  icon: Icons.auto_stories_rounded,
                                  color: const Color(0xFFFF9F0A),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 3,
                              child: DashSectionHeading(
                                  tr('dash_quick_links'))),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 4,
                            child: DashQuickLink(
                              icon: Icons.calendar_month_rounded,
                              title: tr('nav_attendance'),
                              subtitle: tr('dash_view_attendance'),
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
                              title: tr('nav_memory_verse'),
                              subtitle: trp('dash_view_verses',
                                  {'s': sectionLabel}),
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
                              title: '📥 ${tr('nav_download')}',
                              subtitle: tr('dash_view_downloads'),
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
                              title: tr('nav_leave'),
                              subtitle: tr('dash_leave_sub'),
                              color: const Color(0xFF0E9F6E),
                              colorEnd: const Color(0xFF34D399),
                              badge: SeenStore.badgeFor(_leaveUnread),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: StudentLeaveApplicationPage(
                                          fullName: widget.fullName,
                                          section: widget.section,
                                          studentId: _activeIdOrNull))).then(
                                  (_) => _loadBadges()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 8,
                            child: DashQuickLink(
                              icon: Icons.campaign_rounded,
                              title: '📢 ${tr('nav_notice_board')}',
                              subtitle: tr('dash_notice_sub'),
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
                                              widget.fullName,
                                          studentId: _activeIdOrNull))).then(
                                  (_) => _loadNoticeUnread()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 9,
                            child: DashQuickLink(
                              icon: Icons.event_rounded,
                              title:
                                  '📅 ${tr('nav_events_calendar')}',
                              subtitle: tr('dash_events_sub'),
                              color: const Color(0xFF1E3A8A),
                              colorEnd: const Color(0xFF3B82F6),
                              onTap: () => Navigator.push(
                                context,
                                SlidePageRoute(
                                  page: StudentEventsCalendarPage(
                                    studentName: widget.fullName,
                                    section: widget.section,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 10,
                            child: DashQuickLink(
                              icon: Icons.photo_library_rounded,
                              title:
                                  '🖼️ ${tr('nav_canaan_gallery')}',
                              subtitle: tr('dash_gallery_sub'),
                              color: const Color(0xFF0F766E),
                              colorEnd: const Color(0xFF14B8A6),
                              onTap: () => Navigator.push(
                                context,
                                SlidePageRoute(
                                  page: StudentCanaanGalleryPage(
                                    studentName: widget.fullName,
                                    section: widget.section,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 11,
                            child: DashQuickLink(
                              icon: Icons.volunteer_activism_rounded,
                              title:
                                  '🙏 ${tr('nav_prayer_request')}',
                              subtitle: tr('dash_prayer_sub'),
                              color: const Color(0xFF7C3AED),
                              colorEnd: const Color(0xFFA78BFA),
                              onTap: () => Navigator.push(
                                context,
                                SlidePageRoute(
                                  page: StudentPrayerRequestPage(
                                    studentName: widget.fullName,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 12,
                            child: DashQuickLink(
                              icon: Icons.workspace_premium_rounded,
                              title: '🏆 Certificates',
                              subtitle:
                                  'Your published achievement certificates',
                              color: const Color(0xFFB45309),
                              colorEnd: const Color(0xFFF59E0B),
                              onTap: () => Navigator.push(
                                context,
                                SlidePageRoute(
                                  page: StudentCertificatesPage(
                                    studentName: widget.fullName,
                                    studentId: _activeIdOrNull,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 13,
                            child: DashQuickLink(
                              icon: Icons.notification_important_rounded,
                              title: '🚨 ${tr('nav_alerts')}',
                              subtitle:
                                  'Important updates from the Admin',
                              color: const Color(0xFFDC2626),
                              colorEnd: const Color(0xFFF87171),
                              badge: SeenStore.badgeFor(_alertUnread),
                              onTap: () => Navigator.push(
                                context,
                                SlidePageRoute(
                                  page: StudentAlertsPage(
                                    studentName: widget.fullName,
                                    studentId: _activeIdOrNull,
                                  ),
                                ),
                              ).then((_) => _loadAlertBadge()),
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
      ),
    );
  }

  Widget _progressCard() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.insights_rounded,
                    color: Color(0xFF6366F1), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('nav_your_progress'),
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DashColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _progressRow(tr('pg_attendance'), _attPct,
              const Color(0xFF22C55E)),
          const SizedBox(height: 12),
          _progressRow(
              tr('pg_memory'), _memPct, const Color(0xFF6366F1)),
          const SizedBox(height: 12),
          _progressRow(tr('pg_participation'), _partPct,
              const Color(0xFFFF9F0A),
              emptyNote: _hasEvaluation ? null : tr('pg_not_evaluated')),
          const SizedBox(height: 12),
          _progressRow(tr('pg_discipline'), _discPct,
              const Color(0xFF0E9F6E),
              emptyNote: _hasEvaluation ? null : tr('pg_not_evaluated')),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          Center(
            child: Text(tr('pg_overall'),
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DashColors.ink)),
          ),
          const SizedBox(height: 8),
          Center(child: StarRating(stars: _stars, size: 30)),
          const SizedBox(height: 6),
          Center(
            child: Text(ProgressService.overallCardLabel(_stars),
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DashColors.muted)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _openProgress,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('c_view_details'),
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0E9F6E))),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Color(0xFF0E9F6E)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRow(String label, double percent, Color color,
      {String? emptyNote}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: DashColors.ink)),
            ),
            Text(
              emptyNote ?? ProgressService.pctLabel(percent),
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: emptyNote != null ? DashColors.muted : color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 9,
            child: Stack(
              children: [
                Container(color: color.withValues(alpha: 0.14)),
                FractionallySizedBox(
                  widthFactor:
                      (percent.clamp(0, 100) / 100).clamp(0.02, 1.0),
                  child: Container(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// "Switch Student" card — visible ONLY for students who actually
  /// have Admin-linked accounts (§4). Tapping opens the linked profiles.
  Widget _switchStudentCard() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _openSwitcher,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF063B2E), Color(0xFF0E9F6E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0E9F6E).withValues(alpha: 0.35),
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
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.switch_account_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Switch Student',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('View a linked family dashboard — no logout',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color:
                                Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 17, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  /// Current-student indicator (§8): shown while viewing a linked (non
  /// login) dashboard so it is always clear whose data is on screen.
  Widget _viewingAsBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E9F6E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF0E9F6E).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.verified_user_rounded,
            size: 20, color: Color(0xFF0E9F6E)),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Viewing: ${widget.fullName} — Current Student',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF065F46))),
        ),
      ]),
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
                Text(tr('dash_welcome_back'),
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DashColors.ink)),
                const SizedBox(height: 2),
                Text(tr('dash_welcome_sub'),
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
