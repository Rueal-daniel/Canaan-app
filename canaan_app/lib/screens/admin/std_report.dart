import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/attendance_report_service.dart';
import '../../services/session_service.dart';

/// Admin → Students → Student Attendance Reports.
///
/// Reviews attendance reports sent by teachers: view details,
/// approve, or reject with a mandatory reason.
class StdReport extends StatefulWidget {
  const StdReport({super.key});

  @override
  State<StdReport> createState() => _StdReportState();
}

class _StdReportState extends State<StdReport> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  String _filter = 'all'; // all|pending|approved|rejected

  int _count(String status) => _reports
      .where((r) =>
          AttendanceReportService.norm(r['status']?.toString()) == status)
      .length;

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _reports;
    return _reports
        .where((r) =>
            AttendanceReportService.norm(r['status']?.toString()) == _filter)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      // select('*') so new review columns work with or without migration.
      final rows = await _client
          .from('attendance_reports')
          .select('*')
          .order('date', ascending: false);
      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load reports.', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<String> _adminId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == 'admin') return session.userId;
    } catch (_) {}
    return '';
  }

  String _prettySection(String? section) {
    final s = (section ?? '').trim();
    if (s == 'sub-junior') return 'Sub Junior';
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _prettyDate(String raw) {
    try {
      final d = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return raw;
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
        title: Text('Student Attendance Reports',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : RefreshIndicator(
              onRefresh: _fetch,
              color: const Color(0xFF1565C0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryGrid(),
                    const SizedBox(height: 16),
                    _filterChips(),
                    const SizedBox(height: 12),
                    _reportList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _summaryGrid() {
    final cards = [
      _miniStat('Pending Reports', '${_count(AttendanceReportService.pending)}',
          Icons.hourglass_top_rounded, const Color(0xFFF59E0B)),
      _miniStat('Approved Reports', '${_count(AttendanceReportService.approved)}',
          Icons.verified_rounded, const Color(0xFF22C55E)),
      _miniStat('Rejected Reports', '${_count(AttendanceReportService.rejected)}',
          Icons.cancel_rounded, const Color(0xFFEF4444)),
      _miniStat('Total Reports', '${_reports.length}',
          Icons.folder_rounded, const Color(0xFF6366F1)),
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
                    style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w500, color: const Color(0xFF6B7280))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    const options = [
      ('all', 'All'),
      ('pending', 'Pending'),
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
            selectedColor: const Color(0xFF1565C0),
            labelStyle: GoogleFonts.poppins(
                color: _filter == value ? Colors.white : const Color(0xFF374151)),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
      ],
    );
  }

  Widget _reportList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.folder_off_rounded, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No reports found.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = items[i];
        final status = AttendanceReportService.norm(r['status']?.toString());
        final color = AttendanceReportService.color(status);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_prettyDate((r['date'] ?? '').toString()),
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
                  ),
                  _statusPill(status, color),
                ],
              ),
              const SizedBox(height: 6),
              Text('${r['teacher_name'] ?? ''} • ${_prettySection(r['section']?.toString())}',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _countChip('Total ${r['total_students'] ?? 0}', const Color(0xFF6366F1)),
                  _countChip('Present ${r['present_count'] ?? 0}', const Color(0xFF22C55E)),
                  _countChip('Absent ${r['absent_count'] ?? 0}', const Color(0xFFEF4444)),
                  _countChip('Late ${r['late_count'] ?? 0}', const Color(0xFFF59E0B)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => _viewReport(r),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('View', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
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

  Widget _statusPill(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(AttendanceReportService.label(status),
          style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  /// Detail card/modal with summary, student table and approve/reject.
  void _viewReport(Map<String, dynamic> r) {
    final reportId = (r['id'] as num).toInt();
    final status = AttendanceReportService.norm(r['status']?.toString());
    final color = AttendanceReportService.color(status);
    final students = r['students'] is List ? List.from(r['students']) : [];
    final sectionLabel = _prettySection(r['section']?.toString());
    final reason = r['rejection_reason']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('Attendance Report',
                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF111827))),
                  ),
                  _statusPill(status, color),
                ],
              ),
              const SizedBox(height: 8),
              Text('Date: ${_prettyDate((r['date'] ?? '').toString())}',
                  style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF374151))),
              Text('Teacher: ${r['teacher_name'] ?? ''}',
                  style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF374151))),
              Text('Section: $sectionLabel',
                  style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF374151))),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  children: [
                    Text('Summary', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    _summaryRow('Total Students', '${r['total_students'] ?? 0}'),
                    _summaryRow('Present', '${r['present_count'] ?? 0}'),
                    _summaryRow('Absent', '${r['absent_count'] ?? 0}'),
                    _summaryRow('Late', '${r['late_count'] ?? 0}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Students (${students.length})',
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      children: [
                        _cell('Student Name', header: true),
                        _cell('Section', header: true),
                        _cell('Status', header: true),
                      ],
                    ),
                    for (final s in students)
                      TableRow(
                        children: [
                          _cell((s is Map ? s['name'] : '').toString()),
                          _cell(sectionLabel),
                          _cellStatus(s is Map ? s['status']?.toString() : ''),
                        ],
                      ),
                  ],
                ),
              ),
              if (status == AttendanceReportService.rejected && reason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rejected by Admin',
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                      const SizedBox(height: 6),
                      Text('Reason: "$reason"',
                          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF374151))),
                    ],
                  ),
                ),
              ],
              if (status == AttendanceReportService.pending) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmApprove(reportId);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('Approve', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _rejectDialog(reportId);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('Reject', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: header ? FontWeight.w700 : FontWeight.w500,
              color: header ? const Color(0xFF6B7280) : const Color(0xFF111827))),
    );
  }

  Widget _cellStatus(String? status) {
    final s = AttendanceReportService.norm(status);
    final color = s == 'present'
        ? const Color(0xFF22C55E)
        : s == 'late'
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    final label = s == 'present' ? 'Present' : s == 'late' ? 'Late' : 'Absent';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF6B7280))),
          Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _confirmApprove(int reportId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Approve Attendance Report?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Are you sure you want to approve this attendance report?',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final adminId = await _adminId();
              try {
                await AttendanceReportService.approveReport(_client, reportId, adminId);
                await _fetch();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Report approved.', style: GoogleFonts.poppins()),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not approve. Please try again.', style: GoogleFonts.poppins()),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Approve Report', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _rejectDialog(int reportId) {
    final reasonController = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Reject Attendance Report',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please provide a reason for rejecting this attendance report.',
                  style: GoogleFonts.poppins(fontSize: 13.5, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Reason for rejection',
                  hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Reason is required');
                  return;
                }
                Navigator.pop(ctx);
                final adminId = await _adminId();
                try {
                  await AttendanceReportService.rejectReport(
                      _client, reportId, adminId, reasonController.text.trim());
                  await _fetch();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Report rejected.', style: GoogleFonts.poppins()),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not reject. Please try again.', style: GoogleFonts.poppins()),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } finally {
                  reasonController.dispose();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Reject Report', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
