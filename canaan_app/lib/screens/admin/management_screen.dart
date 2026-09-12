import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/language_service.dart';
import '../../widgets/animations.dart';
import 'download_center.dart';
import 'events_calendar.dart';
import 'lesson_plan.dart';
import 'notice_board.dart';
import 'school_gallery.dart';
import 'student_update.dart';

/// Admin Dashboard → Management.
///
/// Hub for admin management options. For now it hosts Lesson Plan.
class ManagementScreen extends StatelessWidget {
  final String adminName;
  const ManagementScreen({super.key, this.adminName = ''});

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
          tr('nav_management'),
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
              tr('hub_mgmt_options'),
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('hub_mgmt_sub'),
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            FadeInSlide(
              index: 0,
              child: _OptionCard(
                icon: Icons.menu_book_rounded,
                title: tr('nav_lesson_plan'),
                subtitle: tr('hub_make_lesson'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                        page: AdminLessonPlanPage(adminName: adminName)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 1,
              child: _OptionCard(
                icon: Icons.download_rounded,
                title: tr('nav_download'),
                subtitle: tr('hub_share_dl'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                        page: AdminDownloadCenterPage(adminName: adminName)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 2,
              child: _OptionCard(
                icon: Icons.campaign_rounded,
                title: tr('nav_notice_board'),
                subtitle: tr('hub_pub_notices'),
                gradient: const LinearGradient(
                  colors: [Color(0xFFB45309), Color(0xFFF59E0B)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                          page: AdminNoticeBoardPage(adminName: adminName)),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 3,
              child: _OptionCard(
                icon: Icons.event_rounded,
                title: tr('nav_events_calendar'),
                subtitle: tr('hub_events_sub'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                        page: AdminEventsCalendarPage(
                            adminName: adminName)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 4,
              child: _OptionCard(
                icon: Icons.photo_library_rounded,
                title: tr('nav_school_gallery'),
                subtitle: tr('hub_gallery_sub'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                        page: AdminSchoolGalleryPage(
                            adminName: adminName)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FadeInSlide(
              index: 5,
              child: _OptionCard(
                icon: Icons.assignment_rounded,
                title: tr('nav_student_update'),
                subtitle: tr('hub_student_update_sub'),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(
                        page: AdminStudentUpdatePage(
                            adminName: adminName)),
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
