import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../services/leaderboard_service.dart';
import '../services/linked_student_service.dart';
import '../services/session_service.dart';
import '../widgets/animations.dart';

/// Sidebar → Leaderboard (Admin, Teacher and Student).
///
/// Two live boards — Attendance and Memory Verse Recitation — calculated
/// from the REAL Supabase records (no leaderboard tables, no manual
/// percentages, no ranking notifications):
///   Attendance % ← `attendance_reports` (same matching as the Student
///                  Dashboard; late counts as attended).
///   Memory %     ← per-section recitation tables, Recited=100 /
///                  Half=50 / Not=0, averaged per student.
///
/// SCOPE (enforced in [LeaderboardService], never by a client value):
///   Admin   → All Students / Sub Junior / Junior / Senior selector.
///   Teacher → own assigned section only (resolved from verified login
///             id — no selector, nothing to tamper with).
///   Student → own section only; the current student row is highlighted.
///
/// Only leaderboard-safe fields are ever displayed (photo, name, section,
/// rank, %) — never username, password, email, phone or parent data.
class LeaderboardPage extends StatefulWidget {
  /// 'admin' | 'teacher' | 'student'
  final String role;

  /// Verified row id: admin id, teacher login id, or ACTIVE student id
  /// (linked family aware). Drives scope + highlight, never credentials.
  final String userId;

  const LeaderboardPage({
    super.key,
    required this.role,
    this.userId = '',
  });

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  bool _memory = false; // false = Attendance, true = Memory Verse
  String _adminSection = ''; // '' = All (admin only)
  String _scopeSection = '';
  bool _scopeLoading = true;

  /// Resolved identity driving scope + highlight (verified row id).
  String _identityId = '';

  List<LeaderboardEntry> _entries = [];
  bool _isLoading = true;
  String? _loadError;
  final List<StreamSubscription> _realtimeSubs = [];

  String get _role => widget.role.trim().toLowerCase();
  bool get _isAdmin => _role == 'admin';
  bool get _isTeacher => _role == 'teacher';

  List<Color> get _gradient {
    if (_isTeacher) {
      return const [Color(0xFF2E1065), Color(0xFF6D28D9)];
    }
    if (_role == 'student') {
      return const [Color(0xFF063B2E), Color(0xFF0E9F6E)];
    }
    return const [Color(0xFF0B2A5B), Color(0xFF1565C0)];
  }

  /// Section actually queried: admin picker, otherwise the verified scope.
  String get _querySection => _isAdmin ? _adminSection : _scopeSection;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _init() async {
    await _resolveScope();
    await _load();
    _watchRealtime();
  }

