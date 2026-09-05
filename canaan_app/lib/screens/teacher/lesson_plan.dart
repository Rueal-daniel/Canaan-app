import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/lesson_plan_service.dart';
import '../../widgets/animations.dart';
import '../lesson_pdf_viewer.dart';

/// Teacher Dashboard → Quick Links → Lesson Plan.
///
/// Read-only. The teacher automatically receives plans for their own
/// section (matched via the `grade` column) — no section picker.
/// The newest published plan is shown prominently; realtime updates
/// make newly published plans appear without any manual action.
class TeacherLessonPlanPage extends StatefulWidget {
  final String section;
  final String teacherId;
  final String teacherName;
  const TeacherLessonPlanPage({
    super.key,
    required this.section,
    this.teacherId = '',
    this.teacherName = '',
  });

  @override
  State<TeacherLessonPlanPage> createState() => _TeacherLessonPlanPageState();
}

class _TeacherLessonPlanPageState extends State<TeacherLessonPlanPage> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _plans = [];
  // lesson_id -> lesson_plan_files row (one file per plan).
  Map<int, Map<String, dynamic>> _files = {};
  bool _isLoading = true;
  String? _loadError;
  bool _busyPdf = false;
  StreamSubscription? _realtimeSub;

  String get _section =>
      LessonPlanService.normalizeSection(widget.section);
  String get _upcomingSaturdayLabel =>
      LessonPlanService.prettyLessonDate(LessonPlanService.upcomingSaturday());

  @override
  void initState() {
    super.initState();
    _fetchPlans();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Supabase realtime: Admin publishes → Teacher Dashboard updates
  /// without requiring the teacher to recreate or add anything.
  void _subscribeRealtime() {
    if (_section.isEmpty) return;
    try {
      _realtimeSub = _client
          .from(LessonPlanService.table)
          .stream(primaryKey: ['id'])
          .eq('grade', _section)
          .listen((_) {
            if (mounted) _fetchPlans(silent: true);
          });
    } catch (_) {
      // Realtime unavailable — pull-to-refresh still works.
    }
  }

  Future<void> _fetchPlans({bool silent = false}) async {
    if (_section.isEmpty) {
      if (mounted) {
        setState(() {
          _plans = [];
          _files = {};
          _isLoading = false;
          _loadError = null;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      List rows;
      try {
        rows = await _client
            .from(LessonPlanService.table)
            .select('*')
            .eq('grade', _section)
            .eq('status', LessonPlanService.statusPublished)
            .order('created_at', ascending: false);
      } catch (_) {
        rows = await _client
            .from(LessonPlanService.table)
            .select('*')
            .eq('grade', _section)
            .order('created_at', ascending: false);
      }
      final plans = List<Map<String, dynamic>>.from(rows);
      final files = <int, Map<String, dynamic>>{};
      if (plans.isNotEmpty) {
        try {
          final ids = plans
              .map((p) => (p['id'] as num?)?.toInt())
              .whereType<int>()
              .toList();
          if (ids.isNotEmpty) {
            final fileRows = await _client
                .from(LessonPlanService.filesTable)
                .select('*')
                .inFilter('lesson_id', ids)
                .order('created_at', ascending: false);
            for (final f in List<Map<String, dynamic>>.from(fileRows)) {
              final lid = (f['lesson_id'] as num?)?.toInt();
              if (lid != null) files.putIfAbsent(lid, () => f);
            }
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _plans = plans;
          _files = files;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load lesson plans. Check your connection and try again. ($e)';
        });
      }
    }
  }

  /// The prominent plan: newest published for the teacher's section.
  Map<String, dynamic>? get _upcomingPlan =>
      _plans.isEmpty ? null : _plans.first;

  List<Map<String, dynamic>> get _previousPlans =>
      _plans.length <= 1 ? [] : _plans.sublist(1);

  Map<String, dynamic>? _fileOf(Map<String, dynamic> plan) {
    final id = (plan['id'] as num?)?.toInt();
    return id == null ? null : _files[id];
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

  Future<void> _viewPdf(Map<String, dynamic> plan) async {
    final path = LessonPlanService.filePathOf(_fileOf(plan) ?? {});
    if (path.isEmpty) {
      _snack('No PDF attached to this lesson plan.', Colors.orange);
      return;
    }
    if (mounted) setState(() => _busyPdf = true);
    try {
      final url = await LessonPlanService.resolvePdfUrl(_client, path);
      if (url == null || url.isEmpty) {
        _snack('Could not open PDF. File missing in storage.', Colors.red);
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonPdfViewerScreen(
            title: (plan['title'] ?? 'Lesson Plan').toString(),
            pdfUrl: url,
            fileName: LessonPlanService.fileNameOf(_fileOf(plan) ?? {}),
          ),
        ),
      );
    } catch (e) {
      _snack('Could not open PDF. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  /// Downloads the actual file stored in the lesson-files bucket.
  /// Verifies the bytes exist via `download`, then hands the URL to
  /// the system so the file is saved — never a fake/local PDF.
  Future<void> _downloadPdf(Map<String, dynamic> plan) async {
    final path = LessonPlanService.filePathOf(_fileOf(plan) ?? {});
    if (path.isEmpty) {
      _snack('No PDF attached to this lesson plan.', Colors.orange);
      return;
    }
    if (mounted) setState(() => _busyPdf = true);
    try {
      // 1. Verify + fetch the real bytes from Supabase Storage.
      try {
        final bytes = await _client.storage
            .from(LessonPlanService.bucket)
            .download(path);
        if (bytes.isEmpty) throw Exception('empty file');
      } catch (e) {
        _snack('Download failed — file not found in storage. ($e)', Colors.red);
        return;
      }
      // 2. Deliver the file via its storage URL (system handles saving).
      final url = await LessonPlanService.resolvePdfUrl(_client, path);
      if (url == null || url.isEmpty) {
        _snack('Download failed — could not resolve file URL.', Colors.red);
        return;
      }
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        _snack('Could not start download.', Colors.red);
      } else {
        _snack('⬇️ Download started.', Colors.green);
      }
    } catch (e) {
      _snack('Download failed. Check your connection. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyPdf = false);
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
        title: Text('Lesson Plan',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchPlans(),
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1565C0))),
                )
              else if (_loadError != null)
                _errorCard()
              else if (_upcomingPlan == null)
                _emptyState()
              else ...[
                Text('Upcoming Saturday',
                    style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 4),
                Text(_upcomingSaturdayLabel,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 10),
                _lessonCard(_upcomingPlan!, highlight: true),
                if (_previousPlans.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Previous Lesson Plans (${_previousPlans.length})',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 10),
                  for (final p in _previousPlans) ...[
                    _lessonCard(p),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ],
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
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9F0A), Color(0xFFFFB74D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9F0A).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lesson Plan',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('View your upcoming Saturday lesson plan.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.92))),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Section: ${LessonPlanService.prettySection(_section.isEmpty ? widget.section : _section)}',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _fetchPlans(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Retry',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Text('📚', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No lesson plan has been published for the upcoming Saturday yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 6),
          Text(_upcomingSaturdayLabel,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade500)),
          if (_previousPlans.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Previous Lesson Plans (${_previousPlans.length})',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 10),
            for (final p in _previousPlans) ...[
              _lessonCard(p),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _sectionBlock(String label, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0D47A1))),
        const SizedBox(height: 4),
        Text(body,
            style: GoogleFonts.poppins(
                fontSize: 13.5,
                height: 1.6,
                color: const Color(0xFF374151))),
      ],
    );
  }

  Widget _lessonCard(Map<String, dynamic> plan, {bool highlight = false}) {
    final title = (plan['title'] ?? 'Lesson Plan').toString();
    final about = LessonPlanService.aboutOf(plan).trim();
    // Older rows store 'Sunday School' in subject — not a real About text.
    final showAbout =
        about.isNotEmpty && about.toLowerCase() != 'sunday school';
    final summaryEn = LessonPlanService.summaryEnOf(plan);
    final summaryNe = LessonPlanService.summaryNeOf(plan);
    final fileName = LessonPlanService.fileNameOf(_fileOf(plan) ?? {});
    final date =
        LessonPlanService.prettyDateTime(LessonPlanService.publishDateOf(plan));
    final section =
        LessonPlanService.prettySection(plan['grade']?.toString());
    return FadeInSlide(
      index: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: highlight
              ? Border.all(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.4),
                  width: 1.5)
              : Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📚 $title',
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('📅 $date', const Color(0xFF1565C0)),
                _pill('🏫 Section: $section', const Color(0xFF7B1FA2)),
              ],
            ),
            if (showAbout) _sectionBlock('About', about),
            _sectionBlock('Summary — English', summaryEn),
            _sectionBlock('Summary — Nepali', summaryNe),
            if (fileName.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded,
                        color: Color(0xFFEF4444), size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('📄 $fileName',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_busyPdf)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(color: Color(0xFF1565C0)),
              ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _busyPdf ? null : () => _viewPdf(plan),
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: Text('View PDF',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _busyPdf ? null : () => _downloadPdf(plan),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text('Download PDF',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
