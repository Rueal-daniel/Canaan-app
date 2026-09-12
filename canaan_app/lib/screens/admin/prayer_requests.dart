import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/language_service.dart';
import '../../widgets/prayer_request_board.dart';

/// Admin Dashboard → Prayer Request.
///
/// Full control: submit, view the shared feed, Reply / Edit Reply /
/// Delete Reply on any request, and delete any request.
class AdminPrayerRequestPage extends StatelessWidget {
  final String adminName;
  final int? focusRequestId;
  const AdminPrayerRequestPage({
    super.key,
    this.adminName = '',
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
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
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
      body: LangBuilder(
        builder: (_) => PrayerRequestBoard(
          role: 'admin',
          hintFullName: adminName,
          accent: const Color(0xFF1565C0),
          focusRequestId: focusRequestId,
        ),
      ),
    );
  }
}
