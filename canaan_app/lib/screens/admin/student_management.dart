import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/language_service.dart';
import '../../widgets/animations.dart';
import '../teacher/memory_verse.dart';
import '../teacher/std_attendance.dart';
import 'std_report.dart';
import 'memory_verse_report.dart';
import 'std_photo.dart';
import 'std_suspension.dart';
import 'student_details.dart';
import 'add_student.dart';
import 'leave_applications.dart';
import 'student_applications.dart';
import 'student_id_cards.dart';
import 'student_progress.dart';

class StudentManagement extends StatelessWidget {
  final String? lockedSection;
  final bool readOnly;
  final String teacherId;
  final String teacherName;
  const StudentManagement({
    super.key,
    this.lockedSection,
    this.readOnly = false,
    this.teacherId = '',
    this.teacherName = '',
  });

  String _prettySection(String? section) {
    if (section == null || section.isEmpty) return '';
    if (section == 'sub-junior') return 'Sub Junior';
    return section[0].toUpperCase() + section.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = lockedSection != null && lockedSection!.isNotEmpty;
    final sectionLabel = _prettySection(lockedSection);
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
          isLocked
              ? trp('opt_view_sec_students', {'s': sectionLabel})
              : tr('hub_student_mgmt'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LangBuilder(
        builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLocked ? tr('hub_my_section') : tr('hub_student_section'),
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 16),
            if (!isLocked)
              FadeInSlide(
                index: 0,
                child: _OptionCard(
                  icon: Icons.person_add_rounded,
                  title: tr('opt_add_student'),
                  subtitle: tr('opt_add_student_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(page: const AddStudent()),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            FadeInSlide(
              index: isLocked ? 0 : 1,
              child: _OptionCard(
                icon: Icons.people_rounded,
                title: tr('opt_student_details'),
                subtitle: isLocked
                    ? trp('opt_view_sec_students', {'s': sectionLabel})
                    : tr('opt_view_all_sec'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                      page: StudentDetails(
                        lockedSection: lockedSection,
                        readOnly: readOnly,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (isLocked) const SizedBox(height: 12),
            if (isLocked)
              FadeInSlide(
                index: 1,
                child: _OptionCard(
                  icon: Icons.fact_check_rounded,
                  title: tr('opt_std_att'),
                  subtitle: tr('opt_mark_sat'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: StdAttendance(
                          teacherId: teacherId,
                          teacherName: teacherName,
                          section: lockedSection!,
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isLocked) const SizedBox(height: 12),
            if (isLocked)
              FadeInSlide(
                index: 2,
                child: _OptionCard(
                  icon: Icons.menu_book_rounded,
                  title: tr('nav_memory_verse'),
                  subtitle: trp('opt_add_verses_for',
                      {'s': sectionLabel}),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF4ADE80)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: TeacherMemoryVerse(
                          teacherId: teacherId,
                          teacherName: teacherName,
                          section: lockedSection!,
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isLocked) const SizedBox(height: 12),
            if (isLocked)
              FadeInSlide(
                index: 3,
                child: _OptionCard(
                  icon: Icons.badge_rounded,
                  title: tr('nav_id_cards'),
                  subtitle: trp('opt_view_id_for',
                      {'s': sectionLabel}),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B2A5B), Color(0xFF42A5F5)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: StudentIdCardsPage(
                            lockedSection: lockedSection),
                      ),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 2,
                child: _OptionCard(
                  icon: Icons.assignment_rounded,
                  title: tr('opt_std_att_reports'),
                  subtitle: tr('opt_review_att_reports'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(page: const StdReport()),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 3,
                child: _OptionCard(
                  icon: Icons.no_accounts_rounded,
                  title: tr('opt_std_susp'),
                  subtitle: tr('opt_susp_std_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(page: const StdSuspension()),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 4,
                child: _OptionCard(
                  icon: Icons.add_a_photo_rounded,
                  title: tr('opt_std_photo'),
                  subtitle: tr('opt_std_photo_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00897B), Color(0xFF4DB6AC)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(page: const StdPhoto()),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 5,
                child: _OptionCard(
                  icon: Icons.menu_book_rounded,
                  title: tr('nav_memory_verses'),
                  subtitle: tr('opt_mem_verses_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF4ADE80)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: const TeacherMemoryVerse(isAdmin: true),
                      ),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 6,
                child: _OptionCard(
                  icon: Icons.fact_check_rounded,
                  title: tr('opt_mem_reports'),
                  subtitle: tr('opt_mem_reports_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: const MemoryVerseReports(),
                      ),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 7,
                child: _OptionCard(
                  icon: Icons.event_note_rounded,
                  title: tr('nav_leave'),
                  subtitle: tr('opt_review_leave'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0E9F6E), Color(0xFF34D399)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: const AdminLeaveApplicationsPage(),
                      ),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 8,
                child: _OptionCard(
                  icon: Icons.send_rounded,
                  title: tr('opt_std_app'),
                  subtitle: tr('opt_std_app_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: const AdminStudentApplicationsPage(),
                      ),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 9,
                child: _OptionCard(
                  icon: Icons.insights_rounded,
                  title: tr('nav_progress'),
                  subtitle: tr('opt_eval_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6D28D9), Color(0xFFA78BFA)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: const AdminStudentProgressPage(),
                      ),
                    );
                  },
                ),
              ),
            if (!isLocked) const SizedBox(height: 12),
            if (!isLocked)
              FadeInSlide(
                index: 10,
                child: _OptionCard(
                  icon: Icons.badge_rounded,
                  title: tr('nav_id_cards'),
                  subtitle: tr('opt_id_sub'),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B2A5B), Color(0xFF42A5F5)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: const StudentIdCardsPage(),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
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
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey.shade400,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
