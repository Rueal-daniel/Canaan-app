import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/recitation_service.dart';
import '../../services/session_service.dart';
import '../../services/auth_service.dart';

/// Admin → Students → Memory Verse Reports.
///
/// Reviews recitation reports sent by teachers: card-style detail,
/// approve, or reject with a mandatory reason.
class MemoryVerseReports extends StatefulWidget {
  const MemoryVerseReports({super.key});

  @override
  State<MemoryVerseReports> createState() => _MemoryVerseReportsState();
}

class _MemoryVerseReportsState extends State<MemoryVerseReports> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  String _filter = 'all'; // all|pending|approved|rejected

  int _count(String status) => _reports
      .where((r) =>
          RecitationService.norm(r['status']?.toString()) == status)
      .length;

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _reports;
    return _reports
        .where((r) =>
            RecitationService.norm(r['status']?.toString()) == _filter)
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
      final rows = await _client
          .from('memory_verse_reports')
          .select('*')
          .order('date', ascending: false);
      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _adminId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        return session.userId;
      }
    } catch (_) {}
    return '';
  }

  String _prettySection(String? section) {
    final s = (section ?? '').trim();
    if (s == 'sub-junior') return 'Sub Junior';
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
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

  int _num(Map<String, dynamic> r, String key) =>
      (r[key] as num?)?.toInt() ?? 0;

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
        title: Text('Memory Verse Reports',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)))
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
      _miniStat(
          'Pending Reports',
          '${_count(RecitationService.pending)}',
          Icons.hourglass_top_rounded,
          const Color(0xFFF59E0B)),
      _miniStat(
          'Approved Reports',
          '${_count(RecitationService.approved)}',
          Icons.verified_rounded,
          const Color(0xFF22C55E)),
      _miniStat(
          'Rejected Reports',
          '${_count(RecitationService.rejected)}',
          Icons.cancel_rounded,
          const Color(0xFFEF4444)),
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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                      height: 1)),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF6B7280))),
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
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
            selectedColor: const Color(0xFF1565C0),
            labelStyle: GoogleFonts.poppins(
                color: _filter == value
                    ? Colors.white
                    : const Color(0xFF374151)),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
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
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.folder_off_rounded,
                size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No reports found.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500)),
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
        final status = RecitationService.norm(r['status']?.toString());
        final color = RecitationService.color(status);
        final ref = (r['verse_title'] ?? '').toString().trim();
        return Container(
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        ref.isEmpty ? 'Memory Verse' : ref,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                  ),
                  _statusPill(status, color),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  '${RecitationService.prettyDate(r['date']?.toString())} • ${r['teacher_name'] ?? ''} • ${_prettySection(r['section']?.toString())}',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _countChip('Recited ${_num(r, 'recited_count')}',
                      const Color(0xFF22C55E)),
                  _countChip(
                      'Half ${_num(r, 'half_recited_count')}',
                      const Color(0xFFF59E0B)),
                  _countChip('Not ${_num(r, 'not_recited_count')}',
                      const Color(0xFFEF4444)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('View',
                      style:
                          GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _statusPill(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(RecitationService.label(status),
          style: GoogleFonts.poppins(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  void _viewReport(Map<String, dynamic> r) {
    final reportId = (r['id'] as num).toInt();
    final status = RecitationService.norm(r['status']?.toString());
    final color = RecitationService.color(status);
    final students =
        r['student_details'] is List ? List.from(r['student_details']) : [];
    final reason = r['rejection_reason']?.toString() ?? '';
    final ref = (r['verse_title'] ?? '').toString().trim();
    final content = (r['verse_content'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
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
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('Memory Verse Recitation Report',
                        style: GoogleFonts.poppins(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827))),
                  ),
                  _statusPill(status, color),
                ],
              ),
              const SizedBox(height: 4),
              Text(RecitationService.prettyDate(r['date']?.toString()),
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, color: const Color(0xFF6B7280))),
              const SizedBox(height: 16),
              _infoBoxes(r, status, color),
              const SizedBox(height: 16),
              _recitationSummary(r),
              const SizedBox(height: 16),
              _verseBox(ref.isEmpty ? 'Memory Verse' : ref, content),
              const SizedBox(height: 16),
              Text('Students (${students.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _studentCards(students),
              if (status == RecitationService.rejected &&
                  reason.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFFEF4444)
                            .withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rejected by Admin',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFEF4444))),
                      const SizedBox(height: 6),
                      Text('Reason: "$reason"',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: const Color(0xFF374151))),
                    ],
                  ),
                ),
              ],
              if (status == RecitationService.pending) ...[
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
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('Approve Report',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700)),
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
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text('Reject Report',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700)),
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

  Widget _infoBoxes(
      Map<String, dynamic> r, String status, Color color) {
    final boxes = [
      ('Date',
          RecitationService.prettyDate(r['date']?.toString()).split(',').first),
      ('Section', _prettySection(r['section']?.toString())),
      ('Teacher', (r['teacher_name'] ?? '').toString()),
      ('Status', RecitationService.label(status)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 74,
      ),
      itemCount: boxes.length,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(boxes[i].$1,
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: const Color(0xFF6B7280))),
            const SizedBox(height: 2),
            Text(boxes[i].$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _recitationSummary(Map<String, dynamic> r) {
    final cards = [
      ('${_num(r, 'recited_count')}', 'Recited', const Color(0xFF22C55E),
          Icons.check_circle_rounded),
      ('${_num(r, 'half_recited_count')}', 'Half Recited',
          const Color(0xFFF59E0B), Icons.warning_amber_rounded),
      ('${_num(r, 'not_recited_count')}', 'Not Recited',
          const Color(0xFFEF4444), Icons.cancel_rounded),
    ];
    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: [
                      BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(cards[i].$4, color: cards[i].$3, size: 22),
                      const SizedBox(height: 6),
                      Text(cards[i].$1,
                          style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                      const SizedBox(height: 4),
                      Text(cards[i].$2,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF6B7280))),
                    ],
                  ),
                ),
              ),
              if (i < cards.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text('Total Students: ${_num(r, 'total_students')}',
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827))),
      ],
    );
  }

  Widget _verseBox(String reference, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text('MEMORY VERSE',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Text(reference,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text(content.isEmpty ? '' : '"$content"',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.92))),
        ],
      ),
    );
  }

  Widget _studentCards(List students) {
    if (students.isEmpty) {
      return Text('No student details in this report.',
          style: GoogleFonts.poppins(
              fontSize: 13, color: Colors.grey.shade500));
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: students.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = students[i] is Map ? students[i] : {};
        final name = (s['name'] ?? '').toString();
        final st = RecitationService.norm(s['status']?.toString());
        final color = RecitationService.color(st);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(_initials(name),
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
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
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(RecitationService.label(st),
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmApprove(int reportId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Approve Memory Verse Report?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
            'Are you sure you want to approve this memory verse recitation report?',
            style:
                GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final adminId = await _adminId();
              try {
                await RecitationService.approveReport(
                    _client, reportId, adminId);
                await _fetch();
                _snack('Report approved.', Colors.green);
              } catch (e) {
                _snack('Could not approve. Please try again.', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Approve Report',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Reject Memory Verse Report',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Please provide the reason for rejecting this report.',
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter rejection reason...',
                  hintStyle: GoogleFonts.poppins(
                      color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFEF4444), width: 2)),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600)),
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
                  await RecitationService.rejectReport(_client, reportId,
                      adminId, reasonController.text.trim());
                  await _fetch();
                  _snack('Report rejected.', Colors.red);
                } catch (e) {
                  _snack('Could not reject. Please try again.', Colors.red);
                } finally {
                  reasonController.dispose();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Reject Report',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
