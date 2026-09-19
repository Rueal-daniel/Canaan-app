import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/alert_inbox.dart';
import '../../widgets/animations.dart';

/// Teacher Dashboard → Quick Links → Alerts.
///
/// Shows ONLY alerts targeted at Teachers of the teacher's OWN assigned
/// section (or All Sections), live via Supabase Realtime. Student-only
/// and other-section alerts can never arrive here (query-level
/// targeting). Expired alerts (>24h) never appear.
class TeacherAlertsPage extends StatelessWidget {
  final String teacherId;
  final String teacherName;

  const TeacherAlertsPage({
    super.key,
    this.teacherId = '',
    this.teacherName = '',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('🚨 Alerts',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInSlide(
              index: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E1065), Color(0xFF6D28D9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF6D28D9).withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('🚨',
                        style: TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('Alerts',
                              style: GoogleFonts.poppins(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                              'Important updates from the Admin for your section.',
                              style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color: Colors.white
                                      .withValues(alpha: 0.92))),
                        ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            AlertInbox(
              role: 'teacher',
              userId: teacherId.trim(),
              gradient: const [Color(0xFF2E1065), Color(0xFF6D28D9)],
            ),
          ],
        ),
      ),
    );
  }
}
