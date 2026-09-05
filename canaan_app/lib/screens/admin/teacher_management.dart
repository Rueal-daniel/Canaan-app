import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/animations.dart';
import 'add_teacher.dart';
import 'teacher_attendance.dart';
import 'teacher_details.dart';
import 'teacher_suspension.dart';

class TeacherManagement extends StatelessWidget {
  const TeacherManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
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
          'Teacher Management',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teacher Section',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 16),
            FadeInSlide(
              index: 0,
              child: _OptionCard(
                icon: Icons.person_add_rounded,
                title: 'Add Teacher',
                subtitle: 'Add a new teacher to the system',
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFA000), Color(0xFFFFB74D)]),
                onTap: () {
                  Navigator.push(
                      context, SlidePageRoute(page: const AddTeacher()));
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 1,
              child: _OptionCard(
                icon: Icons.co_present_rounded,
                title: 'Teacher Details',
                subtitle: 'View all teachers by section',
                gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
                onTap: () {
                  Navigator.push(
                      context,
                      SlidePageRoute(
                          page: const TeacherDetails()));
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 2,
              child: _OptionCard(
                icon: Icons.fact_check_rounded,
                title: 'Teacher Attendance',
                subtitle: 'Mark teacher attendance',
                gradient: const LinearGradient(
                    colors: [Color(0xFF43A047), Color(0xFF66BB6A)]),
                onTap: () {
                  Navigator.push(
                      context,
                      SlidePageRoute(
                          page: const TeacherAttendanceAdmin()));
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 3,
              child: _OptionCard(
                icon: Icons.no_accounts_rounded,
                title: 'Teacher Suspension',
                subtitle: 'Suspend or restore teacher access',
                gradient: const LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFEF5350)]),
                onTap: () {
                  Navigator.push(
                      context,
                      SlidePageRoute(
                          page: const TeacherSuspension()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }
}
