import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/alert_inbox.dart';
import '../../widgets/animations.dart';

/// Student Dashboard → Quick Links → Alerts.
///
/// Shows ONLY alerts targeted at Students of the student's OWN section
/// (or All Sections), live via Supabase Realtime. Teacher-only and
/// other-section alerts can never arrive here (query-level targeting).
/// Expired alerts (>24h) never appear.
class StudentAlertsPage extends StatelessWidget {
  final String studentName;

  /// Active (viewed) student id — linked-family aware.
  final String? studentId;

  const StudentAlertsPage({
    super.key,
    this.studentName = '',
    this.studentId,
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
              colors: [Color(0xFF063B2E), Color(0xFF0E9F6E), Color(0xFF4ADE80)],
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
                    colors: [Color(0xFF063B2E), Color(0xFF0E9F6E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF0E9F6E).withValues(alpha: 0.3),
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
              role: 'student',
              userId: (studentId ?? '').trim(),
              gradient: const [Color(0xFF063B2E), Color(0xFF0E9F6E)],
            ),
          ],
        ),
      ),
    );
  }
}
