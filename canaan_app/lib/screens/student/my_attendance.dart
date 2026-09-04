import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single attendance entry for the logged-in student.
class _AttendanceEntry {
  final String date;
  final String status; // present | absent | late
  const _AttendanceEntry({required this.date, required this.status});
}

/// "My Attendance" — shows ONLY the logged-in student's own records.
///
/// Data source: `attendance_reports` table. Each report row holds one
/// session (`date`) plus a `students` JSON array like:
/// `[{"name": "Sajina Shrestha", "status": "present"}, ...]`
/// Names are matched case-insensitively after trimming, because some
/// stored names contain trailing spaces.
class MyAttendance extends StatefulWidget {
  final String fullName;
  const MyAttendance({super.key, required this.fullName});

  @override
  State<MyAttendance> createState() => _MyAttendanceState();
}

class _MyAttendanceState extends State<MyAttendance> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;
  List<_AttendanceEntry> _records = [];

  int get _present => _records.where((e) => e.status == 'present').length;
  int get _absent => _records.where((e) => e.status == 'absent').length;
  int get _late => _records.where((e) => e.status == 'late').length;
  int get _total => _records.length;

  /// Late counts as attended.
  double get _percentage =>
      _total == 0 ? 0 : ((_present + _late) / _total) * 100;

  String _norm(String? v) => (v ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _client
          .from('attendance_reports')
          .select('date, students')
          .order('date', ascending: false);

      final me = _norm(widget.fullName);
      final found = <_AttendanceEntry>[];

      for (final row in (rows as List)) {
        final date = (row['date'] ?? '').toString();
        final students = row['students'];
        if (students is! List) continue;
        for (final s in students) {
          if (s is! Map) continue;
          if (_norm(s['name']?.toString()) != me) continue;
          final raw = _norm(s['status']?.toString());
          final status =
              raw == 'present' || raw == 'late' ? raw : 'absent';
          found.add(_AttendanceEntry(date: date, status: status));
          break; // one entry per report row
        }
      }

      // Latest date first.
      found.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _records = found;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load attendance. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  String _prettyDate(String raw) {
    try {
      final d = DateTime.parse(raw);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
        title: Text(
          'My Attendance',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetch,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Retry', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                )
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
                        const SizedBox(height: 12),
                        _summaryCard(),
                        const SizedBox(height: 12),
                        _chartCard(),
                        const SizedBox(height: 20),
                        Text('Attendance History',
                            style: GoogleFonts.poppins(
                                fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
                        const SizedBox(height: 12),
                        _historyList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// ✅ Present / ❌ Absent / 🕐 Late / 📊 % mini cards.
  Widget _summaryGrid() {
    final cards = [
      _miniStat('Present', '$_present', Icons.check_circle_rounded, const Color(0xFF22C55E)),
      _miniStat('Absent', '$_absent', Icons.cancel_rounded, const Color(0xFFEF4444)),
      _miniStat('Late', '$_late', Icons.schedule_rounded, const Color(0xFFF59E0B)),
      _miniStat('Attendance', '${_percentage.toStringAsFixed(0)}%',
          Icons.pie_chart_rounded, const Color(0xFF6366F1)),
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6)),
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
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
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

  /// Total / Present / Absent / Late / % breakdown card.
  Widget _summaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        children: [
          Text('Attendance Summary',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          const SizedBox(height: 16),
          _summaryRow('Total days', '$_total', const Color(0xFF111827)),
          _summaryRow('Present days', '$_present', const Color(0xFF22C55E)),
          _summaryRow('Absent days', '$_absent', const Color(0xFFEF4444)),
          _summaryRow('Late days', '$_late', const Color(0xFFF59E0B)),
          const Divider(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Overall attendance',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_percentage.toStringAsFixed(1)}%',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF6366F1))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _total == 0 ? 0 : _percentage / 100,
              minHeight: 10,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF6B7280))),
          Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: valueColor)),
        ],
      ),
    );
  }

  /// Dynamic bar chart (no extra packages).
  Widget _chartCard() {
    final maxCount = [_present, _absent, _late].fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        children: [
          Text('Attendance Chart',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          const SizedBox(height: 16),
          _barRow('Present', _present, maxCount, const Color(0xFF22C55E)),
          const SizedBox(height: 12),
          _barRow('Absent', _absent, maxCount, const Color(0xFFEF4444)),
          const SizedBox(height: 12),
          _barRow('Late', _late, maxCount, const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _barRow(String label, int count, int maxCount, Color color) {
    final fraction = maxCount == 0 ? 0.0 : count / maxCount;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF374151))),
        ),
        Expanded(
          child: Container(
            height: 14,
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction == 0 ? 0.02 : fraction,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.75)]),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text('$count',
              textAlign: TextAlign.end,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
        ),
      ],
    );
  }

  Widget _historyList() {
    if (_records.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No attendance records yet.',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = _records[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 20, color: Colors.grey.shade400),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_prettyDate(r.date),
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF111827))),
              ),
              _statusPill(r.status),
            ],
          ),
        );
      },
    );
  }

  Widget _statusPill(String status) {
    late Color color;
    late IconData icon;
    late String label;
    switch (status) {
      case 'present':
        color = const Color(0xFF22C55E);
        icon = Icons.check_circle_rounded;
        label = 'Present';
        break;
      case 'late':
        color = const Color(0xFFF59E0B);
        icon = Icons.schedule_rounded;
        label = 'Late';
        break;
      default:
        color = const Color(0xFFEF4444);
        icon = Icons.cancel_rounded;
        label = 'Absent';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
