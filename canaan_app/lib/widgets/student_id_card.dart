import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';
import '../services/student_id_service.dart';

/// Professional Digital Student ID Card (front).
///
/// Fixed CR80 ID-card proportions (1.586 : 1), responsive width, Canaan
/// branding with the app logo, student photo (initials fallback), name,
/// section and permanent Student ID. Pure display — edits happen
/// elsewhere, so students can never change data from the card.
///
/// Landscape layout (photo left, details right) so every element fits
/// the ratio with room to spare — no overflow on any screen or font
/// setting. Card typography is locked to print size for fidelity.
class StudentIdCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final double maxWidth;
  const StudentIdCard({
    super.key,
    required this.student,
    this.maxWidth = 380,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = ((student['full_name'] ?? '').toString().trim().isEmpty)
        ? 'Student'
        : (student['full_name'] ?? '').toString().trim();
    final section =
        StudentIdService.prettySection(student['section']?.toString());
    final idNumber = StudentIdService.idNumberOf(student);
    final photo = StudentIdService.photoUrl(
        student['photo_url']?.toString());
    final mq = MediaQuery.of(context);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : maxWidth)
            .clamp(280.0, maxWidth);
        final scale = w / 380;
        return SizedBox(
          width: w,
          child: MediaQuery(
            data: mq.copyWith(
                textScaler: const TextScaler.linear(1.0)),
            child: AspectRatio(
              aspectRatio: 1.586,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0B2A5B),
                      Color(0xFF1565C0),
                      Color(0xFF1E88E5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0B2A5B)
                          .withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      // Decorative shapes.
                      Positioned(
                        right: -40 * scale,
                        top: -50 * scale,
                        child: Container(
                          width: 160 * scale,
                          height: 160 * scale,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        left: -30 * scale,
                        bottom: -55 * scale,
                        child: Container(
                          width: 130 * scale,
                          height: 130 * scale,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(15 * scale),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            // Header: logo + school name.
                            Row(
                              children: [
                                Container(
                                  width: 30 * scale,
                                  height: 30 * scale,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'images/canaan logo.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        Icons.church_rounded,
                                        size: 18 * scale,
                                        color:
                                            const Color(0xFF1565C0),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8 * scale),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                            'CANAAN SUNDAY SCHOOL',
                                            style: GoogleFonts.poppins(
                                                fontSize: 13.5 * scale,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.1,
                                                color: Colors.white,
                                                height: 1.1)),
                                      ),
                                      Text('STUDENT IDENTITY CARD',
                                          style: GoogleFonts.poppins(
                                              fontSize: 8 * scale,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 2.4,
                                              color: Colors.white
                                                  .withValues(
                                                      alpha: 0.8))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10 * scale),
                            // Body: photo + details.
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding:
                                      EdgeInsets.all(2 * scale),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withValues(
                                            alpha: 0.85),
                                        width: 2 * scale),
                                  ),
                                  child: CircleAvatar(
                                    radius: 29 * scale,
                                    backgroundColor: Colors.white
                                        .withValues(alpha: 0.2),
                                    backgroundImage: photo.isNotEmpty
                                        ? NetworkImage(photo)
                                        : null,
                                    onBackgroundImageError:
                                        photo.isNotEmpty
                                            ? (_, _) {}
                                            : null,
                                    child: photo.isEmpty
                                        ? Text(_initials(name),
                                            style: GoogleFonts.poppins(
                                                fontSize: 22 * scale,
                                                fontWeight:
                                                    FontWeight.w800,
                                                color: Colors.white))
                                        : null,
                                  ),
                                ),
                                SizedBox(width: 12 * scale),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(name.toUpperCase(),
                                            maxLines: 1,
                                            style: GoogleFonts.poppins(
                                                fontSize: 17 * scale,
                                                fontWeight:
                                                    FontWeight.w800,
                                                letterSpacing: 0.5,
                                                color: Colors.white,
                                                height: 1.15)),
                                      ),
                                      SizedBox(height: 4 * scale),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 11 * scale,
                                            vertical: 2.5 * scale),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                              alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(
                                                      alpha: 0.35)),
                                        ),
                                        child: Text(
                                            section.toUpperCase(),
                                            style: GoogleFonts.poppins(
                                                fontSize: 9.5 * scale,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.3,
                                                color: Colors.white)),
                                      ),
                                      SizedBox(height: 6 * scale),
                                      Container(
                                        width: double.infinity,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10 * scale,
                                            vertical: 5 * scale),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  8 * scale),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment:
                                              Alignment.centerLeft,
                                          child: Text(
                                            idNumber.isEmpty
                                                ? '${tr('idcard_student_id')}: ${tr('idcard_pending')}'
                                                : '${tr('idcard_student_id')}: $idNumber',
                                            maxLines: 1,
                                            style: GoogleFonts.poppins(
                                                fontSize: 12.5 * scale,
                                                fontWeight:
                                                    FontWeight.w800,
                                                letterSpacing: 1.2,
                                                color: const Color(
                                                    0xFF0B2A5B)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Footer.
                            Text('Canaan Sunday School',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    fontSize: 9 * scale,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.8,
                                    color: Colors.white.withValues(
                                        alpha: 0.85))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
