import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/credential_service.dart';
import '../../services/language_service.dart';
import '../../services/notification_navigation.dart';
import '../../services/password_reset_service.dart';
import '../../services/seen_store.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/dashboard_design.dart';
import '../../widgets/notification_bell.dart';
import 'student_management.dart';
import 'teacher_management.dart';
import 'management_screen.dart';
import 'authentication.dart';

class AdminDashboard extends StatefulWidget {
  final String fullName;
  const AdminDashboard({super.key, required this.fullName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _client = Supabase.instance.client;

  int _adminCount = 0;
  int _teacherCount = 0;
  int _studentCount = 0;
  int _attendanceCount = 0;
  Map<String, int> _teacherSections = {};
  Map<String, int> _studentSections = {};
  bool _isLoading = true;
  int _leavePending = 0;
  int _authPending = 0;
  String _notifUserId = '';
  final List<StreamSubscription> _realtimeSubs = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _subscribeToChanges();
    _loadNotifIdentity();
  }

  /// Resolves the logged-in admin's row id for the notification bell.
  /// Falls back to an `admin` table lookup by name: on shared devices
  /// the single saved session may belong to another role's last login.
  Future<void> _loadNotifIdentity() async {
    try {
      final session = await SessionService.getSession();
      if (!mounted) return;
      final role = (session?.role ?? '').trim().toLowerCase();
      if (session != null &&
          role == UserRole.admin.name &&
          session.userId.isNotEmpty) {
        setState(() => _notifUserId = session.userId);
        LanguageService.bind(role: 'admin', userId: session.userId);
        return;
      }
    } catch (_) {}
    try {
      final rows = await _client
          .from('admin')
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

  @override
  void dispose() {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  void _subscribeToChanges() {
    void watch(String table, Future<void> Function() onData) {
      try {
        _realtimeSubs.add(_client
            .from(table)
            .stream(primaryKey: ['id'])
            .listen((_) => onData()));
      } catch (_) {}
    }

    watch('admin', _fetchAll);
    watch('teachers', _fetchAll);
    watch('students', _fetchAll);
    watch('attendance_reports', _fetchAll);
    // Live pending-action badges.
    watch('student_leave_applications', _loadPendingBadges);
    watch('password_reset_requests', _loadPendingBadges);
    watch('credential_change_requests', _loadPendingBadges);
  }

  /// Red badges for work waiting on the Admin.
  Future<void> _loadPendingBadges() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        () async {
          try {
            final rows = await _client
                .from('student_leave_applications')
                .select('id')
                .eq('status', 'pending');
            return (rows as List).length;
          } catch (_) {
            return 0;
          }
        }(),
        () async {
          var n = 0;
          try {
            final rows = await _client
                .from('password_reset_requests')
                .select('id')
                .eq('status', PasswordResetService.statusPending);
            n += (rows as List).length;
          } catch (_) {}
          try {
            final rows = await _client
                .from('credential_change_requests')
                .select('id')
                .eq('status', CredentialService.statusPending);
            n += (rows as List).length;
          } catch (_) {}
          return n;
        }(),
      ]);
      if (!mounted) return;
      setState(() {
        _leavePending = results[0];
        _authPending = results[1];
      });
    } catch (_) {}
  }

