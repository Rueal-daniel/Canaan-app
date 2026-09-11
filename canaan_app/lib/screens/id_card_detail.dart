import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_id_service.dart';
import '../widgets/animations.dart';
import '../widgets/student_id_card.dart';
import 'id_card_print_preview.dart';

/// Full Digital Student ID view (opened from the Admin/Teacher lists).
///
/// [canManage] (Admin only) shows Generate / Re-generate. Teachers get
/// a read-only view and a note when the ID is still pending; students
/// never reach this page (they use My Student ID).
class IdCardDetailPage extends StatefulWidget {
  final String studentId;
  final bool canManage;
  const IdCardDetailPage({
    super.key,
    required this.studentId,
    this.canManage = false,
  });

  @override
  State<IdCardDetailPage> createState() => _IdCardDetailPageState();
}

class _IdCardDetailPageState extends State<IdCardDetailPage> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  bool _isGenerating = false;
  String? _loadError;
  Map<String, dynamic>? _student;
  StreamSubscription? _sub;

  bool get _hasId =>
      _student != null &&
      StudentIdService.idNumberOf(_student!).isNotEmpty;

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

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final row =
          await StudentIdService.fetchStudent(widget.studentId);
      if (row == null) throw Exception('student not found');
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
          _loadError = 'Could not load the ID card. ($e)';
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

  Future<void> _generate({required bool forceNew}) async {
    if (_isGenerating) return;
    if (forceNew && mounted) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('Re-generate Student ID?',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          content: Text(
            'The current ID will be permanently replaced with a new one. Continue?',
            style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.grey.shade600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style:
                      GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Re-generate',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    setState(() => _isGenerating = true);
    try {
      final id = await StudentIdService.ensureId(
        widget.studentId,
        forceNew: forceNew,
      );
      if (id.isEmpty) throw Exception('no ID assigned');
      await _load(silent: true);
      _snack('✅ Student ID $id assigned.', Colors.green);
    } catch (e) {
      _snack('Could not assign an ID. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
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
              colors: [Color(0xFF0B2A5B), Color(0xFF1565C0), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Digital Student ID',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF1565C0)))
          : _loadError != null || _student == null
              ? _errorState()
              : RefreshIndicator(
                  color: const Color(0xFF1565C0),
                  onRefresh: () => _load(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        FadeInSlide(
                          index: 0,
                          child: Center(
                              child:
                                  StudentIdCard(student: _student!)),
                        ),
                        const SizedBox(height: 14),
                        if (!_hasId)
                          FadeInSlide(
                            index: 1,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.35)),
                              ),
                              child: Text(
                                widget.canManage
                                    ? 'No Student ID yet — generate one below.'
                                    : 'No Student ID yet — ask the Admin office to generate one.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: const Color(0xFF92400E)),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (widget.canManage)
                          FadeInSlide(
                            index: 2,
                            child: SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _isGenerating
                                    ? null
                                    : () => _generate(
                                        forceNew: _hasId),
                                icon: _isGenerating
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5))
                                    : Icon(
                                        _hasId
                                            ? Icons.refresh_rounded
                                            : Icons.badge_rounded,
                                        size: 20),
                                label: Text(
                                  _hasId
                                      ? 'Re-generate Student ID'
                                      : 'Generate Student ID',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF6D28D9),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFF6D28D9)
                                          .withValues(alpha: 0.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        if (widget.canManage)
                          const SizedBox(height: 12),
                        FadeInSlide(
                          index: 3,
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
                              icon: const Icon(Icons.print_rounded,
                                  size: 20),
                              label: Text('Print Preview',
                                  style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF0B2A5B),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                backgroundColor: const Color(0xFF1565C0),
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
      ),
    );
  }
}
