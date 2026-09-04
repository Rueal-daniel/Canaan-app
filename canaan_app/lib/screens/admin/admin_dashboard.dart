import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/profile_card.dart';
import '../../widgets/animations.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';
import 'student_management.dart';

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

  @override
  Widget build(BuildContext context) {
    final total = _adminCount + _teacherCount + _studentCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          'Admin Dashboard',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            color: Colors.white,
            onPressed: () async {
              await AuthService().logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : RefreshIndicator(
              onRefresh: _fetchAll,
              color: const Color(0xFF1565C0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    ProfileCard(fullName: widget.fullName, roleBadge: 'Canaan Administrator'),
                    const SizedBox(height: 6),
                    _buildTotalUsersCard(total),
                    _buildTeachersCard(),
                    _buildStudentsCard(),
                    _buildAttendanceCard(),
                    const SizedBox(height: 12),
                    _buildQuickLinks(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTotalUsersCard(int total) {
    final teacherPct = total > 0 ? _teacherCount / total : 0.0;
    final studentPct = total > 0 ? _studentCount / total : 0.0;
    final adminPct = total > 0 ? _adminCount / total : 0.0;

    return FadeInSlide(
      index: 1,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: const Color(0xFF1565C0).withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Users', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      AnimatedCounter(
                        target: total,
                        style: GoogleFonts.poppins(fontSize: 38, fontWeight: FontWeight.bold, color: const Color(0xFF0D47A1)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (adminPct > 0)
                      Expanded(flex: (adminPct * 1000).toInt(), child: Container(color: const Color(0xFF7B1FA2))),
                    if (teacherPct > 0)
                      Expanded(flex: (teacherPct * 1000).toInt(), child: Container(color: const Color(0xFFFFA000))),
                    if (studentPct > 0)
                      Expanded(flex: (studentPct * 1000).toInt(), child: Container(color: const Color(0xFF43A047))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _LegendItem2('$_adminCount admin', const Color(0xFF7B1FA2)),
                _LegendItem2('$_teacherCount teachers', const Color(0xFFFFA000)),
                _LegendItem2('$_studentCount students', const Color(0xFF43A047)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeachersCard() {
    final subJr = _teacherSections['sub-junior'] ?? 0;
    final jr = _teacherSections['junior'] ?? 0;
    final sr = _teacherSections['senior'] ?? 0;
    final maxVal = [subJr, jr, sr].fold(0, (a, b) => a > b ? a : b);

    return FadeInSlide(
      index: 2,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFA000), Color(0xFFFFB74D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFFFFA000).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Teachers', style: GoogleFonts.poppins(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 4),
                      AnimatedCounter(
                        target: _teacherCount,
                        style: GoogleFonts.poppins(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.school_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BarChart(
              values: [
                _BarData(subJr, '$subJr', Colors.white),
                _BarData(jr, '$jr', Colors.white),
                _BarData(sr, '$sr', Colors.white),
              ],
              maxValue: maxVal,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendItem2('Sub', Colors.white.withValues(alpha: 0.8)),
                _LegendItem2('Jun', Colors.white.withValues(alpha: 0.8)),
                _LegendItem2('Sen', Colors.white.withValues(alpha: 0.8)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsCard() {
    final subJr = _studentSections['sub-junior'] ?? 0;
    final jr = _studentSections['junior'] ?? 0;
    final sr = _studentSections['senior'] ?? 0;
    final maxVal = [subJr, jr, sr].fold(0, (a, b) => a > b ? a : b);

    return FadeInSlide(
      index: 3,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF43A047).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Students', style: GoogleFonts.poppins(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 4),
                      AnimatedCounter(
                        target: _studentCount,
                        style: GoogleFonts.poppins(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BarChart(
              values: [
                _BarData(subJr, '$subJr', Colors.white),
                _BarData(jr, '$jr', Colors.white),
                _BarData(sr, '$sr', Colors.white),
              ],
              maxValue: maxVal,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendItem2('Sub', Colors.white.withValues(alpha: 0.8)),
                _LegendItem2('Jun', Colors.white.withValues(alpha: 0.8)),
                _LegendItem2('Sen', Colors.white.withValues(alpha: 0.8)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard() {
    return FadeInSlide(
      index: 4,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF7B1FA2).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance Reports', style: GoogleFonts.poppins(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
                  const SizedBox(height: 4),
                  AnimatedCounter(
                    target: _attendanceCount,
                    style: GoogleFonts.poppins(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.assessment_rounded, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickLinks(BuildContext context) {
    return FadeInSlide(
      index: 5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Links',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {
                Navigator.push(context, SlidePageRoute(page: const StudentManagement()));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.2)),
                  boxShadow: [BoxShadow(color: const Color(0xFF43A047).withValues(alpha: 0.08), blurRadius: 15, offset: const Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF66BB6A)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Students', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
                          Text('Manage Students', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF43A047), size: 18),
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

class _LegendItem2 extends StatelessWidget {
  final String text;
  final Color color;
  const _LegendItem2(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(text, style: GoogleFonts.poppins(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _BarData {
  final int value;
  final String label;
  final Color color;
  const _BarData(this.value, this.label, this.color);
}

class _BarChart extends StatelessWidget {
  final List<_BarData> values;
  final int maxValue;
  const _BarChart({required this.values, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: values.map((bar) {
        final height = maxValue > 0 ? (bar.value / maxValue) * 55.0 : 0.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Text(bar.label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Container(
                  height: height.clamp(4.0, 55.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
