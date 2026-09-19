import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/id_card_print.dart';
import '../widgets/animations.dart';
import '../widgets/certificate_view.dart';

/// Print preview for an Achievement Certificate.
///
/// Plain white page with nothing but the certificate: the browser print
/// dialog (web) prints exactly this clean layout. "Download as PDF" is
/// the print dialog's Save-as-PDF destination.
class CertificatePrintPreview extends StatelessWidget {
  final Map<String, dynamic> certificate;
  const CertificatePrintPreview({super.key, required this.certificate});

  void _print(BuildContext context) async {
    final ok = await printIdCardPage();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Printing is available in the web version — open this preview there and use the browser print dialog (Save as PDF to download).',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        title: Text('Certificate Preview',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          children: [
            const SizedBox(height: 8),
            FadeInSlide(
              index: 0,
              child: CertificateView(certificate: certificate),
            ),
            const SizedBox(height: 24),
            FadeInSlide(
              index: 1,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _print(context),
                  icon: const Icon(Icons.print_rounded, size: 20),
                  label: Text('🖨️ Print / Download PDF',
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B2A5B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
