import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/animations.dart';
import '../../widgets/dashboard_design.dart';
import 'student_management.dart';
import 'teacher_management.dart';
import 'management_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _subscribeToChanges();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _subscribeToChanges() {
    _client.from('admin').stream(primaryKey: ['id']).listen((_) => _fetchAll());
    _client.from('teachers').stream(primaryKey: ['id']).listen((_) => _fetchAll());
    _client.from('students').stream(primaryKey: ['id']).listen((_) => _fetchAll());
    _client.from('attendance_reports').stream(primaryKey: ['id']).listen((_) => _fetchAll());
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
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _splitSubtitle(Map<String, int> sections) {
    final sub = sections['sub-junior'] ?? 0;
    final jun = sections['junior'] ?? 0;
    final sen = sections['senior'] ?? 0;
    return '$sub Sub · $jun Jun · $sen Sen';
  }

  @override
  Widget build(BuildContext context) {
    final total = _adminCount + _teacherCount + _studentCount;

    return Scaffold(
      backgroundColor: DashColors.bg,
      body: RefreshIndicator(
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
              flexibleSpace: FlexibleSpaceBar(
                background: DashboardHero(
                  gradient: DashColors.adminGradient,
                  greeting:
                      '${dashGreeting()}, Admin',
                  name: widget.fullName,
                  roleLabel: 'Canaan Administrator',
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
                              color: Color(0xFF1565C0))),
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
                                  label: 'Total Users',
                                  value: '$total',
                                  subtitle:
                                      '$_adminCount admin · $_teacherCount teachers',
                                  icon: Icons.groups_rounded,
                                  color: const Color(0xFF1565C0),
                                ),
                                DashStat(
                                  label: 'Teachers',
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
                                  label: 'Students',
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
                                  label: 'Attendance Reports',
                                  value: '$_attendanceCount',
                                  subtitle: 'Submitted by teachers',
                                  icon: Icons.assessment_rounded,
                                  color: const Color(0xFF7B1FA2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 2,
                              child: const DashSectionHeading('By Section')),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 3,
                            child: _SectionBreakdownCard(
                              title: 'Teachers',
                              icon: Icons.co_present_rounded,
                              color: const Color(0xFFF59E0B),
                              sections: _teacherSections,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 4,
                            child: _SectionBreakdownCard(
                              title: 'Students',
                              icon: Icons.school_rounded,
                              color: const Color(0xFF22C55E),
                              sections: _studentSections,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FadeInSlide(
                              index: 5,
                              child: const DashSectionHeading('Quick Links')),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 6,
                            child: DashQuickLink(
                              icon: Icons.school_rounded,
                              title: 'Students',
                              subtitle: 'Manage students · $_studentCount total',
                              color: const Color(0xFF22C55E),
                              colorEnd: const Color(0xFF4ADE80),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: const StudentManagement())),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeInSlide(
                            index: 7,
                            child: DashQuickLink(
                              icon: Icons.co_present_rounded,
                              title: 'Teachers',
                              subtitle: 'Manage teachers · $_teacherCount total',
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
                              title: '⚙️ Management',
                              subtitle: 'Lesson plans & more',
                              color: const Color(0xFF7B1FA2),
                              colorEnd: const Color(0xFFAB47BC),
                              onTap: () => Navigator.push(
                                  context,
                                  SlidePageRoute(
                                      page: ManagementScreen(
                                          adminName: widget.fullName))),
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
                child: Text('$title by Section',
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
              label: 'Sub Junior', count: sub, max: maxVal, color: color),
          const SizedBox(height: 10),
          _SectionBarRow(
              label: 'Junior', count: jun, max: maxVal, color: color),
          const SizedBox(height: 10),
          _SectionBarRow(
              label: 'Senior', count: sen, max: maxVal, color: color),
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
