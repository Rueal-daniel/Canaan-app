import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_update_service.dart';
import 'updating_screen.dart';

/// Shown when the remote check found a newer APK.
/// Force updates can't be dismissed; optional updates show "Later".
class UpdateAvailableScreen extends StatelessWidget {
  final RemoteUpdate update;
  const UpdateAvailableScreen({super.key, required this.update});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !update.forceUpdate,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !update.forceUpdate) {
          AppUpdateService.markSkipped(update.versionCode);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F5F9),
        appBar: AppBar(
          elevation: 0,
          automaticallyImplyLeading: !update.forceUpdate,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text('Update Available',
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(update.updateTitle,
                              style: GoogleFonts.poppins(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(update.updateDescription,
                              style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color:
                                      Colors.white.withValues(alpha: 0.9))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill('Version ${update.versionName}',
                                  Colors.white),
                              if (update.forceUpdate)
                                _pill('Required', Colors.white),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (update.whatsNew.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text("What's New",
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in update.whatsNew)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin:
                                    const EdgeInsets.only(top: 6),
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1565C0),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(item,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        height: 1.5,
                                        color: const Color(
                                            0xFF374151))),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 100),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UpdatingScreen(update: update),
                        ),
                      );
                    },
                    icon: const Icon(Icons.system_update_rounded,
                        size: 20),
                    label: Text('Update Now',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
                if (!update.forceUpdate) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () {
                        AppUpdateService.markSkipped(
                            update.versionCode);
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1565C0),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Later',
                          style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pill(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text,
        style: GoogleFonts.poppins(
            fontSize: 12, fontWeight: FontWeight.w600, color: color)),
  );
}