  /// Resolves the fixed scope for teacher/student from a VERIFIED id.
  ///
  /// Primary source is the sidebar-passed row id; fallback is the secure
  /// login/active identity (session / linked-active — never a typed or
  /// client-picked section), so the scope stays tamper-proof even when
  /// the dashboard could not resolve its display id.
  Future<void> _resolveScope() async {
    if (_isAdmin) {
      if (mounted) {
        setState(() {
          _identityId = widget.userId.trim();
          _scopeLoading = false;
        });
      }
      return;
    }
    try {
      var id = widget.userId.trim();
      if (id.isEmpty) {
        if (_isTeacher) {
          try {
            final session = await SessionService.getSession();
            if (session != null &&
                session.role == UserRole.teacher.name) {
              id = session.userId.trim();
            }
          } catch (_) {}
        } else {
          try {
            id = await LinkedStudentService.effectiveStudentId();
          } catch (_) {}
        }
      }
      final section = id.isEmpty
          ? ''
          : _isTeacher
              ? await LeaderboardService.teacherSectionOf(id)
              : await LeaderboardService.studentSectionOf(id);
      if (!mounted) return;
      setState(() {
        _identityId = id;
        _scopeSection = section;
        _scopeLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _scopeLoading = false);
    }
  }

  void _watchRealtime() {
    if (_realtimeSubs.isNotEmpty) return;
    final client = Supabase.instance.client;
    for (final t in [
      'attendance_reports',
      'students',
      'recitation_sub_junior',
      'recitation_junior',
      'recitation_senior',
      'memory_verses',
    ]) {
      try {
        _realtimeSubs.add(client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) _load(silent: true);
            }));
      } catch (_) {}
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final entries = await LeaderboardService.compute(
        section: _querySection,
        memory: _memory,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load leaderboard. ($e)';
        });
      }
    }
  }

  String get _scopeLabel {
    if (_isAdmin) {
      return _adminSection.isEmpty
          ? 'All Students'
          : LeaderboardService.prettySection(_adminSection);
    }
    final s = LeaderboardService.prettySection(_scopeSection);
    return s.isEmpty ? 'My Section' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [..._gradient, _gradient.last.withValues(alpha: 0.75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Leaderboard',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LangBuilder(
        builder: (_) => RefreshIndicator(
          onRefresh: () async {
            await _resolveScope();
            await _load();
          },
          color: _gradient.last,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerCard(),
                const SizedBox(height: 14),
                _metricToggle(),
                if (_isAdmin) ...[
                  const SizedBox(height: 12),
                  _sectionSelector(),
                ],
                const SizedBox(height: 16),
                if (!_isAdmin && !_scopeLoading && _scopeSection.isNotEmpty)
                  _scopeChip(),
                if (!_isAdmin && !_scopeLoading && _scopeSection.isNotEmpty)
                  const SizedBox(height: 12),
                _body(),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _gradient.last.withValues(alpha: 0.3),
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
            child: const Icon(Icons.leaderboard_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leaderboard',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      _memory
                          ? 'Memory Verse Recitation · $_scopeLabel'
                          : 'Attendance · $_scopeLabel',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _metricToggle() {
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(children: [
          Expanded(child: _metricButton(false, Icons.calendar_month_rounded, 'Attendance')),
          Expanded(child: _metricButton(true, Icons.menu_book_rounded, 'Memory Verse')),
        ]),
      ),
    );
  }

  Widget _metricButton(bool value, IconData icon, String label) {
    final selected = _memory == value;
    return GestureDetector(
      onTap: () {
        if (_memory == value) return;
        setState(() => _memory = value);
        _load();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: _gradient) : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _gradient.last.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 19,
              color: selected ? Colors.white : const Color(0xFF64748B)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF64748B))),
          ),
        ]),
      ),
    );
  }

  /// Admin only: All / Sub Junior / Junior / Senior.
  Widget _sectionSelector() {
    const options = [
      ('', 'All Students'),
      ('sub-junior', 'Sub Junior'),
      ('junior', 'Junior'),
      ('senior', 'Senior'),
    ];
    return FadeInSlide(
      index: 2,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (value, label) in options)
            GestureDetector(
              onTap: () {
                if (_adminSection == value) return;
                setState(() => _adminSection = value);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: _adminSection == value
                      ? LinearGradient(colors: _gradient)
                      : null,
                  color: _adminSection == value
                      ? null
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _adminSection == value
                          ? Colors.transparent
                          : const Color(0xFFE2E8F0)),
                  boxShadow: _adminSection == value
                      ? [
                          BoxShadow(
                            color:
                                _gradient.last.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _adminSection == value
                            ? Colors.white
                            : const Color(0xFF475569))),
              ),
            ),
        ],
      ),
    );
  }

  /// Teacher/student scope indicator (informational — no selector).
  Widget _scopeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _gradient.last.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: _gradient.last.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_rounded, size: 15, color: _gradient.last),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
              _role == 'student'
                  ? 'Your section: $_scopeLabel'
                  : 'Section: $_scopeLabel',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _gradient.last)),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_scopeLoading || _isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 50),
        child: Center(
            child: CircularProgressIndicator(color: _gradient.last)),
      );
    }
    if (_loadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gradient.last,
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
    if (!_isAdmin && _scopeSection.isEmpty) {
      return _emptyCard('No section assigned yet.\nPlease contact the Admin.');
    }
    if (_entries.isEmpty) {
      return _emptyCard(_memory
          ? 'No recitation records yet.\nRankings appear once teachers mark recitations.'
          : 'No attendance records yet.\nRankings appear once teachers mark attendance.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _rowCard(_entries[i], i),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('🏆', style: TextStyle(fontSize: 44)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151))),
      ]),
    );
  }

  Widget _rowCard(LeaderboardEntry e, int index) {
    final isMe = !_isAdmin &&
        _role == 'student' &&
        e.studentId.trim().isNotEmpty &&
        _identityId.isNotEmpty &&
        e.studentId.trim() == _identityId.trim();
    final ranked = e.percent != null;
    final sectionLabel =
        LeaderboardService.prettySection(e.section);

    Color accent;
    String medal = '';
    if (!ranked) {
      accent = const Color(0xFF94A3B8);
    } else if (e.rank == 1) {
      accent = const Color(0xFFEAB308);
      medal = '🥇';
    } else if (e.rank == 2) {
      accent = const Color(0xFF94A3B8);
      medal = '🥈';
    } else if (e.rank == 3) {
      accent = const Color(0xFFB45309);
      medal = '🥉';
    } else {
      accent = _gradient.last;
    }

    return FadeInSlide(
      index: index % 6,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: isMe
              ? LinearGradient(colors: [
                  _gradient.first.withValues(alpha: 0.12),
                  _gradient.last.withValues(alpha: 0.08),
                ])
              : null,
          color: isMe ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isMe ? _gradient.last : const Color(0xFFF1F5F9),
              width: isMe ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          // Rank / medal.
          SizedBox(
            width: 44,
            child: Center(
              child: ranked
                  ? (medal.isNotEmpty
                      ? Text(medal, style: const TextStyle(fontSize: 26))
                      : Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('${e.rank}',
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: accent)),
                          ),
                        ))
                  : Text('—',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade300)),
            ),
          ),
          // Photo (initials fallback).
          CircleAvatar(
            radius: 22,
            backgroundColor: accent.withValues(alpha: 0.12),
            backgroundImage: e.photoUrl.isNotEmpty
                ? NetworkImage(e.photoUrl)
                : null,
            onBackgroundImageError:
                e.photoUrl.isNotEmpty ? (_, _) {} : null,
            child: e.photoUrl.isEmpty
                ? Text(
                    LeaderboardService.initialsOf(e.fullName),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Name + section + detail line.
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                          isMe
                              ? '⭐ ${e.fullName}'
                              : e.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827))),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _gradient.last,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('YOU',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                      ranked
                          ? '$sectionLabel  •  ${_detailLine(e)}'
                          : '$sectionLabel  •  ${_memory ? 'No recitation data' : 'No attendance data'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: Colors.grey.shade500)),
                ]),
          ),
          const SizedBox(width: 8),
          // Percentage badge.
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: ranked
                  ? accent.withValues(alpha: 0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
                ranked
                    ? LeaderboardService.pctLabel(e.percent!)
                    : '—',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ranked
                        ? accent
                        : Colors.grey.shade400)),
          ),
        ]),
      ),
    );
  }

  /// Attendance: `18/20 present` · Memory: `5 recited · 2 half`.
  String _detailLine(LeaderboardEntry e) {
    if (_memory) {
      final parts = <String>['${e.present} recited'];
      if (e.halfCount > 0) parts.add('${e.halfCount} half');
      if (e.notCount > 0) parts.add('${e.notCount} not');
      parts.add('${e.total} verses');
      return parts.join(' · ');
    }
    return '${e.present}/${e.total} present';
  }
}
