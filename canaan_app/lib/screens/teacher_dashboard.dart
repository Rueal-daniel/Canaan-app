import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/animations.dart';
import 'login_screen.dart';

class TeacherDashboard extends StatefulWidget {
  final String fullName;
  const TeacherDashboard({super.key, required this.fullName});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final _client = Supabase.instance.client;
  int _studentCount = 0;
  int _attendanceCount = 0;
  Map<String, int> _sectionCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _client.from('students').stream(primaryKey: ['id']).listen((_) => _fetchData());
  }

  Future<void> _fetchData() async {
    try {
      final students = await _client.from('students').select('section');
      final attendance = await _client.from('attendance_reports').select('id');

      final sections = <String, int>{};
      for (final s in students) {
        final sec = s['section'] ?? 'Unknown';
        sections[sec] = (sections[sec] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _studentCount = students.length;
          _attendanceCount = attendance.length;
          _sectionCounts = sections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          _getInitials(widget.fullName),
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(widget.fullName, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Teacher', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                color: Colors.white,
                onPressed: () {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.only(top: 100),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF1565C0))),
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeInSlide(index: 0, child: _statCard('Total Students', _studentCount, Icons.groups_rounded, const Color(0xFF42A5F5), const Color(0xFF1565C0))),
                        const SizedBox(height: 14),
                        FadeInSlide(index: 1, child: _attendanceCard()),
                        const SizedBox(height: 14),
                        FadeInSlide(index: 2, child: _sectionsCard()),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, int count, IconData icon, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: fg.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [bg, fg]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: fg.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                AnimatedCounter(
                  target: count,
                  style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.bold, color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceCard() {
    return Container(
      width: double.infinity,
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
                style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.assessment_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _sectionsCard() {
    final colors = {
      'sub-junior': const Color(0xFF7B1FA2),
      'junior': const Color(0xFF1565C0),
      'senior': const Color(0xFF43A047),
    };
    final labels = {
      'sub-junior': 'Sub Junior',
      'junior': 'Junior',
      'senior': 'Senior',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Sections', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0D47A1))),
          const SizedBox(height: 16),
          ...colors.entries.map((e) {
            final count = _sectionCounts[e.key] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: e.value.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.class_rounded, color: e.value, size: 20)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(labels[e.key] ?? e.key, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: e.value.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text('$count', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: e.value)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}
