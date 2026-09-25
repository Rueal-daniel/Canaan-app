import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';
import '../widgets/notice_rich_text.dart';

/// One-time "Canaan Updated Successfully" box. Shown as a dialog over
/// the splash right after an update, then never again for that version.
/// Uses the Admin's exact formatted update description.
Future<void> showUpdateSuccessDialog(
  BuildContext context, {
  required String previousName,
  required String currentName,
  List<String> whatsNew = const [],
  String descriptionHtml = '',
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF063B2E), Color(0xFF0E9F6E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_rounded,
                      color: Colors.white, size: 34),
                ),
                const SizedBox(height: 12),
                Text(tr('upd_success'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text('${tr('upd_version')} $previousName → $currentName',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (descriptionHtml.trim().isNotEmpty &&
                      !noticeHtmlIsEmpty(descriptionHtml)) ...[
                    Text(tr('upd_whats_new'),
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFF1F5F9)),
                      ),
                      child: NoticeContentView(descriptionHtml),
                    ),
                    const SizedBox(height: 8),
                  ] else if (whatsNew.isNotEmpty) ...[
                    Text(tr('upd_whats_new'),
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 8),
                    for (final item in whatsNew)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(item,
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      height: 1.5,
                                      color: const Color(0xFF374151))),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Text('Canaan has been successfully updated.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            color: const Color(0xFF374151))),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E9F6E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    child: Text(tr('upd_close'),
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
