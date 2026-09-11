import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/language_service.dart';
import '../../services/progress_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/star_rating.dart';
import 'evaluate_student.dart';

/// Admin → Students → Student Progress.
///
/// Section tabs + search + modern student cards (no tables). Each card
/// shows live Attendance / Memory Verse percentages plus the Admin's
/// Participation / Discipline evaluation and overall stars.
class AdminStudentProgressPage extends StatefulWidget {
  final String adminName;
  const AdminStudentProgressPage({super.key, this.adminName = ''});

  @override
  State<AdminStudentProgressPage> createState() =>
      _AdminStudentProgressPageState();
}

class _AdminStudentProgressPageState extends State<AdminStudentProgressPage>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;
  final _searchController = TextEditingController();

  static const _sections = ['sub-junior', 'junior', 'senior'];

  List<StudentProgressBundle> _items = [];
  String _search = '';
  bool _isLoading = true;
  String? _loadError;
  final List<StreamSubscription> _subs = [];

  String get _section => _sections[_tabController.index];

  String _prettySection(String s) {
    if (s == 'sub-junior') return tr('sec_sub');
    if (s == 'junior') return tr('sec_jun');
    if (s == 'senior') return tr('sec_sen');
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
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
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) _fetch();
    });
    _fetch();
    _watch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
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
              if (mounted) _fetch(silent: true);
            }));
      } catch (_) {}
    }

    listen('students');
    listen('attendance_reports');
    listen(ProgressService.evalTable);
    listen('recitation_sub_junior');
    listen('recitation_junior');
    listen('recitation_senior');
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final items = await ProgressService.forSection(_section);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load progress. ($e)';
        });
      }
    }
  }

  List<StudentProgressBundle> get _visible {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where((b) => b.fullName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _openEvaluate(StudentProgressBundle b) async {
    final saved = await Navigator.push(
      context,
      SlidePageRoute(
        page: EvaluateStudentPage(
          studentId: b.studentId,
          fullName: b.fullName,
          section: b.section,
          adminName: widget.adminName,
        ),
      ),
    );
    if (saved == true && mounted) _fetch(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return LangBuilder(
      builder: (_) => Scaffold(
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
        title: Text(tr('nav_progress'),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: tr('sec_sub')),
            Tab(text: tr('sec_jun')),
            Tab(text: tr('sec_sen')),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: '${tr('c_search_student')} 🔍',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF1565C0), width: 2)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : _loadError != null
                    ? _errorState()
                    : RefreshIndicator(
                        color: const Color(0xFF1565C0),
                        onRefresh: () => _fetch(),
                        child: _visible.isEmpty
                            ? _emptyState()
                            : ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    20, 8, 20, 24),
                                itemCount: _visible.length,
                                itemBuilder: (_, i) =>
                                    _studentCard(_visible[i]),
                              ),
                      ),
          ),
        ],
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
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(_loadError ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetch(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(tr('c_retry'),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(Icons.group_off_rounded,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                _search.trim().isEmpty
                    ? trp('pg_no_students',
                        {'s': _prettySection(_section)})
                    : trp('pg_no_match', {'q': _search.trim()}),
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _studentCard(StudentProgressBundle b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0xFF1565C0),
                    Color(0xFF42A5F5)
                  ]),
                  shape: BoxShape.circle,
                ),
                child: Text(_initials(b.fullName),
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.fullName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text(_prettySection(b.section),
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
              StarRating(stars: b.stars, size: 17),
            ],
          ),
          const SizedBox(height: 14),
          _miniRow(tr('pg_attendance'),
              ProgressService.pctLabel(b.attendance.percent),
              const Color(0xFF22C55E)),
          const SizedBox(height: 8),
          _miniRow(tr('nav_memory_verse'),
              ProgressService.pctLabel(b.memory.percent),
              const Color(0xFF6366F1)),
          const SizedBox(height: 8),
          _miniRow(tr('pg_participation'),
              b.evaluation == null
                  ? '—'
                  : '${b.participation}%',
              const Color(0xFFFF9F0A)),
          const SizedBox(height: 8),
          _miniRow(tr('pg_discipline'),
              b.evaluation == null ? '—' : '${b.discipline}%',
              const Color(0xFF0E9F6E)),
          const SizedBox(height: 8),
          _miniRow(tr('pg_overall_rating'),
              b.stars == 0
                  ? tr('pg_not_rated')
                  : '${b.stars}.0 / 5 · ${ProgressService.starLabel(b.stars)}',
              const Color(0xFFF59E0B)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _openEvaluate(b),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(tr('pg_evaluate'),
                  style: GoogleFonts.poppins(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniRow(String label, String value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF475569))),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ),
      ],
    );
  }
}
