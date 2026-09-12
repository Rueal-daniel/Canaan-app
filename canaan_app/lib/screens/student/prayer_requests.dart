import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/prayer_request_board.dart';

/// Student Dashboard → Prayer Request.
///
/// Students submit and view the shared feed (including admin replies).
/// Reply controls never appear here — admin only.
class StudentPrayerRequestPage extends StatelessWidget {
  final String studentName;
  final int? focusRequestId;
  const StudentPrayerRequestPage({
    super.key,
    this.studentName = '',
    this.focusRequestId,
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
        title: Text('Prayer Request',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PrayerRequestBoard(
        role: 'student',
        hintFullName: studentName,
        accent: const Color(0xFF0E9F6E),
        focusRequestId: focusRequestId,
      ),
    );
  }
}