  Future<void> _fetchAll() async {
    try {
      final adminRes = await _client.from('admin').select('id');
      final teacherRes = await _client.from('teachers').select('section');
      final studentRes = await _client.from('students').select('section');
      final attendanceRes = await _client.from('attendance_reports').select('id');

      final tSections = <String, int>{};
      for (final t in teacherRes) {
        final s = t['section'] ?? 'Unknown';
        tSections[s] = (tSections[s] ?? 0) + 1;
      }

      final sSections = <String, int>{};
      for (final s in studentRes) {
        final sec = s['section'] ?? 'Unknown';
        sSections[sec] = (sSections[sec] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _adminCount = adminRes.length;
          _teacherCount = teacherRes.length;
          _studentCount = studentRes.length;
          _attendanceCount = attendanceRes.length;
          _teacherSections = tSections;
          _studentSections = sSections;
          _isLoading = false;
        });
        _loadPendingBadges();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _splitSubtitle(Map<String, int> sections) {
    final sub = sections['sub-junior'] ?? 0;
    final jun = sections['junior'] ?? 0;
    final sen = sections['senior'] ?? 0;
    return trp('dash_split',
        {'a': '$sub', 'b': '$jun', 'c': '$sen'});
  }

  @override
  Widget build(BuildContext context) {
    final total = _adminCount + _teacherCount + _studentCount;

    return Scaffold(
      backgroundColor: DashColors.bg,
      drawer: CanaanSidebar(
        gradient: DashColors.adminGradient,
        fullName: widget.fullName,
        roleLabel: tr('role_admin'),
        role: 'admin',
        userId: _notifUserId,
      ),
      body: LangBuilder(
        builder: (_) => RefreshIndicator(
        onRefresh: _fetchAll,
        color: const Color(0xFF1565C0),
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
                  gradient: DashColors.adminGradient,
                  greeting:
                      '${dashGreeting()}, ${tr('role_admin_short')}',
                  name: widget.fullName,
                  roleLabel: tr('role_admin'),
                ),
              ),
              actions: [
                NotificationBell(
                  userId: _notifUserId,
                  role: 'admin',
                  gradient: DashColors.adminGradient,
                  onNotificationTap: (n) =>
                      NotificationNavigation.handleTap(
                    context,
                    role: 'admin',
                    notification: n,
                    fullName: widget.fullName,
                    adminName: widget.fullName,
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
                              color: Color(0xFF1565C0))),
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
                                  label: tr('dash_total_users'),
                                  value: '$total',
                                  subtitle:
                                      '$_adminCount ${tr('role_admin_short')} · $_teacherCount ${tr('dash_teachers')}',
                                  icon: Icons.groups_rounded,
                                  color: const Color(0xFF1565C0),
                                ),
                                DashStat(
                                  label: tr('dash_teachers'),
                                  value: '$_teacherCount',
                                  subtitle:
                                      _splitSubtitle(_teacherSections),
                                  icon: Icons.co_present_rounded,
                                  color: const Color(0xFFF59E0B),
                                  onTap: () => Navigator.push(
                                      context,
                                      SlidePageRoute(
                                          page: const TeacherManagement())),
                                ),
                                DashStat(
                                  label: tr('dash_students'),
                                  value: '$_studentCount',
                                  subtitle:
                                      _splitSubtitle(_studentSections),
                                  icon: Icons.school_rounded,
                                  color: const Color(0xFF22C55E),
                                  onTap: () => Navigator.push(
                                      context,
                                      SlidePageRoute(
                                          page: const StudentManagement())),
                                ),
                                DashStat(
                                  label: tr('dash_att_reports'),
                                  value: '$_attendanceCount',
                                  subtitle: tr('dash_submitted_by_teachers'),
                                  icon: Icons.assessment_rounded,
                                  color: const Color(0xFF7B1FA2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 2,
                              child: DashSectionHeading(
                                  tr('dash_by_section'))),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 3,
                            child: _SectionBreakdownCard(
                              title: tr('dash_teachers'),
                              icon: Icons.co_present_rounded,
                              color: const Color(0xFFF59E0B),
                              sections: _teacherSections,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 4,
                            child: _SectionBreakdownCard(
                              title: tr('dash_students'),
                              icon: Icons.school_rounded,
                              color: const Color(0xFF22C55E),
                              sections: _studentSections,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 5,
                              child: DashSectionHeading(
                                  tr('dash_quick_links'))),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 6,
                            child: DashQuickLink(
                              icon: Icons.school_rounded,
                              title: tr('dash_students'),
                              subtitle: trp('dash_manage_students',
                                  {'n': '$_studentCount'}),
                              color: const Color(0xFF22C55E),
                              colorEnd: const Color(0xFF4ADE80),
                              badge: SeenStore.badgeFor(_leavePending),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: const StudentManagement())).then(
                                  (_) => _loadPendingBadges()),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 7,
                            child: DashQuickLink(
                              icon: Icons.co_present_rounded,
                              title: tr('dash_teachers'),
                              subtitle: trp('dash_manage_teachers',
                                  {'n': '$_teacherCount'}),
                              color: const Color(0xFFF59E0B),
                              colorEnd: const Color(0xFFFFB74D),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: const TeacherManagement())),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 8,
                            child: DashQuickLink(
                              icon: Icons.settings_rounded,
                              title: '⚙️ ${tr('nav_management')}',
                              subtitle: tr('dash_manage_sub'),
                              color: const Color(0xFF7B1FA2),
                              colorEnd: const Color(0xFFAB47BC),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: ManagementScreen(
                                          adminName: widget.fullName))),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 9,
                            child: DashQuickLink(
                              icon: Icons.lock_person_rounded,
                              title: '🔐 ${tr('nav_authentication')}',
                              subtitle: tr('dash_auth_sub'),
                              color: const Color(0xFF0B2A5B),
                              colorEnd: const Color(0xFF1565C0),
                              badge: SeenStore.badgeFor(_authPending),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: AuthenticationPage(
                                          adminName: widget.fullName))).then(
                                  (_) => _loadPendingBadges()),
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

/// White card breaking a population down by Sub Junior / Junior / Senior
/// with slim horizontal progress bars.
class _SectionBreakdownCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Map<String, int> sections;
  const _SectionBreakdownCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final sub = sections['sub-junior'] ?? 0;
    final jun = sections['junior'] ?? 0;
    final sen = sections['senior'] ?? 0;
    final maxVal = [sub, jun, sen].fold(1, (a, b) => a > b ? a : b);
    final total = sub + jun + sen;

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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('$title ${tr('dash_by_section')}',
                    style: GoogleFonts.poppins(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: DashColors.ink)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$total',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionBarRow(
              label: tr('sec_sub'), count: sub, max: maxVal, color: color),
          const SizedBox(height: 10),
          _SectionBarRow(
              label: tr('sec_jun'), count: jun, max: maxVal, color: color),
          const SizedBox(height: 10),
          _SectionBarRow(
              label: tr('sec_sen'), count: sen, max: maxVal, color: color),
        ],
      ),
    );
  }
}

class _SectionBarRow extends StatelessWidget {
  final String label;
  final int count;
  final int max;
  final Color color;
  const _SectionBarRow({
    required this.label,
    required this.count,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final frac = max > 0 ? count / max : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: DashColors.muted)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 9,
              child: Stack(
                children: [
                  Container(color: color.withValues(alpha: 0.14)),
                  FractionallySizedBox(
                    widthFactor: frac.clamp(0.04, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [color, color.withValues(alpha: 0.7)]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 30,
          child: Text('$count',
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: DashColors.ink)),
        ),
      ],
    );
  }
}
