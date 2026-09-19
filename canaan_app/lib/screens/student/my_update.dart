import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/linked_student_service.dart';
import '../../services/student_update_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/student_update_detail.dart';

/// Student Dashboard → My Update.
///
/// Read-only personal feed: the student sees ONLY rows whose
/// `student_id` matches their own account — never another student's
/// updates, and no create/edit/delete controls exist here.
/// Realtime delivery: new Admin updates appear automatically.
class StudentMyUpdatePage extends StatefulWidget {
  final String fullName;
  final String? section;

  /// Active (viewed) student id — updates load for this student only.
  final String? studentId;
  const StudentMyUpdatePage({
    super.key,
    required this.fullName,
    this.section,
    this.studentId,
  });

  @override
  State<StudentMyUpdatePage> createState() => _StudentMyUpdatePageState();
}

class _StudentMyUpdatePageState extends State<StudentMyUpdatePage> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _updates = [];
  bool _isLoading = true;
  String? _loadError;
  String _studentId = '';
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _init();
    _subscribeRealtime();
  }

  Future<void> _init() async {
    await _resolveStudentId();
    await _fetchUpdates();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// The ACTIVE student's own row id — the ONLY key this page ever
  /// queries by (verified linked selection, never another student).
  Future<void> _resolveStudentId() async {
    var sid = (widget.studentId ?? '').trim();
    if (sid.isEmpty) {
      try {
        sid = await LinkedStudentService.effectiveStudentId();
      } catch (_) {}
    }
    if (sid.isEmpty && widget.fullName.trim().isNotEmpty) {
      try {
        final row = await _client
            .from('students')
            .select('id')
            .eq('full_name', widget.fullName.trim())
            .limit(1)
            .maybeSingle();
        sid = ((row?['id'] ?? '').toString());
      } catch (_) {}
    }
    if (mounted) setState(() => _studentId = sid);
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(StudentUpdateService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
        if (mounted) _fetchUpdates(silent: true);
      });
    } catch (_) {}
  }

  Future<void> _fetchUpdates({bool silent = false}) async {
    if (_studentId.isEmpty) {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
          _loadError = null;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final before = _updates
          .map(StudentUpdateService.updateIdOf)
          .where((id) => id >= 0)
          .toSet();
      // Ownership enforced at the query level: only MY student_id rows
      // are ever fetched — another student's updates can never arrive.
      final rows = await _client
          .from(StudentUpdateService.table)
          .select('*')
          .eq('student_id', _studentId)
          .order('created_at', ascending: false);
      final items = List<Map<String, dynamic>>.from(rows);
      if (mounted) {
        final hadBefore = before.isNotEmpty;
        final fresh = items
            .where((u) =>
                !before.contains(StudentUpdateService.updateIdOf(u)))
            .toList();
        setState(() {
          _updates = items;
          _isLoading = false;
          _loadError = null;
        });
        if (silent && hadBefore && fresh.isNotEmpty) {
          _snack(
            '📋 ${fresh.length == 1 ? 'New Student Update from Admin' : '${fresh.length} new Student Updates from Admin'}',
            const Color(0xFF0E9F6E),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load updates. Check your connection and try again. ($e)';
        });
      }
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
        title: Text('My Update',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _resolveStudentId();
          await _fetchUpdates();
        },
        color: const Color(0xFF0E9F6E),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 16),
              Text('My Updates (${_updates.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _body(),
            ],
          ),
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
            colors: [Color(0xFF063B2E), Color(0xFF0E9F6E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0E9F6E).withValues(alpha: 0.3),
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
            child: const Icon(Icons.assignment_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Updates',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Your weekly feedback from Admin.',
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
            onPressed: () => _fetchUpdates(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E9F6E),
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
    if (_studentId.isEmpty) {
      return _emptyCard(
        'Could not identify your account.\nPlease log in again to see your updates.',
      );
    }
    if (_updates.isEmpty) {
      return _emptyCard(
        'No Updates Yet\n\nYour Student Updates will appear here after Admin adds them.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _updates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => FadeInSlide(
        index: 1,
        child: _updateCard(_updates[i]),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('📋', style: TextStyle(fontSize: 48)),
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

  Widget _updateCard(Map<String, dynamic> update) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: Color(0xFF0E9F6E), width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📅 ${StudentUpdateService.prettyDate(update)}',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 4),
          Text('Student Update',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  StudentUpdateService.starsLabel(
                      StudentUpdateService.ratingOf(update)),
                  style: GoogleFonts.poppins(fontSize: 15),
                ),
              ),
              Text('${StudentUpdateService.percentageOf(update)}%',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0E9F6E))),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => showStudentUpdateDetail(
                context,
                update,
                accent: const Color(0xFF0E9F6E),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View Update →',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0E9F6E))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
