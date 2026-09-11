import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../services/student_id_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/student_id_card.dart';
import '../id_card_print_preview.dart';

/// Student Dashboard → Quick Links → My Student ID.
///
/// The student sees ONLY their own card (resolved from their login —
/// never by picking from a list). Read-only: nothing on this screen
/// can change the ID, name, section or photo.
class MyStudentIdPage extends StatefulWidget {
  final String fullName;
  const MyStudentIdPage({super.key, this.fullName = ''});

  @override
  State<MyStudentIdPage> createState() => _MyStudentIdPageState();
}

class _MyStudentIdPageState extends State<MyStudentIdPage> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  String? _loadError;
  Map<String, dynamic>? _student;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    try {
      _sub = _client
          .from('students')
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _load(silent: true);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<String> _ownId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null &&
          session.role == UserRole.student.name &&
          session.userId.isNotEmpty) {
        return session.userId;
      }
    } catch (_) {}
    if (widget.fullName.trim().isNotEmpty) {
      try {
        final rows = await _client
            .from('students')
            .select('id')
            .eq('full_name', widget.fullName)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(rows);
        if (list.isNotEmpty) {
          return (list.first['id'] ?? '').toString();
        }
      } catch (_) {}
    }
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
      final id = await _ownId();
      if (id.isEmpty) throw Exception('account not found');
      var row = await StudentIdService.fetchStudent(id);
      if (row == null) throw Exception('account not found');
      // First view mints the permanent ID (never re-minted after).
      if (StudentIdService.idNumberOf(row).isEmpty) {
        await StudentIdService.ensureId(id);
        row = await StudentIdService.fetchStudent(id) ?? row;
      }
      if (!mounted) return;
      setState(() {
        _student = row;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load your ID card. ($e)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
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
        title: Text('My Student ID',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF0E9F6E),
        onRefresh: () => _load(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF0E9F6E))),
                )
              else if (_loadError != null)
                _errorState()
              else if (_student != null) ...[
                FadeInSlide(
                  index: 0,
                  child: Center(
                      child: StudentIdCard(student: _student!)),
                ),
                const SizedBox(height: 16),
                FadeInSlide(
                  index: 1,
                  child: Text(
                    'Your ID is permanent. If anything looks wrong, contact the Admin office.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 16),
                FadeInSlide(
                  index: 2,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        SlidePageRoute(
                          page: IdCardPrintPreview(
                              student: _student!),
                        ),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 20),
                      label: Text('Print Preview',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E9F6E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Icon(Icons.badge_outlined,
              size: 52, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(),
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
        ],
      ),
    );
  }
}
