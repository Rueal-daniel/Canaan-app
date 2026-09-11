import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/dashboard_design.dart';
import '../../services/auth_service.dart';
import '../../services/download_center_service.dart';
import '../../services/language_service.dart';
import '../../services/notice_service.dart';
import '../../services/notification_navigation.dart';
import '../../services/seen_store.dart';
import '../../services/session_service.dart';
import '../../widgets/notification_bell.dart';
import '../admin/student_management.dart';
import '../login_screen.dart';
import 'download_center.dart';
import 'lesson_plan.dart';
import 'notice_board.dart';
import 'student_applications.dart';
import 'teacher_tasks.dart';
import 'memory_verse.dart';
import 'my_attendance.dart';

class TeacherDashboard extends StatefulWidget {
  final String fullName;
  final String? username;
  final String? section;
  const TeacherDashboard({
    super.key,
    required this.fullName,
    this.username,
    this.section,
  });

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final _client = Supabase.instance.client;

  String? _teacherSection;
  String? _teacherId;
  String? _teacherName;
  int _myStudentCount = 0;
  int _memoryVerseCount = 0;
  int _lessonPlanCount = 0;
  int _notificationCount = 0;
  int _noticeUnread = 0;
  int _verseUnread = 0;
  int _lessonUnread = 0;
  int _dcUnread = 0;
  int _sentAppUnread = 0;
  bool _isLoading = true;
  Timer? _suspensionTimer;
  String _notifUserId = '';
  final List<StreamSubscription> _realtimeSubs = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _loadNotifIdentity();
    // Suspended mid-session → sign out to Login with notice.
    _guardSuspension();
    _suspensionTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _guardSuspension(),
    );
    _realtimeSubs.add(_client
        .from('students')
        .stream(primaryKey: ['id'])
        .listen((_) => _fetchData()));
    // Live badge refresh for anything new.
    for (final t in [
      'memory_verses',
      'lesson_plans',
      'download_center',
      'student_leave_applications',
      'notices',
    ]) {
      try {
        _realtimeSubs.add(_client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) _loadBadges(_teacherSection);
            }));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _suspensionTimer?.cancel();
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Resolves the logged-in teacher's row id for the notification bell.
  Future<void> _loadNotifIdentity() async {
    try {
      final session = await SessionService.getSession();
      if (!mounted) return;
      final role = (session?.role ?? '').trim().toLowerCase();
      if (session != null &&
          role == UserRole.teacher.name &&
          session.userId.isNotEmpty) {
        setState(() => _notifUserId = session.userId);
        LanguageService.bind(role: 'teacher', userId: session.userId);
      }
    } catch (_) {}
  }

  Future<void> _guardSuspension() async {
    try {
      final session = await SessionService.getSession();
      if (session == null || session.role != UserRole.teacher.name) return;
      final auth = AuthService();
      final profile = await auth.getUserById(
        userId: session.userId,
        role: UserRole.teacher,
      );
      if (!AuthService.isSuspended(profile)) return;
      await auth.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
              suspendedNotice: true, suspendedRole: 'teacher'),
        ),
        (_) => false,
      );
    } catch (_) {}
  }

  Future<void> _fetchData() async {
    try {
      // 1. Resolve teacher's own id, name and section
      String? section = widget.section;
      String? teacherId;
      String? teacherName = widget.fullName;

      if (section == null &&
          widget.username != null &&
          widget.username!.isNotEmpty) {
        try {
          final t = await _client
              .from('teachers')
              .select('id, full_name, section')
              .eq('username', widget.username!)
              .maybeSingle();
          section ??= t?['section'] as String?;
          teacherId = t?['id']?.toString();
          if (t?['full_name'] != null) {
            teacherName = t!['full_name'] as String;
          }
        } catch (_) {}
      }

      // Fallback: try lookup by full_name (in case username wasn't passed)
      if (section == null || teacherId == null) {
        try {
          final t2 = await _client
              .from('teachers')
              .select('id, full_name, section')
              .eq('full_name', widget.fullName)
              .maybeSingle();
          section ??= t2?['section'] as String?;
          teacherId ??= t2?['id']?.toString();
          if (t2?['full_name'] != null) {
            teacherName = t2!['full_name'] as String;
          }
        } catch (_) {}
      }

      // 2. Count students IN THIS SECTION ONLY
      int myCount = 0;
      if (section != null && section.isNotEmpty) {
        final students =
            await _client.from('students').select('id').eq('section', section);
        myCount = students.length;
      } else {
        // No section resolved — show 0 instead of misleading total
        myCount = 0;
      }

      // 3. Section-scoped counts where the tables exist.
      int memoryCount = 0;
      int lessonCount = 0;
      int notifCount = 0;
      try {
        final mv = section == null || section.isEmpty
            ? await _client.from('memory_verses').select('id')
            : await _client
                .from('memory_verses')
                .select('id')
                .eq('section', section);
        memoryCount = mv.length;
      } catch (_) {}
      try {
        final lp = section == null || section.isEmpty
            ? await _client.from('lesson_plans').select('id')
            : await _client
                .from('lesson_plans')
                .select('id')
                .eq('grade', section)
                .eq('status', 'published');
        lessonCount = lp.length;
      } catch (_) {
        try {
          final lp = section == null || section.isEmpty
              ? await _client.from('lesson_plans').select('id')
              : await _client
                  .from('lesson_plans')
                  .select('id')
                  .eq('grade', section);
          lessonCount = lp.length;
        } catch (_) {}
      }
      try {
        final nt = await _client.from('notifications').select('id');
        notifCount = nt.length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _teacherSection = section;
          _teacherId = teacherId;
          _teacherName = teacherName;
          _myStudentCount = myCount;
          _memoryVerseCount = memoryCount;
          _lessonPlanCount = lessonCount;
          _notificationCount = notifCount;
          _isLoading = false;
          // Authoritative bell identity: the id resolved from the
          // teachers table itself (the saved session may belong to
          // another role's last login on shared devices).
          if (teacherId != null && teacherId.isNotEmpty) {
            _notifUserId = teacherId;
            LanguageService.bind(role: 'teacher', userId: teacherId);
          }
        });
        _loadNoticeUnread();
        _loadBadges(section);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Red number badges: anything new since the teacher last opened it.
  Future<void> _loadBadges(String? section) async {
    if (section == null || section.isEmpty || !mounted) return;
    try {
      final results = await Future.wait([
        () async {
          try {
            final rows = await _client
                .from('memory_verses')
                .select('id')
                .eq('section', section);
            return (rows as List)
                .map((r) => (r as Map)['id'].toString())
                .toList();
          } catch (_) {
            return <String>[];
          }
        }(),
        () async {
          try {
            final rows = await _client
                .from('lesson_plans')
                .select('id')
                .eq('grade', section)
                .eq('status', 'published');
            return (rows as List)
                .map((r) => (r as Map)['id'].toString())
                .toList();
          } catch (_) {
            try {
              final rows = await _client
                  .from('lesson_plans')
                  .select('id')
                  .eq('grade', section);
              return (rows as List)
                  .map((r) => (r as Map)['id'].toString())
                  .toList();
            } catch (_) {
              return <String>[];
            }
          }
        }(),
        () async {
          try {
            final rows = await _client
                .from('download_center')
                .select('id')
                .inFilter(
                    'audience',
                    DownloadCenterService.visibleAudiencesFor(
                        'teacher'));
            return (rows as List)
                .map((r) => (r as Map)['id'].toString())
                .toList();
          } catch (_) {
            try {
              final rows =
                  await _client.from('download_center').select('id');
              return (rows as List)
                  .map((r) => (r as Map)['id'].toString())
                  .toList();
            } catch (_) {
              return <String>[];
            }
          }
        }(),
        () async {
          try {
            final rows = await _client
                .from('student_leave_applications')
                .select('id')
                .eq('section', section)
                .eq('sent_to_teacher', true);
            return (rows as List)
                .map((r) => (r as Map)['id'].toString())
                .toList();
          } catch (_) {
            return <String>[];
          }
        }(),
      ]);
      final seen = await Future.wait([
        SeenStore.getSeen('seen_teacher_verses'),
        SeenStore.getSeen('seen_teacher_lessons'),
        SeenStore.getSeen('seen_teacher_downloads'),
        SeenStore.getSeen('seen_teacher_sentapps'),
      ]);
      if (!mounted) return;
      setState(() {
        _verseUnread = SeenStore.unseenCount(results[0], seen[0]);
        _lessonUnread = SeenStore.unseenCount(results[1], seen[1]);
        _dcUnread = SeenStore.unseenCount(results[2], seen[2]);
        _sentAppUnread = SeenStore.unseenCount(results[3], seen[3]);
      });
    } catch (_) {}
  }

  /// Unread notice count for the Notice Board quick-link badge.
  Future<void> _loadNoticeUnread() async {
    try {
      String key = '';
      try {
        final session = await SessionService.getSession();
        key = session?.userId ?? '';
      } catch (_) {}
      key = key.isEmpty
          ? (_teacherId ?? _teacherName ?? widget.fullName)
          : key;
      final rows = await _client
          .from('notices')
          .select('id,read_by')
          .inFilter(
              'audience', NoticeService.visibleAudiencesFor('teacher'));
      int count = 0;
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        if (NoticeService.isUnread(m, key)) count++;
      }
      if (mounted) setState(() => _noticeUnread = count);
    } catch (_) {}
  }

  void _deny(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _openMyStudents() {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
      _deny('No section assigned yet');
      return;
    }
    Navigator.push(
      context,
      SlidePageRoute(
        page: StudentManagement(
          lockedSection: _teacherSection,
          readOnly: true,
          teacherId: _teacherId ?? '',
          teacherName: _teacherName ?? widget.fullName,
        ),
      ),
    );
  }

  void _openMyAttendance() {
    if (_teacherId == null || _teacherId!.isEmpty) {
      _deny('Could not identify teacher account');
      return;
    }
    Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherMyAttendance(
          teacherId: _teacherId!,
          section: _teacherSection ?? '',
        ),
      ),
    );
  }

  Future<void> _openMemoryVerse() async {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
      _deny('No section assigned yet');
      return;
    }
    await Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherMemoryVerse(
          teacherId: _teacherId ?? '',
          teacherName: _teacherName ?? widget.fullName,
          section: _teacherSection!,
        ),
      ),
    );
    if (mounted) _loadBadges(_teacherSection);
  }

  Future<void> _openStudentApplications() {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
      _deny('No section assigned yet');
      return Future.value();
    }
    return Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherStudentApplicationsPage(section: _teacherSection!),
      ),
    );
  }

  Future<void> _openLessonPlan() {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
      _deny('No section assigned yet');
      return Future.value();
    }
    return Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherLessonPlanPage(
          section: _teacherSection!,
          teacherId: _teacherId ?? '',
          teacherName: _teacherName ?? widget.fullName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionLabel = dashPrettySection(_teacherSection);

    return Scaffold(
      backgroundColor: DashColors.bg,
      drawer: CanaanSidebar(
        gradient: DashColors.teacherGradient,
        fullName: _teacherName ?? widget.fullName,
        roleLabel: tr('role_teacher'),
        role: 'teacher',
        userId: _teacherId ?? '',
      ),
      body: LangBuilder(
        builder: (_) => RefreshIndicator(
        onRefresh: _fetchData,
        color: const Color(0xFF7C3AED),
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
                  gradient: DashColors.teacherGradient,
                  greeting: dashGreeting(),
                  name: _teacherName ?? widget.fullName,
                  roleLabel: tr('role_teacher'),
                  sectionLabel: sectionLabel,
                ),
              ),
              actions: [
                NotificationBell(
                  userId: _notifUserId,
                  role: 'teacher',
                  gradient: DashColors.teacherGradient,
                  onNotificationTap: (n) =>
                      NotificationNavigation.handleTap(
                    context,
                    role: 'teacher',
                    notification: n,
                    fullName: _teacherName ?? widget.fullName,
                    section: _teacherSection,
                    teacherId: (_teacherId != null && _teacherId!.isNotEmpty)
                        ? _teacherId!
                        : _notifUserId,
                    teacherName: _teacherName ?? widget.fullName,
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
                              color: Color(0xFF7C3AED))),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeInSlide(
                              index: 0,
                              child: DashSectionHeading(tr('dash_overview'),
                                  trailing: dashTodayLabel())),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 1,
                            child: GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: 158,
                              children: [
                                DashStat(
                                  label: tr('dash_my_students'),
                                  value: '$_myStudentCount',
                                  subtitle: sectionLabel,
                                  icon: Icons.group_outlined,
                                  color: const Color(0xFF6366F1),
                                  onTap: _openMyStudents,
                                ),
                                DashStat(
                                  label: tr('nav_memory_verses'),
                                  value: '$_memoryVerseCount',
                                  subtitle: tr('dash_this_section'),
                                  icon: Icons.menu_book_outlined,
                                  color: const Color(0xFF22C55E),
                                  badge: SeenStore.badgeFor(_verseUnread),
                                  onTap: _openMemoryVerse,
                                ),
                                DashStat(
                                  label: tr('nav_lesson_plans'),
                                  value: '$_lessonPlanCount',
                                  subtitle: tr('dash_published'),
                                  icon: Icons.description_outlined,
                                  color: const Color(0xFFFF9F0A),
                                  badge: SeenStore.badgeFor(_lessonUnread),
                                  onTap: () => _openLessonPlan().then((_) =>
                                      _loadBadges(_teacherSection)),
                                ),
                                DashStat(
                                  label: tr('nav_notifications'),
                                  value: '$_notificationCount',
                                  subtitle: tr('dash_latest_updates'),
                                  icon: Icons.notifications_outlined,
                                  color: const Color(0xFFA855F7),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 2,
                              child: DashSectionHeading(
                                  tr('dash_quick_links'))),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 3,
                            child: DashQuickLink(
                              icon: Icons.school_rounded,
                              title: tr('dash_students'),
                              subtitle: trp('dash_section_students', {
                                's': sectionLabel,
                                'n': '$_myStudentCount'
                              }),
                              color: const Color(0xFF22C55E),
                              colorEnd: const Color(0xFF4ADE80),
                              onTap: _openMyStudents,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 4,
                            child: DashQuickLink(
                              icon: Icons.person_rounded,
                              title: tr('nav_my_attendance'),
                              subtitle: tr('dash_my_att_sub'),
                              color: const Color(0xFF1565C0),
                              colorEnd: const Color(0xFF42A5F5),
                              onTap: _openMyAttendance,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 5,
                            child: DashQuickLink(
                              icon: Icons.menu_book_rounded,
                              title: '📚 ${tr('nav_lesson_plan')}',
                              subtitle: trp('dash_lesson_sub',
                                  {'s': sectionLabel}),
                              color: const Color(0xFFFF9F0A),
                              colorEnd: const Color(0xFFFFB74D),
                              badge: SeenStore.badgeFor(_lessonUnread),
                              onTap: () => _openLessonPlan().then((_) =>
                                  _loadBadges(_teacherSection)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 6,
                            child: DashQuickLink(
                              icon: Icons.download_rounded,
                              title: '📥 ${tr('nav_download')}',
                              subtitle: tr('dash_view_downloads'),
                              color: const Color(0xFF1565C0),
                              colorEnd: const Color(0xFF42A5F5),
                              badge: SeenStore.badgeFor(_dcUnread),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page:
                                          const TeacherDownloadCenterPage())).then(
                                  (_) => _loadBadges(_teacherSection)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 7,
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
                                      page: TeacherNoticeBoardPage(
                                        teacherId: _teacherId ?? '',
                                        teacherName: _teacherName ??
                                            widget.fullName,
                                      ))).then(
                                  (_) => _loadNoticeUnread()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 8,
                            child: DashQuickLink(
                              icon: Icons.event_note_rounded,
                              title: tr('nav_student_apps'),
                              subtitle: trp('dash_sent_for',
                                  {'s': sectionLabel}),
                              color: const Color(0xFF0E9F6E),
                              colorEnd: const Color(0xFF34D399),
                              badge: SeenStore.badgeFor(_sentAppUnread),
                              onTap: () => _openStudentApplications().then(
                                  (_) => _loadBadges(_teacherSection)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 9,
                            child: DashQuickLink(
                              icon: Icons.task_rounded,
                              title: '📋 ${tr('nav_teacher_tasks')}',
                              subtitle: tr('task_my_sub'),
                              color: const Color(0xFF6D28D9),
                              colorEnd: const Color(0xFFA78BFA),
                              onTap: () {
                                final tid = _teacherId;
                                if (tid == null || tid.isEmpty) {
                                  _deny('Could not identify teacher account');
                                  return;
                                }
                                Navigator.push(
                                  context,
                                  SlidePageRoute(
                                    page: TeacherTasksPage(
                                      teacherId: tid,
                                      teacherName: _teacherName ??
                                          widget.fullName,
                                      section: _teacherSection ?? '',
                                    ),
                                  ),
                                );
                              },
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
}
