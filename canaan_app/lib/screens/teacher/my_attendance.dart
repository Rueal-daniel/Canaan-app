import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Teacher Dashboard → Quick Links → My Attendance.
///
/// View-only: the logged-in teacher sees ONLY their own records.
/// No marking, editing, deleting — and no Late anywhere on this page.
class TeacherMyAttendance extends StatefulWidget {
  final String teacherId;
  final String section;
  const TeacherMyAttendance({
    super.key,
    required this.teacherId,
    required this.section,
  });

  @override
  State<TeacherMyAttendance> createState() => _TeacherMyAttendanceState();
}

class _TeacherMyAttendanceState extends State<TeacherMyAttendance> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];

  int get _total => _records.length;
  int get _present =>
      _records.where((r) => _norm(r['status']) == 'present').length;
  int get _absent => _total - _present;
  double get _percentage => _total == 0 ? 0 : (_present / _total) * 100;

  String _norm(dynamic v) => (v ?? '').toString().trim().toLowerCase();

  String _prettySection(String section) {
    if (section == 'sub-junior') return 'Sub Junior';
    if (section.isEmpty) return section;
    return section[0].toUpperCase() + section.substring(1);
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
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      // Own records only: filtered by this teacher's id, newest first.
      final rows = await _client
          .from('teacher_attendance')
          .select('*')
          .eq('teacher_id', widget.teacherId)
          .order('date', ascending: false);
      if (mounted) {
        setState(() {
          _records = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
        title: Text('My Attendance',
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
                    Text('View your attendance history and attendance summary.',
                        style: GoogleFonts.poppins(
                            fontSize: 13.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 16),
                    _summaryGrid(),
                    const SizedBox(height: 20),
                    Text('Attendance History',
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

  Widget _summaryGrid() {
    final cards = [
      _miniStat('Total Attendance Days', '$_total', Icons.calendar_month_rounded,
          const Color(0xFF6366F1)),
      _miniStat('Present', '$_present', Icons.check_circle_rounded,
          const Color(0xFF22C55E)),
      _miniStat('Absent', '$_absent', Icons.cancel_rounded,
          const Color(0xFFEF4444)),
      _miniStat('Attendance Percentage', '${_percentage.toStringAsFixed(0)}%',
          Icons.pie_chart_rounded, const Color(0xFF1565C0)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 118,
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
                    textAlign: TextAlign.end,
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

  Widget _historyList() {
    if (_records.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 44),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded,
                size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No attendance records yet.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _records[i];
        final present = _norm(r['status']) == 'present';
        final color = present
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444);
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
                        _prettyDate((r['date'] ?? '').toString()),
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
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
                        Text(present ? 'Present' : 'Absent',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Section: ${_prettySection(widget.section)}',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade600)),
            ],
          ),
        );
      },
    );
  }
}
