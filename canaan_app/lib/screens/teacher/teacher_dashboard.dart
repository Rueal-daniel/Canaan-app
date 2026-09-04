import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/animations.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';
import '../admin/student_management.dart';

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
  int _memoryVerseCount = 1;
  int _lessonPlanCount = 0;
  int _notificationCount = 4;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _client.from('students').stream(primaryKey: ['id']).listen((_) => _fetchData());
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

      // 3. Optional: try to load real counts if those tables exist,
      //    otherwise keep the placeholder numbers from the design.
      int memoryCount = _memoryVerseCount;
      int lessonCount = _lessonPlanCount;
      int notifCount = _notificationCount;
      try {
        final mv = await _client.from('memory_verses').select('id');
        memoryCount = mv.length;
      } catch (_) {}
      try {
        final lp = await _client.from('lesson_plans').select('id');
        lessonCount = lp.length;
      } catch (_) {}
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
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openMyStudents() {
    if (_teacherSection == null || _teacherSection!.isEmpty) {
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

  String _formatSection(String? section) {
    if (section == null || section.isEmpty) return 'Not Assigned';
    if (section == 'sub-junior') return 'Sub Junior';
    if (section.length == 1) return section.toUpperCase();
    return section[0].toUpperCase() + section.substring(1);
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
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
                      Text(widget.fullName,
                          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Teacher',
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
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
                onPressed: () async {
                  await AuthService().logout();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                      context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
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
                        FadeInSlide(index: 0, child: _teachingSectionCard()),
                        const SizedBox(height: 12),
                        FadeInSlide(
                          index: 1,
                          child: _statCard(
                            title: 'My Students',
                            value: '$_myStudentCount',
                            icon: Icons.group_outlined,
                            color: const Color(0xFF6366F1),
                            onTap: _openMyStudents,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeInSlide(
                          index: 2,
                          child: _statCard(
                            title: 'Memory Verses',
                            value: '$_memoryVerseCount',
                            icon: Icons.menu_book_outlined,
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeInSlide(
                          index: 3,
                          child: _statCard(
                            title: 'Lesson Plans',
                            value: '$_lessonPlanCount',
                            icon: Icons.description_outlined,
                            color: const Color(0xFFFF9F0A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeInSlide(
                          index: 4,
                          child: _statCard(
                            title: 'Notifications',
                            value: '$_notificationCount',
                            icon: Icons.notifications_outlined,
                            color: const Color(0xFFA855F7),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeInSlide(index: 5, child: _buildQuickLinks()),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Purple header card — "Your Teaching Section / Junior"
  Widget _teachingSectionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.school_outlined, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Teaching Section',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatSection(_teacherSection),
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Quick Links — just like admin, but locked to teacher's section
  Widget _buildQuickLinks() {
    final sectionLabel = _formatSection(_teacherSection);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Links',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _openMyStudents,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF43A047).withValues(alpha: 0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF43A047), Color(0xFF66BB6A)]),
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: const Icon(Icons.school_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Students',
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
                      Text('View $sectionLabel students ($_myStudentCount)',
                          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF43A047), size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// White stat card — same style as student dashboard
  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.82)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 27),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
