import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/language_service.dart';
import '../../services/leave_service.dart';
import '../../services/progress_service.dart';
import '../../services/recitation_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/progress_chart.dart';
import '../../widgets/star_rating.dart';

/// Student Dashboard → Your Progress → View Details.
///
/// Header with the Admin's star rating, four detail cards (Attendance,
/// Memory Verse, Participation, Discipline) and a trailing-months
/// history chart. Attendance + Memory Verse are calculated live from
/// existing records; the rest comes from the Admin's evaluation.
class StudentProgressPage extends StatefulWidget {
  final String fullName;
  final String studentId;
  final String? section;
  const StudentProgressPage({
    super.key,
    required this.fullName,
    required this.studentId,
    this.section,
  });

  @override
  State<StudentProgressPage> createState() => _StudentProgressPageState();
}

class _StudentProgressPageState extends State<StudentProgressPage> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  AttendanceSummary _attendance =
      const AttendanceSummary(total: 0, present: 0, absent: 0, percent: 0);
  MemorySummary _memory = const MemorySummary(
      total: 0, recited: 0, halfRecited: 0, notRecited: 0, percent: 0);
  Map<String, dynamic>? _eval;
  ProgressHistory? _history;
  final List<StreamSubscription> _subs = [];

  String get _section =>
      LeaveService.normalizeSection(widget.section ?? '');

  int get _stars {
    final v = _eval?['overall_star_rating'];
    if (v is num) return v.toInt().clamp(0, 5);
    return (int.tryParse((v ?? '').toString()) ?? 0).clamp(0, 5);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _watch();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _watch() {
    void listen(String table) {
      try {
        _subs.add(_client
            .from(table)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) _load(silent: true);
            }));
      } catch (_) {}
    }

    listen('attendance_reports');
    listen(ProgressService.evalTable);
    final reciteTable = RecitationService.sectionTable(_section);
    if (reciteTable != null) listen(reciteTable);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ProgressService.attendanceFor(widget.fullName),
        ProgressService.memoryFor(widget.studentId, _section),
        ProgressService.evaluationFor(widget.studentId),
        ProgressService.historyFor(
          fullName: widget.fullName,
          studentId: widget.studentId,
          section: _section,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _attendance = results[0] as AttendanceSummary;
        _memory = results[1] as MemorySummary;
        _eval = results[2] as Map<String, dynamic>?;
        _history = results[3] as ProgressHistory;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _ratingLine(String key) {
    final raw = ProgressService.evalString(_eval, key);
    if (raw.isEmpty) return tr('pg_not_rated');
    return ProgressService.ratingLabel(raw);
  }

  @override
  Widget build(BuildContext context) {
    return LangBuilder(
      builder: (_) => Scaffold(
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
        title: Text(tr('nav_your_progress'),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF0E9F6E),
        onRefresh: () => _load(),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF0E9F6E)))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerCard(),
                    const SizedBox(height: 14),
                    _detailCard(
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFF22C55E),
                      title: tr('pg_attendance'),
                      percent: _attendance.percent,
                      lines: [
                        '${_attendance.present} ${tr('pg_present')}',
                        '${_attendance.absent} ${tr('pg_absent')}',
                        '${_attendance.total} ${tr('pg_sessions')}',
                      ],
                    ),
                    const SizedBox(height: 12),
                    _detailCard(
                      icon: Icons.menu_book_rounded,
                      color: const Color(0xFF6366F1),
                      title: tr('nav_memory_verse'),
                      percent: _memory.percent,
                      lines: [
                        tr('pg_recitation_perf'),
                        '${_memory.recited} ${tr('pg_recited')} · ${_memory.halfRecited} ${tr('pg_half')} · ${_memory.notRecited} ${tr('pg_not')}',
                        '${_memory.total} ${tr('pg_verses')}',
                      ],
                    ),
                    const SizedBox(height: 12),
                    _detailCard(
                      icon: Icons.waving_hand_rounded,
                      color: const Color(0xFFFF9F0A),
                      title: tr('pg_participation'),
                      percent: ProgressService.evalInt(
                              _eval, 'participation_percentage')
                          .toDouble(),
                      lines: [
                        _ratingLine('participation_rating'),
                        if (ProgressService.evalString(
                                _eval, 'participation_comment')
                            .isNotEmpty)
                          ProgressService.evalString(
                              _eval, 'participation_comment'),
                      ],
                      evaluated: _eval != null,
                    ),
                    const SizedBox(height: 12),
                    _detailCard(
                      icon: Icons.verified_user_rounded,
                      color: const Color(0xFF0E9F6E),
                      title: tr('pg_discipline'),
                      percent: ProgressService.evalInt(
                              _eval, 'discipline_percentage')
                          .toDouble(),
                      lines: [
                        _ratingLine('discipline_rating'),
                        if (ProgressService.evalString(
                                _eval, 'discipline_comment')
                            .isNotEmpty)
                          ProgressService.evalString(
                              _eval, 'discipline_comment'),
                      ],
                      evaluated: _eval != null,
                    ),
                    const SizedBox(height: 20),
                    Text(tr('pg_history'),
                        style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A))),
                    const SizedBox(height: 4),
                    Text(tr('pg_improving'),
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey.shade500)),
                    const SizedBox(height: 12),
                    _historyCard(),
                    const SizedBox(height: 8),
                  ],
                ),
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
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0E9F6E), Color(0xFF4ADE80)],
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
          child: Column(
            children: [
              Text(tr('pg_overall_rating'),
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 8),
            StarRating(
              stars: _stars,
              size: 34,
              fillColor: Colors.white,
            ),
            const SizedBox(height: 8),
            Text(
              _stars == 0
                  ? tr('pg_not_rated')
                  : ProgressService.starLabel(_stars),
              style: GoogleFonts.poppins(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            if (_stars > 0)
              Text('$_stars.0 / 5',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      ),
    );
  }

  Widget _detailCard({
    required IconData icon,
    required Color color,
    required String title,
    required double percent,
    required List<String> lines,
    bool evaluated = true,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A))),
              ),
              Text(ProgressService.pctLabel(percent),
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 9,
              child: Stack(
                children: [
                  Container(color: color.withValues(alpha: 0.14)),
                  FractionallySizedBox(
                    widthFactor:
                        (percent.clamp(0, 100) / 100).clamp(0.02, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          color,
                          color.withValues(alpha: 0.7)
                        ]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: Text(
                lines[i],
                style: GoogleFonts.poppins(
                  fontSize: i == 0 ? 13.5 : 12.5,
                  fontWeight:
                      i == 0 ? FontWeight.w600 : FontWeight.w400,
                  color: i == 0
                      ? const Color(0xFF0F172A)
                      : Colors.grey.shade500,
                ),
              ),
            ),
          if (!evaluated)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('pg_waiting_eval'),
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade400)),
            ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    final h = _history;
    if (h == null || h.months.isEmpty) return const SizedBox.shrink();
    final labels = [for (final m in h.months) m.label];
    List<double?> col(Map<String, double?> map) =>
        [for (final m in h.months) map[m.key]];
    final part = _eval == null
        ? null
        : ProgressService.evalInt(_eval, 'participation_percentage')
            .toDouble();
    final disc = _eval == null
        ? null
        : ProgressService.evalInt(_eval, 'discipline_percentage')
            .toDouble();
    final series = [
      ChartSeries(
          label: tr('pg_attendance'),
          color: const Color(0xFF22C55E),
          values: col(h.attendance)),
      ChartSeries(
          label: tr('nav_memory_verse'),
          color: const Color(0xFF6366F1),
          values: col(h.memory)),
      if (part != null)
        ChartSeries(
          label: tr('pg_participation'),
          color: const Color(0xFFFF9F0A),
          values: [for (final _ in h.months) part],
        ),
      if (disc != null)
        ChartSeries(
          label: tr('pg_discipline'),
          color: const Color(0xFF0E9F6E),
          values: [for (final _ in h.months) disc],
        ),
    ];
    final hasData = series.any((s) => s.values.any((v) => v != null));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: hasData
          ? ProgressChart(monthLabels: labels, series: series)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(tr('pg_history_empty'),
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade500)),
              ),
            ),
    );
  }
}
