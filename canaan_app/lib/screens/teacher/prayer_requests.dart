import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/prayer_request_board.dart';

/// Teacher Dashboard → Prayer Request.
///
/// Teachers submit and view the shared feed (including admin replies).
/// Reply controls never appear here — admin only.
class TeacherPrayerRequestPage extends StatelessWidget {
  final String teacherId;
  final String teacherName;
  final int? focusRequestId;
  const TeacherPrayerRequestPage({
    super.key,
    this.teacherId = '',
    this.teacherName = '',
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
              colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)],
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
        role: 'teacher',
        hintUserId: teacherId,
        hintFullName: teacherName,
        accent: const Color(0xFF6D28D9),
        focusRequestId: focusRequestId,
      ),
    );
  }
}
