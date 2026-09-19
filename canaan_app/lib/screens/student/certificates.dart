import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/certificate_service.dart';
import '../../services/linked_student_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/certificate_view.dart';
import '../certificate_print_preview.dart';

/// Student Dashboard → Certificates.
///
/// Shows ONLY officially published certificates belonging to the ACTIVE
/// (viewed) student — drafts never appear here. Each card offers View
/// and Print/Download (Save as PDF via the print dialog).
class StudentCertificatesPage extends StatefulWidget {
  final String studentName;

  /// Active (viewed) student id — linked-family aware.
  final String? studentId;

  const StudentCertificatesPage({
    super.key,
    this.studentName = '',
    this.studentId,
  });

  @override
  State<StudentCertificatesPage> createState() =>
      _StudentCertificatesPageState();
}

class _StudentCertificatesPageState
    extends State<StudentCertificatesPage> {
  List<Map<String, dynamic>> _certs = [];
  bool _isLoading = true;
  String? _loadError;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
    _watchRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _watchRealtime() {
    try {
      _realtimeSub = Supabase.instance.client
          .from(CertificateService.table)
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _load(silent: true);
      });
    } catch (_) {}
  }

  Future<String> _resolveId() async {
    final explicit = (widget.studentId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    try {
      return await LinkedStudentService.effectiveStudentId();
    } catch (_) {
      return '';
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final sid = await _resolveId();
      final rows = await CertificateService.publishedForStudent(sid);
      if (!mounted) return;
      setState(() {
        _certs = rows;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load certificates. ($e)';
        });
      }
    }
  }

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
        title: Text('Certificates',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        color: const Color(0xFF0E9F6E),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerCard(),
                const SizedBox(height: 16),
                Text('My Certificates (${_certs.length})',
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 12),
                _body(),
              ]),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return FadeInSlide(
      index: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B2A5B), Color(0xFF1565C0)],
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
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: Color(0xFFFFD971), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Certificates',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Achievement certificates published by Admin.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.92))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF0E9F6E))),
      );
    }
    if (_loadError != null) {
      return _messageCard(
          '⚠️', _loadError!, _load, const Color(0xFFEF4444));
    }
    if (_certs.isEmpty) {
      return _emptyCard();
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _certs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => FadeInSlide(
        index: 1,
        child: _certCard(_certs[i]),
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('🏆', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No Certificates Available',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF374151))),
        const SizedBox(height: 6),
        Text(
            'Certificates for Rank 1–3 leaderboard achievements will appear here once Admin publishes them.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _messageCard(
      String emoji, String message, VoidCallback onRetry, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text('Retry',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _certCard(Map<String, dynamic> c) {
    final position = (c['position'] as num?)?.toInt() ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B2A5B), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B2A5B).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Color(0xFFFFD971), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🏆 Achievement Certificate',
                      style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                      '${CertificateService.categoryLabel((c['category'] ?? '').toString())} · ${CertificateService.positionLabel(position)}',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.85))),
                ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () =>
                    showCertificatePreview(context, c),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: Text('View',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B2A5B),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  SlidePageRoute(
                    page: CertificatePrintPreview(certificate: c),
                  ),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Download',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E9F6E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
