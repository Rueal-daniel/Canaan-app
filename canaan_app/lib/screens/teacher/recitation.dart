import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/recitation_service.dart';

/// Teacher → Student → Memory Verse → Mark Recitation.
///
/// Marks recitation for ONE verse, section students only.
/// Saves into the section recitation table; sending creates/updates
/// the row in `memory_verse_reports` for verse + teacher + date.
class MarkRecitation extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String section;
  final int verseId;
  final String verseReference;
  final String verseText;
  const MarkRecitation({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.section,
    required this.verseId,
    required this.verseReference,
    required this.verseText,
  });

  @override
  State<MarkRecitation> createState() => _MarkRecitationState();
}

class _MarkRecitationState extends State<MarkRecitation> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSending = false;
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _statuses = {}; // student id -> recited|half_recited|not_recited

  int? _reportId;
  String _reportStatus = '';
  String? _rejectionReason;

  final _scrollController = ScrollController();
  final _tableKey = GlobalKey();

  int get _total => _students.length;
  int get _recited =>
      _statuses.values.where((s) => s == RecitationService.recited).length;
  int get _half =>
      _statuses.values.where((s) => s == RecitationService.halfRecited).length;
  int get _notRecited =>
      _statuses.values.where((s) => s == RecitationService.notRecited).length;

  String get _today => RecitationService.todayStr();

  String _prettySection(String section) {
    if (section == 'sub-junior') return 'Sub Junior';
    if (section.isEmpty) return section;
    return section[0].toUpperCase() + section.substring(1);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final table = RecitationService.sectionTable(widget.section);
      final students = await _client
          .from('students')
          .select('id, full_name, username')
          .eq('section', widget.section)
          .order('full_name');
      final list = List<Map<String, dynamic>>.from(students);
      final statuses = <String, String>{
        for (final s in list)
          s['id'].toString(): RecitationService.notRecited,
      };

      // Pre-fill with previously saved recitation for this verse.
      if (table != null) {
        try {
          final saved = await _client
              .from(table)
              .select('student_id, status')
              .eq('verse_id', widget.verseId);
          for (final r in (saved as List)) {
            final st = RecitationService.norm(r['status']?.toString());
            if (RecitationService.isKnownRecitation(st)) {
              statuses[r['student_id'].toString()] = st;
            }
          }
        } catch (_) {}
      }

      await _loadTodaysReport();

      if (mounted) {
        setState(() {
          _students = list;
          _statuses = statuses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Could not load students.', Colors.red);
      }
    }
  }

  Future<void> _loadTodaysReport() async {
    try {
      final report = await RecitationService.findTodaysReport(
        _client,
        verseId: widget.verseId,
        teacherId: widget.teacherId,
        date: _today,
      );
      _reportId =
          report == null ? null : (report['id'] as num?)?.toInt();
      _reportStatus = report == null
          ? ''
          : RecitationService.norm(report['status']?.toString());
      final reason = report?['rejection_reason']?.toString();
      _rejectionReason =
          reason == null || reason.trim().isEmpty ? null : reason.trim();
    } catch (_) {
      _reportId = null;
      _reportStatus = '';
      _rejectionReason = null;
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

  Future<void> _save() async {
    if (!RecitationService.markingAllowed) {
      _snack('Recitation can only be done on Saturday.', Colors.orange);
      return;
    }
    final table = RecitationService.sectionTable(widget.section);
    if (table == null || _students.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      // Existing rows for this verse (dedupe key: student + verse).
      final existingRows = await _client
          .from(table)
          .select('student_id')
          .eq('verse_id', widget.verseId);
      final existingIds = {
        for (final r in (existingRows as List)) r['student_id'].toString()
      };

      for (final s in _students) {
        final sid = s['id'].toString();
        final row = <String, dynamic>{
          'student_id': sid,
          'student_name': (s['full_name'] ?? '').toString(),
          'verse_id': widget.verseId,
          'status': _statuses[sid] ?? RecitationService.notRecited,
          'date': _today,
        };
        if (widget.teacherId.isNotEmpty) {
          row['teacher_id'] = widget.teacherId;
        }
        if (existingIds.contains(sid)) {
          await _client
              .from(table)
              .update(row)
              .eq('student_id', sid)
              .eq('verse_id', widget.verseId);
        } else {
          await _client.from(table).insert(row);
        }
      }

      if (!mounted) return;
      _showSavedPopup();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      _snack(
        msg.contains('check constraint')
            ? 'Half Recited is not enabled in the database yet. Ask your admin to run the half_recited SQL.'
            : 'Could not save recitation: $e',
        Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSavedPopup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF4ADE80)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.menu_book_rounded,
                  color: Colors.white, size: 34),
            ),
            const SizedBox(height: 16),
            Text('Recitation Saved Successfully!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            Text(
              'The memory verse recitation has been saved successfully. Would you like to send this report to Admin?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendReport();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Send Report',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later',
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReport() async {
    if (_reportStatus == RecitationService.pending ||
        _reportStatus == RecitationService.approved) {
      _snack('Report Already Submitted', Colors.orange);
      return;
    }
    setState(() => _isSending = true);
    try {
      final details = _students
          .map((s) => {
                'id': s['id'].toString(),
                'name': (s['full_name'] ?? '').toString(),
                'username': (s['username'] ?? '').toString(),
                'status': _statuses[s['id'].toString()] ??
                    RecitationService.notRecited,
              })
          .toList();
      final payload = <String, dynamic>{
        'verse_id': widget.verseId.toString(),
        'verse_title': widget.verseReference,
        'verse_content': widget.verseText,
        'section': widget.section,
        'teacher_name': widget.teacherName,
        'date': _today,
        'total_students': _total,
        'recited_count': _recited,
        'half_recited_count': _half,
        'not_recited_count': _notRecited,
        'student_details': details,
      };
      if (widget.teacherId.isNotEmpty) {
        payload['teacher_id'] = widget.teacherId;
      }

      if (_reportId != null) {
        // Resubmission after rejection (or update of a draft).
        await RecitationService.sendReport(_client, _reportId as int, payload);
      } else {
        final existing = await RecitationService.findTodaysReport(
          _client,
          verseId: widget.verseId,
          teacherId: widget.teacherId,
          date: _today,
        );
        if (existing != null) {
          final st = RecitationService.norm(existing['status']?.toString());
          if (st == RecitationService.pending ||
              st == RecitationService.approved) {
            if (!mounted) return;
            setState(() {
              _reportId = (existing['id'] as num?)?.toInt();
              _reportStatus = st;
            });
            _snack('Report Already Submitted', Colors.orange);
            return;
          }
          final id = (existing['id'] as num).toInt();
          await RecitationService.sendReport(_client, id, payload);
          _reportId = id;
        } else {
          try {
            final inserted = await _client
                .from('memory_verse_reports')
                .insert({...payload, 'status': RecitationService.pending})
                .select('id')
                .limit(1);
            final rows = List<Map<String, dynamic>>.from(inserted);
            if (rows.isNotEmpty) {
              _reportId = (rows.first['id'] as num?)?.toInt();
            }
          } catch (_) {
            // Retry without newer columns if migration is pending.
            final fallback = Map<String, dynamic>.from(payload)
              ..removeWhere((k, _) => const {
                    'half_recited_count',
                    'rejection_reason',
                    'reviewed_by_admin_id',
                    'reviewed_at',
                  }.contains(k));
            final inserted = await _client
                .from('memory_verse_reports')
                .insert({...fallback, 'status': RecitationService.pending})
                .select('id')
                .limit(1);
            final rows = List<Map<String, dynamic>>.from(inserted);
            if (rows.isNotEmpty) {
              _reportId = (rows.first['id'] as num?)?.toInt();
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _reportStatus = RecitationService.pending;
        _rejectionReason = null;
      });
      _snack('Report sent! Status: Pending Admin Review', Colors.green);
    } catch (e) {
      _snack('Could not send report: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToTable() {
    final ctx = _tableKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400));
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
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Mark Recitation',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF1565C0),
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _verseHeader(),
                    const SizedBox(height: 12),
                    _reportBanner(),
                    if (_reportId != null && _reportStatus.isNotEmpty)
                      const SizedBox(height: 12),
                    if (!RecitationService.markingAllowed) ...[
                      _saturdayNotice(),
                      const SizedBox(height: 12),
                    ],
                    _summaryGrid(),
                    const SizedBox(height: 8),
                    Text('Total Students: $_total',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 16),
                    Text('Students - ${_prettySection(widget.section)}',
                        key: _tableKey,
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 12),
                    _studentList(),
                    const SizedBox(height: 20),
                    if (RecitationService.markingAllowed) _saveButton(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _verseHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.verseReference,
                    style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('"${widget.verseText}"',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withValues(alpha: 0.92))),
          const SizedBox(height: 8),
          Text(
              'Section: ${_prettySection(widget.section)} • ${RecitationService.prettyDate(_today)}',
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _saturdayNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: Color(0xFFF59E0B), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saturday Only',
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 2),
                Text('Recitation can only be done on Saturday.',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportBanner() {    if (_reportId == null || _reportStatus.isEmpty) {
      return const SizedBox.shrink();
    }
    final approved = _reportStatus == RecitationService.approved;
    final rejected = _reportStatus == RecitationService.rejected;
    final pending = _reportStatus == RecitationService.pending;
    final color = RecitationService.color(_reportStatus);
    final icon = approved
        ? Icons.verified_rounded
        : rejected
            ? Icons.cancel_rounded
            : pending
                ? Icons.hourglass_top_rounded
                : Icons.info_rounded;
    final title = approved
        ? 'Memory Verse Report Approved'
        : rejected
            ? 'Memory Verse Report Rejected'
            : pending
                ? 'Report Status: Pending Admin Review'
                : 'Recitation saved — not sent yet';
    final subtitle = approved
        ? 'Your memory verse recitation report has been approved by Admin.'
        : rejected
            ? 'Reason from Admin: ${_rejectionReason ?? 'No reason provided.'}'
            : pending
                ? 'Your report is waiting for admin review.'
                : 'Send it to the Admin when you are ready.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(subtitle,
              style:
                  GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          if (rejected) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _scrollToTable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Review & Resubmit',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          if (!approved && !pending && !rejected) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSending ? null : _sendReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF1565C0)
                      .withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Send Report',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryGrid() {
    final cards = [
      _miniStat('Recited', '$_recited', Icons.check_circle_rounded,
          const Color(0xFF22C55E)),
      _miniStat('Half Recited', '$_half', Icons.warning_amber_rounded,
          const Color(0xFFF59E0B)),
      _miniStat('Not Recited', '$_notRecited', Icons.cancel_rounded,
          const Color(0xFFEF4444)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 118,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                  height: 1)),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _studentList() {
    if (_students.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.group_off_rounded,
                size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No students in this section yet.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _students.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = _students[i];
        final id = s['id'].toString();
        final name = (s['full_name'] ?? '').toString();
        final current =
            _statuses[id] ?? RecitationService.notRecited;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6)
                  ]),
                  shape: BoxShape.circle,
                ),
                child: Text(_initials(name),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF111827))),
              ),
              const SizedBox(width: 8),
              _statusDropdown(id, current,
                  enabled: RecitationService.markingAllowed),
            ],
          ),
        );
      },
    );
  }

  Widget _statusDropdown(String studentId, String current,
      {bool enabled = true}) {
    final color = RecitationService.color(current);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: enabled ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          icon: Icon(Icons.arrow_drop_down_rounded,
              color: enabled ? color : Colors.grey.shade400),
          style: GoogleFonts.poppins(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
          dropdownColor: Colors.white,
          items: const [
            DropdownMenuItem(
                value: RecitationService.recited, child: Text('Recited')),
            DropdownMenuItem(
                value: RecitationService.halfRecited,
                child: Text('Half Recited')),
            DropdownMenuItem(
                value: RecitationService.notRecited,
                child: Text('Not Recited')),
          ],
          onChanged: enabled
              ? (v) {
                  if (v != null) setState(() => _statuses[studentId] = v);
                }
              : null,
        ),
      ),
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_isSaving || _students.isEmpty) ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22C55E),
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              const Color(0xFF22C55E).withValues(alpha: 0.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Text('Save Recitation',
                style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
