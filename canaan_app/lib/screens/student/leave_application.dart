import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/leave_service.dart';
import '../../services/notification_service.dart';
import '../../services/seen_store.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';

/// Student Dashboard → Quick Links → Leave Application.
///
/// The student explains an absence (today auto-filled, from-date
/// picker, description). Submitting creates a Pending application —
/// attendance is never touched. Approvals/rejections arrive live
/// with the Admin's comment.
class StudentLeaveApplicationPage extends StatefulWidget {
  final String fullName;
  final String? section;
  const StudentLeaveApplicationPage({
    super.key,
    required this.fullName,
    this.section,
  });

  @override
  State<StudentLeaveApplicationPage> createState() =>
      _StudentLeaveApplicationPageState();
}

class _StudentLeaveApplicationPageState
    extends State<StudentLeaveApplicationPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _scrollController = ScrollController();

  Map<String, dynamic>? _student;
  DateTime? _fromDate;
  List<Map<String, dynamic>> _mine = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  StreamSubscription? _realtimeSub;

  String get _todayLabel =>
      LeaveService.prettyDate(LeaveService.todayStr());

  @override
  void initState() {
    super.initState();
    _init();
    _subscribeRealtime();
  }

  Future<void> _init() async {
    await _loadStudent();
    await _fetchMine();
  }

  @override
  void dispose() {
    _descController.dispose();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(LeaveService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchMine(silent: true);
          });
    } catch (_) {}
  }

  Future<void> _loadStudent() async {
    try {
      Map<String, dynamic>? row;
      try {
        final session = await SessionService.getSession();
        if (session != null && session.role == UserRole.student.name) {
          final res = await _client
              .from('students')
              .select('id, full_name, email, section')
              .eq('id', session.userId)
              .maybeSingle();
          if (res != null) row = Map<String, dynamic>.from(res);
        }
      } catch (_) {}
      if (row == null && widget.fullName.isNotEmpty) {
        try {
          final res = await _client
              .from('students')
              .select('id, full_name, email, section')
              .eq('full_name', widget.fullName)
              .limit(1);
          final list = List<Map<String, dynamic>>.from(res);
          if (list.isNotEmpty) row = list.first;
        } catch (_) {}
      }
      if (mounted) setState(() => _student = row);
    } catch (_) {}
  }

  String get _section =>
      LeaveService.normalizeSection(
          _student?['section']?.toString() ?? widget.section ?? '');

  Future<void> _fetchMine({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final myId = _student?['id']?.toString() ?? '';
      final myName = (_student?['full_name'] ?? widget.fullName).toString();
      List<Map<String, dynamic>> mine = [];
      if (myId.isNotEmpty) {
        try {
          final res = await _client
              .from(LeaveService.table)
              .select('*')
              .eq('student_id', myId)
              .order('created_at', ascending: false);
          mine = List<Map<String, dynamic>>.from(res);
        } catch (_) {}
      }
      if (mine.isEmpty && myName.trim().isNotEmpty) {
        try {
          final res = await _client
              .from(LeaveService.table)
              .select('*')
              .order('created_at', ascending: false)
              .limit(100);
          for (final r in (res as List)) {
            final m = Map<String, dynamic>.from(r as Map);
            if (LeaveService.norm(m['student_name']?.toString()) ==
                LeaveService.norm(myName)) {
              mine.add(m);
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      final prev = {
        for (final m in _mine) (m['id'] ?? '').toString(): (m['status'] ?? '').toString()
      };
      setState(() {
        _mine = mine;
        _isLoading = false;
        _loadError = null;
      });
      // Dashboard badge: decided applications count as seen once opened here.
      SeenStore.markSeen(
          'seen_student_leavedecisions',
          mine
              .where((m) =>
                  (m['status'] ?? '').toString() == 'approved' ||
                  (m['status'] ?? '').toString() == 'rejected')
              .map((m) => (m['id'] ?? '').toString()));
      // Realtime decision popups for previously-pending applications.
      if (silent && prev.isNotEmpty) {
        for (final m in mine) {
          final id = (m['id'] ?? '').toString();
          final was = prev[id];
          final now = (m['status'] ?? '').toString();
          if (was == LeaveService.statusPending && was != now) {
            if (now == LeaveService.statusApproved) {
              _decisionDialog(
                  approved: true,
                  message:
                      'Your leave application has been successfully approved by Admin.');
            } else if (now == LeaveService.statusRejected) {
              final comment =
                  (m['admin_comment'] ?? '').toString().trim();
              _decisionDialog(
                approved: false,
                message: 'Your leave application has been rejected by Admin.',
                comment: comment.isEmpty ? null : comment,
              );
            }
            break;
          }
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load your applications. Check your connection. ($e)';
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

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF0E9F6E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _fromDate =
          DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_fromDate == null) {
      _snack('Please choose the From date.', Colors.orange);
      return;
    }
    if (_student == null) {
      _snack('Could not identify your account. Please log in again.',
          Colors.red);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final today = LeaveService.todayStr();
      final now = DateTime.now().toIso8601String();
      final payload = <String, dynamic>{
        'student_id': (_student!['id'] ?? '').toString(),
        'student_name': (_student!['full_name'] ?? '').toString(),
        'student_email': (_student!['email'] ?? '').toString(),
        'section': _section,
        'application_date': today,
        'from_date': LeaveService.dateStr(_fromDate!),
        'description': _descController.text.trim(),
        'status': LeaveService.statusPending,
        'sent_to_teacher': false,
        'created_at': now,
        'updated_at': now,
      };
      String newId = '';
      try {
        final created = await _client
            .from(LeaveService.table)
            .insert(payload)
            .select('id')
            .single();
        newId = (created['id'] ?? '').toString();
      } catch (_) {
        // Row may already exist despite the failed round-trip:
        // recover its id instead of submitting a duplicate.
        newId = await NotificationService.recoverNewestId(
          table: LeaveService.table,
          match: {'student_id': (_student!['id'] ?? '').toString()},
        );
      }
      _descController.clear();
      setState(() => _fromDate = null);
      await _fetchMine(silent: true);
      // 🔔 Notify admins + confirm to the student (fire-and-forget).
      if (newId.isNotEmpty) {
        try {
          NotificationService.leaveSubmitted(
            applicationId: newId,
            studentId: (_student!['id'] ?? '').toString(),
            studentName: (_student!['full_name'] ?? '').toString(),
          );
        } catch (_) {}
      }
      if (!mounted) return;
      _pendingDialog();
    } catch (e) {
      _snack('Could not submit. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _pendingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                color: Color(0xFFF59E0B), size: 36),
          ),
          const SizedBox(height: 16),
          Text('Please Wait for Admin Approval',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              'Your leave application has been submitted successfully. Please wait for Admin approval.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Status: Pending',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309))),
          ),
          const SizedBox(height: 20),
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
              child: Text('OK',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  void _decisionDialog(
      {required bool approved, required String message, String? comment}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: approved
                  ? [const Color(0xFF22C55E), const Color(0xFF4ADE80)]
                  : [const Color(0xFFEF4444), const Color(0xFFF87171)]),
              shape: BoxShape.circle,
            ),
            child: Icon(
                approved
                    ? Icons.verified_rounded
                    : Icons.cancel_rounded,
                color: Colors.white,
                size: 36),
          ),
          const SizedBox(height: 16),
          Text(
              approved
                  ? 'Leave Application Approved'
                  : 'Leave Application Rejected',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600)),
          if (comment != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin Comment',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7280))),
                    const SizedBox(height: 4),
                    Text(comment,
                        style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            color: const Color(0xFF1F2937))),
                  ]),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: approved
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('OK',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
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
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Leave Application',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStudent();
          await _fetchMine();
        },
        color: const Color(0xFF0E9F6E),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              _formCard(),
              const SizedBox(height: 20),
              Text('My Leave Applications (${_mine.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _historyList(),
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
            child: const Icon(Icons.event_note_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leave Application',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'If you were absent, submit an application explaining the reason for your absence.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0E9F6E), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  Widget _formCard() {
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label("Today's Date"),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: Color(0xFF0E9F6E)),
                    const SizedBox(width: 10),
                    Text(_todayLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827))),
                  ]),
                ),
                const SizedBox(height: 14),
                _label('From Date'),
                GestureDetector(
                  onTap: _pickFromDate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.date_range_rounded,
                          size: 18, color: Color(0xFF0E9F6E)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            _fromDate == null
                                ? 'Select the leave date'
                                : LeaveService.prettyDate(
                                    LeaveService.dateStr(_fromDate!)),
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: _fromDate == null
                                    ? Colors.grey.shade400
                                    : const Color(0xFF111827),
                                fontWeight: _fromDate == null
                                    ? FontWeight.normal
                                    : FontWeight.w600)),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded,
                          color: Colors.grey),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                _label('Description / Message'),
                TextFormField(
                  controller: _descController,
                  maxLines: 5,
                  style: GoogleFonts.poppins(fontSize: 14, height: 1.6),
                  decoration: _dec(
                      'Write the reason for your absence here...'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please write the reason for your absence.'
                      : null,
                ),
                const SizedBox(height: 18),
                if (_isSubmitting) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: const LinearProgressIndicator(
                      color: Color(0xFF0E9F6E),
                      backgroundColor: Color(0xFFF1F5F9),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.send_rounded, size: 19),
                    label: Text('Submit Leave Application',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E9F6E),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF0E9F6E)
                          .withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case LeaveService.statusApproved:
        return const Color(0xFF22C55E);
      case LeaveService.statusRejected:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case LeaveService.statusApproved:
        return '🟢';
      case LeaveService.statusRejected:
        return '🔴';
      default:
        return '🟡';
    }
  }

  Widget _historyList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF0E9F6E))),
      );
    }
    if (_loadError != null) {
      final missing = _loadError!.contains('student_leave_applications') ||
          _loadError!.contains('PGRST205');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Icon(
              missing
                  ? Icons.storage_rounded
                  : Icons.cloud_off_rounded,
              size: 48,
              color: missing
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(
              missing
                  ? 'Leave applications are not set up yet. Please ask the Admin to enable them.'
                  : _loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _init,
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
    if (_mine.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Text('No applications yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13.5, color: Colors.grey.shade500)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _mine.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _historyCard(_mine[i]),
    );
  }

  Widget _historyCard(Map<String, dynamic> m) {
    final status = (m['status'] ?? '').toString();
    final color = _statusColor(status);
    final comment = (m['admin_comment'] ?? '').toString().trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                'Applied: ${LeaveService.prettyDate(m['application_date']?.toString())}',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
                '${_statusEmoji(status)} ${LeaveService.prettyStatus(status)}',
                style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('From: ${LeaveService.prettyDate(m['from_date']?.toString())}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Text((m['description'] ?? '').toString(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 13.5, height: 1.6, color: const Color(0xFF374151))),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin Comment',
                      style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6B7280))),
                  const SizedBox(height: 3),
                  Text(comment,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: const Color(0xFF1F2937))),
                ]),
          ),
        ],
      ]),
    );
  }
}
