import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/certificate_service.dart';
import '../../services/leaderboard_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/certificate_view.dart';
import '../certificate_print_preview.dart';

/// Teacher Dashboard → Certificates (read-only).
///
/// Shows PUBLISHED certificates for students of the teacher's OWN
/// assigned section (resolved server-side from the verified login id —
/// no section parameter to tamper with). Teachers cannot generate,
/// edit, publish or delete — View only.
class TeacherCertificatesPage extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  const TeacherCertificatesPage({
    super.key,
    this.teacherId = '',
    this.teacherName = '',
  });

  @override
  State<TeacherCertificatesPage> createState() =>
      _TeacherCertificatesPageState();
}

class _TeacherCertificatesPageState
    extends State<TeacherCertificatesPage> {
  List<Map<String, dynamic>> _certs = [];
  bool _isLoading = true;
  String? _loadError;
  String _section = '';
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

  Future<String> _resolveTeacherId() async {
    final explicit = widget.teacherId.trim();
    if (explicit.isNotEmpty) return explicit;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.teacher.name) {
        return session.userId.trim();
      }
    } catch (_) {}
    return '';
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final tid = await _resolveTeacherId();
      final section =
          await LeaderboardService.teacherSectionOf(tid);
      final rows =
          await CertificateService.publishedForSection(section);
      if (!mounted) return;
      setState(() {
        _section = section;
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
              colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)],
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
        color: const Color(0xFF6D28D9),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerCard(),
                const SizedBox(height: 16),
                Text('Section Certificates (${_certs.length})',
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 4),
                Text('Published certificates for your section (view only).',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500)),
                const SizedBox(height: 12),
                _body(),
              ]),
        ),
      ),
    );
  }

  Widget _headerCard() {
    final sectionLabel =
        LeaderboardService.prettySection(_section);
    return FadeInSlide(
      index: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E1065), Color(0xFF6D28D9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
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
                  Text('Certificates',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      sectionLabel.isEmpty
                          ? 'Published student achievements.'
                          : 'Published achievements · $sectionLabel section.',
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
            child: CircularProgressIndicator(color: Color(0xFF6D28D9))),
      );
    }
    if (_loadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
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
    if (_section.isEmpty) {
      return _emptyState(
          'No section assigned yet.\nPlease contact the Admin.');
    }
    if (_certs.isEmpty) {
      return _emptyState(
          'No published certificates in your section yet.\nThey appear here once Admin publishes them.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _certs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => FadeInSlide(
        index: 1,
        child: _certCard(_certs[i]),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('🏆', style: TextStyle(fontSize: 44)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151))),
      ]),
    );
  }

  Widget _certCard(Map<String, dynamic> c) {
    final position = (c['position'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFF6D28D9), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((c['student_name'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827))),
        const SizedBox(height: 2),
        Text(
            '${CertificateService.categoryLabel((c['category'] ?? '').toString())} · ${CertificateService.positionLabel(position)}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        Row(children: [
          _viewBtn(
            'View',
            Icons.visibility_rounded,
            () => showCertificatePreview(context, c),
          ),
          const SizedBox(width: 8),
          _viewBtn(
            'Print',
            Icons.print_rounded,
            () => Navigator.push(
              context,
              SlidePageRoute(
                page: CertificatePrintPreview(certificate: c),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _viewBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF6D28D9).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: const Color(0xFF6D28D9)),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6D28D9))),
        ]),
      ),
    );
  }
}
