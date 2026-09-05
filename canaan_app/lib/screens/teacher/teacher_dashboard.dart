import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/animations.dart';
import '../../widgets/dashboard_design.dart';
import '../../services/auth_service.dart';
import '../../services/notice_service.dart';
import '../../services/session_service.dart';
import '../admin/student_management.dart';
import '../login_screen.dart';
import 'download_center.dart';
import 'lesson_plan.dart';
import 'notice_board.dart';
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
  bool _isLoading = true;
  Timer? _suspensionTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
    // Suspended mid-session → sign out to Login with notice.
    _guardSuspension();
    _suspensionTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _guardSuspension(),
    );
    _client.from('students').stream(primaryKey: ['id']).listen((_) => _fetchData());
  }

  @override
  void dispose() {
    _suspensionTimer?.cancel();
    super.dispose();
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
        });
        _loadNoticeUnread();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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

  void _openMemoryVerse() {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
      _deny('No section assigned yet');
      return;
    }
    Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherMemoryVerse(
          teacherId: _teacherId ?? '',
          teacherName: _teacherName ?? widget.fullName,
          section: _teacherSection!,
        ),
      ),
    );
  }

  void _openLessonPlan() {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
      _deny('No section assigned yet');
      return;
    }
    Navigator.push(
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
      body: RefreshIndicator(
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
              flexibleSpace: FlexibleSpaceBar(
                background: DashboardHero(
                  gradient: DashColors.teacherGradient,
                  greeting: dashGreeting(),
                  name: _teacherName ?? widget.fullName,
                  roleLabel: 'Teacher',
                  sectionLabel: sectionLabel,
                ),
              ),
              actions: [
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
                              child: DashSectionHeading('Overview',
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
                                  label: 'My Students',
                                  value: '$_myStudentCount',
                                  subtitle: sectionLabel,
                                  icon: Icons.group_outlined,
                                  color: const Color(0xFF6366F1),
                                  onTap: _openMyStudents,
                                ),
                                DashStat(
                                  label: 'Memory Verses',
                                  value: '$_memoryVerseCount',
                                  subtitle: 'This section',
                                  icon: Icons.menu_book_outlined,
                                  color: const Color(0xFF22C55E),
                                  onTap: _openMemoryVerse,
                                ),
                                DashStat(
                                  label: 'Lesson Plans',
                                  value: '$_lessonPlanCount',
                                  subtitle: 'Published',
                                  icon: Icons.description_outlined,
                                  color: const Color(0xFFFF9F0A),
                                  onTap: _openLessonPlan,
                                ),
                                DashStat(
                                  label: 'Notifications',
                                  value: '$_notificationCount',
                                  subtitle: 'Latest updates',
                                  icon: Icons.notifications_outlined,
                                  color: const Color(0xFFA855F7),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 2,
                              child: const DashSectionHeading('Quick Links')),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 3,
                            child: DashQuickLink(
                              icon: Icons.school_rounded,
                              title: 'Students',
                              subtitle:
                                  'View $sectionLabel students ($_myStudentCount)',
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
                              title: 'My Attendance',
                              subtitle: 'View your attendance history',
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
                              title: '📚 Lesson Plan',
                              subtitle: 'View $sectionLabel lesson plan',
                              color: const Color(0xFFFF9F0A),
                              colorEnd: const Color(0xFFFFB74D),
                              onTap: _openLessonPlan,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 6,
                            child: DashQuickLink(
                              icon: Icons.download_rounded,
                              title: '📥 Download Center',
                              subtitle: 'Resources shared with you',
                              color: const Color(0xFF1565C0),
                              colorEnd: const Color(0xFF42A5F5),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page:
                                          const TeacherDownloadCenterPage())),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 7,
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
                                      page: TeacherNoticeBoardPage(
                                        teacherId: _teacherId ?? '',
                                        teacherName: _teacherName ??
                                            widget.fullName,
                                      ))).then(
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
}
