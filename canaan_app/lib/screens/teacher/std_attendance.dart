import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/attendance_report_service.dart';

/// Student Attendance (teacher side).
///
/// - Locked to the logged-in teacher's own section (no section picker).
/// - Saturday-only marking: controls + Save are enabled on Saturday;
///   on other days a notice is shown with previously saved reports.
/// - Saves into `attendance_reports` (one row per date + section) so the
///   Student Dashboard → My Attendance page picks it up automatically.
/// - Re-saving on the same Saturday updates the existing row
///   (no duplicate Student + Date records).
class StdAttendance extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String section;
  const StdAttendance({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.section,
  });

  @override
  State<StdAttendance> createState() => _StdAttendanceState();
}

class _StdAttendanceState extends State<StdAttendance> {
  final _client = Supabase.instance.client;

  // TEMP: Saturday-only restriction disabled for testing.
  // Set back to true to re-enable Saturday-only marking.
  static const bool _enforceSaturdayOnly = false;

  bool get _isSaturday =>
      !_enforceSaturdayOnly ||
      DateTime.now().weekday == DateTime.saturday;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSending = false;
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _statuses = {}; // student id -> present|absent|late
  int? _existingReportId;
  String _reportStatus = ''; // submitted|pending|approved|rejected
  String? _rejectionReason;
  String? _reviewedAt;
  List<Map<String, dynamic>> _pastReports = [];
  final _scrollController = ScrollController();
  final _tableKey = GlobalKey();

  int get _total => _students.length;
  int get _present => _statuses.values.where((s) => s == 'present').length;
  int get _absent => _statuses.values.where((s) => s == 'absent').length;
  int get _late => _statuses.values.where((s) => s == 'late').length;

