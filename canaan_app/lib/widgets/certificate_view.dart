import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/certificate_service.dart';

/// Professional printable Certificate of Achievement.
///
/// Rendered from the certificate SNAPSHOT row (name, position, category,
/// section, date) — never live leaderboard data, so a published
/// certificate stays historically accurate. White background with navy +
/// gold formal styling; prints cleanly via the browser print dialog
/// (web → Save as PDF).
///
/// The signature mark is a decorative flourish drawn in code — NOT a real
/// person's signature.
class CertificateView extends StatelessWidget {
  final Map<String, dynamic> certificate;
  const CertificateView({super.key, required this.certificate});

  @override
  Widget build(BuildContext context) {
    final name = ((certificate['student_name'] ?? '').toString().trim().isEmpty)
        ? 'Student'
        : (certificate['student_name'] ?? '').toString().trim();
    final position =
        (certificate['position'] as num?)?.toInt() ?? 0;
    final category =
        CertificateService.categoryLabel((certificate['category'] ?? '').toString());
    final section =
        CertificateService.prettySection((certificate['section'] ?? '').toString());
    final date =
        CertificateService.prettyDate((certificate['certificate_date'] ?? '').toString());

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9A227), width: 5),
      ),
      child: Container(
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF0B2A5B), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // -- masthead --------------------------------------------------
            Image.asset(
              'images/canaan logo.png',
              height: 64,
              errorBuilder: (_, _, _) => Container(
                height: 64,
                width: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF0B2A5B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.school_rounded,
                    color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(height: 8),
            Text('CANAAN SUNDAY SCHOOL',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: const Color(0xFF0B2A5B))),
            const SizedBox(height: 10),
            Container(height: 2, width: 120, color: const Color(0xFFC9A227)),
            const SizedBox(height: 14),
            Text('CERTIFICATE OF ACHIEVEMENT',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: const Color(0xFF0B2A5B))),
            const SizedBox(height: 16),
            Text('We Kindly Honour',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF475569))),
            const SizedBox(height: 8),
            Text(name.toUpperCase(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: const Color(0xFF0B2A5B))),
            const SizedBox(height: 4),
            Container(
                height: 1.5,
                width: 200,
                color: const Color(0xFFC9A227)),
            const SizedBox(height: 14),
            Text('for securing',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF475569))),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 26, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B2A5B),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                  CertificateService.positionLabel(position),
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: const Color(0xFFFFD971))),
            ),
            const SizedBox(height: 10),
            Text('for outstanding performance in',
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFF475569))),
            const SizedBox(height: 4),
            Text(category,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0B2A5B))),
            if (section.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('$section Section',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B))),
            ],
            const SizedBox(height: 12),
            Text('Keep it up!',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: const Color(0xFFB45309))),
            const SizedBox(height: 20),
            // -- footer ----------------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(date.isEmpty ? '' : 'Date: $date',
                          style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: const Color(0xFF475569))),
                      const SizedBox(height: 4),
                      Container(
                          height: 1,
                          width: 130,
                          color: const Color(0xFF94A3B8)),
                      const SizedBox(height: 3),
                      Text('Date',
                          style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              color: const Color(0xFF64748B))),
                    ]),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(
                        height: 44,
                        width: 150,
                        child: CustomPaint(
                            painter: _SignatureFlourishPainter()),
                      ),
                      Container(
                          height: 1,
                          width: 150,
                          color: const Color(0xFF94A3B8)),
                      const SizedBox(height: 3),
                      Text('Canaan Administrator',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0B2A5B))),
                      Text('Canaan Sunday School',
                          style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              color: const Color(0xFF64748B))),
                    ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Decorative signature-style flourish (drawn mark — not a real signature).
class _SignatureFlourishPainter extends CustomPainter {
  const _SignatureFlourishPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0B2A5B)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.06, h * 0.75)
      ..cubicTo(w * 0.18, h * 0.1, w * 0.24, h * 0.1, w * 0.26, h * 0.62)
      ..cubicTo(w * 0.28, h * 0.85, w * 0.36, h * 0.8, w * 0.44, h * 0.55)
      ..cubicTo(w * 0.52, h * 0.3, w * 0.58, h * 0.35, w * 0.6, h * 0.6)
      ..cubicTo(w * 0.62, h * 0.8, w * 0.72, h * 0.78, w * 0.94, h * 0.55);
    canvas.drawPath(path, paint);
    final underline = Path()
      ..moveTo(w * 0.04, h * 0.86)
      ..quadraticBezierTo(w * 0.5, h * 0.98, w * 0.96, h * 0.78);
    canvas.drawPath(
        underline,
        paint
          ..strokeWidth = 1.2
          ..color = const Color(0xFFC9A227));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full-screen preview dialog for a certificate row.
void showCertificatePreview(
    BuildContext context, Map<String, dynamic> certificate) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CertificateView(certificate: certificate),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B2A5B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Close',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
