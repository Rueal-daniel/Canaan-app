import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/recitation_service.dart';
import '../../services/session_service.dart';
import '../../services/auth_service.dart';

/// Student Dashboard → Quick Links → Memory Verse.
///
/// Shows ONLY the logged-in student's own section verses,
/// newest first. View-only: no create, edit or delete here.
class StudentMemoryVerse extends StatefulWidget {
  final String section;
  const StudentMemoryVerse({super.key, required this.section});

  @override
  State<StudentMemoryVerse> createState() => _StudentMemoryVerseState();
}

class _StudentMemoryVerseState extends State<StudentMemoryVerse> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _verses = [];
  bool _isLoading = true;
  // This student's own status per verse: verseId -> status.
  // Absent key = teacher hasn't recorded this verse yet.
  Map<int, String> _myStatuses = {};

  @override
  void initState() {
    super.initState();
    _fetchVerses();
  }

  String _prettySection(String? section) {
    final s = (section ?? '').trim();
    if (s == 'sub-junior') return 'Sub Junior';
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _referenceOf(Map<String, dynamic> v) {
    final ref = (v['verse_reference'] ?? '').toString().trim();
    if (ref.isNotEmpty) return ref;
    final title = (v['title'] ?? '').toString().trim();
    if (title.isNotEmpty && title.toLowerCase() != 'memory verse') return title;
    final content = (v['content'] ?? '').toString().trim();
    if (content.isEmpty) return 'Memory Verse';
    final firstLine = content.split('\n').first.trim();
    return firstLine.length > 60 ? 'Memory Verse' : firstLine;
  }

  Future<void> _fetchVerses() async {
    setState(() => _isLoading = true);
    try {
      final rows = await _client
          .from('memory_verses')
          .select('*')
          .eq('section', widget.section)
          .order('created_at', ascending: false);
      final verses = List<Map<String, dynamic>>.from(rows);
      final myStatuses = await _fetchMyStatuses();
      if (mounted) {
        setState(() {
          _verses = verses;
          _myStatuses = myStatuses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Loads ONLY this student's recitation statuses (own session id),
  /// keyed by verse id so each verse shows its own result.
  Future<Map<int, String>> _fetchMyStatuses() async {
    try {
      final session = await SessionService.getSession();
      if (session == null || session.role != UserRole.student.name) {
        return {};
      }
      final table = RecitationService.sectionTable(widget.section);
      if (table == null) return {};
      final rows = await _client
          .from(table)
          .select('verse_id, status')
          .eq('student_id', session.userId)
          .order('date', ascending: false)
          .order('id', ascending: false);
      final map = <int, String>{};
      for (final r in (rows as List)) {
        final verseId = (r['verse_id'] as num?)?.toInt();
        final st = RecitationService.norm(r['status']?.toString());
        // Latest record wins when several exist for one verse.
        if (verseId != null &&
            RecitationService.isKnownRecitation(st) &&
            !map.containsKey(verseId)) {
          map[verseId] = st;
        }
      }
      return map;
    } catch (_) {
      return {};
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
        title: Text('Memory Verse',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : RefreshIndicator(
              onRefresh: _fetchVerses,
              color: const Color(0xFF1565C0),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _sectionBanner(),
                    const SizedBox(height: 16),
                    if (_verses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 48),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          children: [
                            Icon(Icons.menu_book_outlined,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No memory verses for your section yet.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _verses.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 14),
                        itemBuilder: (_, i) =>
                            _verseCard(_verses[i], i == 0),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Memory Verses',
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text('Section: ${_prettySection(widget.section)}',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${_verses.length}',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _verseCard(Map<String, dynamic> v, bool isLatest) {
    final verseId = (v['id'] as num?)?.toInt();
    final myStatus = verseId == null ? null : _myStatuses[verseId];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_stories_rounded,
                  size: 18, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              Text('MEMORY VERSE',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: const Color(0xFF6366F1))),
              if (isLatest) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('NEW',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF15803D))),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(_referenceOf(v),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 12),
          Text('"${(v['content'] ?? '').toString().trim()}"',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                    'Section: ${_prettySection(v['section']?.toString())}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500)),
              ),
              Text('  •  ',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade400)),
              Flexible(
                child: Text(
                    'Added by: ${(v['teacher_name'] ?? '').toString()}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _recitationStatusCard(myStatus),
        ],
      ),
    );
  }

  /// This student's own status for one verse (null = not recorded yet).
  Widget _recitationStatusCard(String? status) {
    late Color color;
    late IconData icon;
    late String message;
    late String sub;
    late String label;
    switch (status) {
      case RecitationService.recited:
        color = const Color(0xFF22C55E);
        icon = Icons.celebration_rounded;
        message = 'You have recited this memory verse!';
        sub = 'Great job! You successfully recited the memory verse.';
        label = 'Recited';
        break;
      case RecitationService.halfRecited:
        color = const Color(0xFFF59E0B);
        icon = Icons.menu_book_rounded;
        message = 'You have half recited this memory verse.';
        sub = 'Keep practicing and try to complete the whole verse!';
        label = 'Half Recited';
        break;
      case RecitationService.notRecited:
        color = const Color(0xFFEF4444);
        icon = Icons.fitness_center_rounded;
        message = "You haven't recited this memory verse yet.";
        sub = 'Keep practicing and try again next time!';
        label = 'Not Recited';
        break;
      default:
        color = const Color(0xFF6366F1);
        icon = Icons.hourglass_top_rounded;
        message = 'Recitation Pending';
        sub = "Your teacher hasn't recorded your recitation yet.";
        label = 'Pending';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(sub,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(20)),
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