  String get _dateStr {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  String get _dateLabel {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return 'Saturday, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

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

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  /// Section table holding one row per student per date.
  String? _sectionTable(String section) {
    switch (section) {
      case 'sub-junior':
        return 'attendance_sub_junior';
      case 'junior':
        return 'attendance_junior';
      case 'senior':
        return 'attendance_senior';
      default:
        return null;
    }
  }

  /// Mirrors the saved attendance into the section table
  /// (e.g. `attendance_junior`): one row per student + date.
  /// Existing rows for the date are updated, missing ones inserted.
  Future<void> _syncSectionTable(
      List<Map<String, String>> entries) async {
    final table = _sectionTable(widget.section);
    if (table == null) return;
    final now = DateTime.now().toIso8601String();

    final existingRows = await _client
        .from(table)
        .select('student_id')
        .eq('date', _dateStr);
    final existingIds = {
      for (final r in (existingRows as List)) r['student_id'].toString()
    };

    for (final e in entries) {
      final row = <String, dynamic>{
        'student_id': e['id'],
        'student_name': e['name'],
        'date': _dateStr,
        'status': e['status'],
        'marked_at': now,
      };
      if (widget.teacherId.isNotEmpty) {
        row['teacher_id'] = widget.teacherId;
      }
      if (existingIds.contains(e['id'])) {
        await _client
            .from(table)
            .update(row)
            .eq('student_id', e['id']!)
            .eq('date', _dateStr);
      } else {
        await _client.from(table).insert(row);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final students = await _client
          .from('students')
          .select('id, full_name, username, section')
          .eq('section', widget.section)
          .order('full_name');

      final list = List<Map<String, dynamic>>.from(students);
      final statuses = <String, String>{
        for (final s in list) s['id'].toString(): 'present',
      };
      int? reportId;
      String reportStatus = '';
      String? rejectionReason;
      String? reviewedAt;

      if (_isSaturday) {
        // Pre-fill today's existing report so corrections just update it.
        // select('*') stays compatible if review columns are added later.
        // limit(1) avoids errors if duplicate rows exist for the date.
        final existingRows = await _client
            .from('attendance_reports')
            .select('*')
            .eq('date', _dateStr)
            .eq('section', widget.section)
            .limit(1);
        final existing =
            existingRows.isNotEmpty ? existingRows.first : null;
        if (existing != null) {
          reportId = (existing['id'] as num?)?.toInt();
          reportStatus =
              AttendanceReportService.norm(existing['status']?.toString());
          rejectionReason = existing['rejection_reason']?.toString();
          reviewedAt = existing['reviewed_at']?.toString();
          final saved = existing['students'];
          if (saved is List) {
            final byName = <String, String>{};
            for (final e in saved) {
              if (e is Map) {
                byName[_norm(e['name']?.toString())] =
                    _norm(e['status']?.toString());
              }
            }
            for (final s in list) {
              final hit = byName[_norm(s['full_name']?.toString())];
              if (hit == 'present' || hit == 'absent' || hit == 'late') {
                statuses[s['id'].toString()] = hit!;
              }
            }
          }
        }
      } else {
        // Non-Saturday: read-only view of previously saved reports.
        final past = await _client
            .from('attendance_reports')
            .select('date, total_students, present_count, absent_count, late_count')
            .eq('section', widget.section)
            .order('date', ascending: false)
            .limit(10);
        _pastReports = List<Map<String, dynamic>>.from(past);
      }

      if (mounted) {
        setState(() {
          _students = list;
          _statuses = statuses;
          _existingReportId = reportId;
          _reportStatus = reportStatus;
          _rejectionReason = rejectionReason;
          _reviewedAt = reviewedAt;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load students.', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    // Re-validate with the actual device date at save time.
    if (_enforceSaturdayOnly &&
        DateTime.now().weekday != DateTime.saturday) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Attendance is available only on Saturday.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    if (_students.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final entries = _students
          .map((s) => {
                'id': s['id'].toString(),
                'name': (s['full_name'] ?? '').toString(),
                'status': _statuses[s['id'].toString()] ?? 'present',
              })
          .toList();

      final payload = <String, dynamic>{
        'date': _dateStr,
        'section': widget.section,
        'teacher_name': widget.teacherName,
        'students': entries,
        'total_students': _total,
        'present_count': _present,
        'absent_count': _absent,
        'late_count': _late,
        // A rejected report goes back to draft when corrected + saved,
        // so it can be sent for review again. Other states are kept.
        'status': _reportStatus == AttendanceReportService.rejected
            ? AttendanceReportService.submitted
            : (_reportStatus.isEmpty
                ? AttendanceReportService.submitted
                : _reportStatus),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (widget.teacherId.isNotEmpty) {
        payload['teacher_id'] = widget.teacherId;
      }

      if (_existingReportId != null) {
        await _client
            .from('attendance_reports')
            .update(payload)
            .eq('id', _existingReportId as int);
      } else {
        // Double-check to prevent duplicates (Student + Date).
        final existingRows = await _client
            .from('attendance_reports')
            .select('id')
            .eq('date', _dateStr)
            .eq('section', widget.section)
            .limit(1);
        if (existingRows.isNotEmpty) {
          final id = (existingRows.first['id'] as num).toInt();
          await _client.from('attendance_reports').update(payload).eq('id', id);
          _existingReportId = id;
        } else {
          final insertedRows = await _client
              .from('attendance_reports')
              .insert(payload)
              .select('id')
              .limit(1);
          final id = insertedRows.isNotEmpty
              ? (insertedRows.first['id'] as num?)?.toInt()
              : null;
          if (id != null) _existingReportId = id;
        }
      }

      if (!mounted) return;
      // Mirror into the section table (attendance_junior, ...).
      // Kept separate so a sync problem never masks the main save result.
      String? syncError;
      try {
        await _syncSectionTable(entries);
      } catch (e) {
        syncError = e.toString();
      }

      if (!mounted) return;
      if (syncError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to report, but section table update failed: $syncError',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      setState(() {
        // Keep local status in sync with what was just saved.
        if (_reportStatus == AttendanceReportService.rejected ||
            _reportStatus.isEmpty) {
          _reportStatus = AttendanceReportService.submitted;
        }
      });
      _showSavedPopup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save attendance: $e',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  /// "Attendance Saved Successfully!" popup with Send Report / Later.
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
                gradient: LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF4ADE80)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Attendance Saved Successfully!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            Text(
              'Attendance for $_dateLabel has been saved successfully. Would you like to send this attendance report to the Admin?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13.5, color: Colors.grey.shade600),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Send Report',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later', style: GoogleFonts.poppins(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends the saved report for admin review. Blocks duplicate sends.
  Future<void> _sendReport() async {
    if (_existingReportId == null) {
      _snack('Please save the attendance first.', Colors.orange);
      return;
    }
    if (_reportStatus == AttendanceReportService.pending ||
        _reportStatus == AttendanceReportService.approved) {
      _snack('Report Already Submitted', Colors.orange);
      return;
    }
    setState(() => _isSending = true);
    try {
      await AttendanceReportService.sendReport(_client, _existingReportId as int);
      if (!mounted) return;
      setState(() {
        _reportStatus = AttendanceReportService.pending;
        _rejectionReason = null;
        _reviewedAt = null;
      });
      _snack('Report sent! Status: Pending Admin Review', Colors.green);
    } catch (e) {
      _snack('Could not send report. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToTable() {
    final ctx = _tableKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
    }
  }

  String _prettyDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return '';
    }
  }

  /// Report-status banner shown above the table on Saturday.
  Widget _reportBanner() {
    if (_existingReportId == null || _reportStatus.isEmpty) {
      return const SizedBox.shrink();
    }
    final approved = _reportStatus == AttendanceReportService.approved;
    final rejected = _reportStatus == AttendanceReportService.rejected;
    final pending = _reportStatus == AttendanceReportService.pending;
    final color = AttendanceReportService.color(_reportStatus);
    final icon = approved
        ? Icons.verified_rounded
        : rejected
            ? Icons.cancel_rounded
            : pending
                ? Icons.hourglass_top_rounded
                : Icons.info_rounded;
    final title = approved
        ? 'Attendance Report Approved by Admin'
        : rejected
            ? 'Attendance Report Rejected'
            : pending
                ? 'Report Status: Pending Admin Review'
                : 'Attendance saved — not sent yet';
    final subtitle = approved
        ? 'Your attendance report for $_dateLabel has been approved by Admin${_prettyDateTime(_reviewedAt).isNotEmpty ? ' on ${_prettyDateTime(_reviewedAt)}' : ''}.'
        : rejected
            ? 'Reason from Admin: ${_rejectionReason?.isNotEmpty == true ? _rejectionReason! : 'No reason provided.'}'
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
          BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(subtitle, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Review & Resubmit',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
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
                  disabledBackgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : Text('Send Report',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
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
        title: Text('Student Attendance',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
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
                    _headerCard(),
                    const SizedBox(height: 12),
                    if (!_isSaturday) ...[
                      _saturdayNotice(),
                      const SizedBox(height: 20),
                      Text('Previously Saved Attendance',
                          style: GoogleFonts.poppins(
                              fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
                      const SizedBox(height: 12),
                      _pastList(),
                    ] else ...[
                      _reportBanner(),
                      if (_existingReportId != null && _reportStatus.isNotEmpty)
                        const SizedBox(height: 12),
                      _summaryGrid(),
                      const SizedBox(height: 16),
                      Row(
                        key: _tableKey,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('Mark Attendance - $_total Students',
                                style: GoogleFonts.poppins(
                                    fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Today',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _studentList(),
                      const SizedBox(height: 20),
                      _saveButton(),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _headerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
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
                child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Student Attendance',
                    style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Date: $_dateLabel',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.92))),
          const SizedBox(height: 4),
          Text('${_prettySection(widget.section)} Section',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _saturdayNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline_rounded, color: Color(0xFFF59E0B), size: 28),
          ),
          const SizedBox(height: 12),
          Text('Attendance is available only on Saturday.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          const SizedBox(height: 6),
          Text('Sunday School operates on Saturday. Marking is disabled today, but you can still view previously saved attendance below.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _pastList() {
    if (_pastReports.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text('No saved attendance yet.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _pastReports.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _pastReports[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_prettyDate((r['date'] ?? '').toString()),
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _countChip('Present ${r['present_count'] ?? 0}', const Color(0xFF22C55E)),
                  _countChip('Absent ${r['absent_count'] ?? 0}', const Color(0xFFEF4444)),
                  _countChip('Late ${r['late_count'] ?? 0}', const Color(0xFFF59E0B)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _countChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  String _prettyDate(String raw) {
    try {
      final d = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
    } catch (_) {
      return raw;
    }
  }

  Widget _summaryGrid() {
    final cards = [
      _miniStat('Total Students', '$_total', Icons.groups_rounded, const Color(0xFF6366F1)),
      _miniStat('Present', '$_present', Icons.check_circle_rounded, const Color(0xFF22C55E)),
      _miniStat('Absent', '$_absent', Icons.cancel_rounded, const Color(0xFFEF4444)),
      _miniStat('Late', '$_late', Icons.schedule_rounded, const Color(0xFFF59E0B)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 112,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF111827), height: 1)),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studentList() {
    if (_students.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.group_off_rounded, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No students in this section yet.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
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
        final username = (s['username'] ?? '').toString();
        final current = _statuses[id] ?? 'present';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF4ADE80)]),
                      shape: BoxShape.circle,
                    ),
                    child: Text(_initials(name),
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
                        if (username.isNotEmpty)
                          Text('@$username',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_prettySection(widget.section),
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _statusOption(id, 'present', 'Present', const Color(0xFF22C55E), current)),
                  const SizedBox(width: 8),
                  Expanded(child: _statusOption(id, 'absent', 'Absent', const Color(0xFFEF4444), current)),
                  const SizedBox(width: 8),
                  Expanded(child: _statusOption(id, 'late', 'Late', const Color(0xFFF59E0B), current)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusOption(String studentId, String value, String label, Color color, String current) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => setState(() => _statuses[studentId] = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : color)),
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
          disabledBackgroundColor: const Color(0xFF22C55E).withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text('Save Attendance',
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
