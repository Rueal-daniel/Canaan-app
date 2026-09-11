import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/language_service.dart';
import '../../services/leave_service.dart';
import '../../services/progress_service.dart';
import '../../widgets/star_rating.dart';

/// Admin → Students → Student Progress → Evaluate.
///
/// Attendance + Memory Verse are shown read-only (automatically
/// calculated from existing records). Admin enters Class Participation
/// and Discipline (percentage + rating + optional comment) and picks
/// the overall 5-star rating, then saves.
class EvaluateStudentPage extends StatefulWidget {
  final String studentId;
  final String fullName;
  final String section;
  final String adminName;
  const EvaluateStudentPage({
    super.key,
    required this.studentId,
    required this.fullName,
    required this.section,
    this.adminName = '',
  });

  @override
  State<EvaluateStudentPage> createState() => _EvaluateStudentPageState();
}

class _EvaluateStudentPageState extends State<EvaluateStudentPage> {
  final _formKey = GlobalKey<FormState>();
  final _partPctController = TextEditingController();
  final _partCommentController = TextEditingController();
  final _discPctController = TextEditingController();
  final _discCommentController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  AttendanceSummary _attendance =
      const AttendanceSummary(total: 0, present: 0, absent: 0, percent: 0);
  MemorySummary _memory = const MemorySummary(
      total: 0, recited: 0, halfRecited: 0, notRecited: 0, percent: 0);
  String _partRating = ProgressService.ratingGood;
  String _discRating = ProgressService.ratingGood;
  int _stars = 0;

  String get _section =>
      LeaveService.normalizeSection(widget.section);

  String _prettySection(String s) {
    if (s == 'sub-junior') return 'Sub Junior';
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partPctController.dispose();
    _partCommentController.dispose();
    _discPctController.dispose();
    _discCommentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProgressService.attendanceFor(widget.fullName),
        ProgressService.memoryFor(
            widget.studentId, widget.section),
        ProgressService.evaluationFor(widget.studentId),
      ]);
      if (!mounted) return;
      final eval = results[2] as Map<String, dynamic>?;
      setState(() {
        _attendance = results[0] as AttendanceSummary;
        _memory = results[1] as MemorySummary;
        if (eval != null) {
          _partPctController.text =
              ProgressService.evalInt(eval, 'participation_percentage')
                  .toString();
          _discPctController.text =
              ProgressService.evalInt(eval, 'discipline_percentage')
                  .toString();
          _partCommentController.text =
              ProgressService.evalString(eval, 'participation_comment');
          _discCommentController.text =
              ProgressService.evalString(eval, 'discipline_comment');
          final pr = ProgressService.evalString(
              eval, 'participation_rating', ProgressService.ratingGood);
          final dr = ProgressService.evalString(
              eval, 'discipline_rating', ProgressService.ratingGood);
          if (ProgressService.ratings.contains(pr)) _partRating = pr;
          if (ProgressService.ratings.contains(dr)) _discRating = dr;
          final st = ProgressService.evalInt(eval, 'overall_star_rating');
          _stars = st.clamp(0, 5);
        } else {
          _partPctController.text = '0';
          _discPctController.text = '0';
        }
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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

  String? _pctValidator(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return tr('pg_enter_pct');
    if (n < 0 || n > 100) return tr('pg_enter_pct');
    return null;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ProgressService.saveEvaluation(
        studentId: widget.studentId,
        section: _section,
        participationPercent:
            int.parse(_partPctController.text.trim()),
        participationRating: _partRating,
        participationComment: _partCommentController.text,
        disciplinePercent: int.parse(_discPctController.text.trim()),
        disciplineRating: _discRating,
        disciplineComment: _discCommentController.text,
        stars: _stars,
        evaluatedBy: widget.adminName,
      );
      if (!mounted) return;
      _snack(tr('pg_saved'), Colors.green);
      Navigator.pop(context, true);
    } catch (e) {
      _snack('${tr('pg_save_fail')} ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        title: Text(tr('pg_eval_title'),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF1565C0)))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _identityCard(),
                    const SizedBox(height: 14),
                    _autoCard(
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFF22C55E),
                      title: 'Attendance',
                      subtitle: tr('pg_auto'),
                      percent: _attendance.percent,
                      detail:
                          '${_attendance.present} Present · ${_attendance.absent} Absent · ${_attendance.total} Sessions',
                    ),
                    const SizedBox(height: 12),
                    _autoCard(
                      icon: Icons.menu_book_rounded,
                      color: const Color(0xFF6366F1),
                      title: 'Memory Verse Recitation',
                      subtitle: tr('pg_auto'),
                      percent: _memory.percent,
                      detail:
                          '${_memory.recited} Recited · ${_memory.halfRecited} Half · ${_memory.notRecited} Not · ${_memory.total} Verses',
                    ),
                    const SizedBox(height: 20),
                    Text(tr('pg_admin_eval'),
                        style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 12),
                    _evalCard(
                      icon: Icons.waving_hand_rounded,
                      color: const Color(0xFFFF9F0A),
                      title: tr('pg_participation'),
                      pctController: _partPctController,
                      rating: _partRating,
                      onRating: (v) =>
                          setState(() => _partRating = v),
                      commentController: _partCommentController,
                      commentHint:
                          'Participates actively in class activities...',
                    ),
                    const SizedBox(height: 12),
                    _evalCard(
                      icon: Icons.verified_user_rounded,
                      color: const Color(0xFF0E9F6E),
                      title: tr('pg_discipline'),
                      pctController: _discPctController,
                      rating: _discRating,
                      onRating: (v) =>
                          setState(() => _discRating = v),
                      commentController: _discCommentController,
                      commentHint:
                          'Shows good behavior and follows classroom guidelines.',
                    ),
                    const SizedBox(height: 20),
                    _starsCard(),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              const Color(0xFF22C55E)
                                  .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5))
                            : Text(tr('pg_save'),
                                style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _identityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('pg_eval_title'),
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          Text(widget.fullName,
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(_prettySection(_section),
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _autoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required double percent,
    required String detail,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text(detail,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: const Color(0xFF475569))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(ProgressService.pctLabel(percent),
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }

  Widget _evalCard({
    required IconData icon,
    required Color color,
    required String title,
    required TextEditingController pctController,
    required String rating,
    required ValueChanged<String> onRating,
    required TextEditingController commentController,
    required String commentHint,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                        color: const Color(0xFF111827))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(tr('pg_pct'),
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 6),
          TextFormField(
            controller: pctController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.poppins(fontSize: 15),
            validator: _pctValidator,
            decoration: InputDecoration(
              hintText: '0 – 100',
              suffixText: '%',
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
                      const BorderSide(color: Color(0xFF1565C0), width: 2)),
            ),
          ),
          const SizedBox(height: 12),
          Text(tr('pg_rating'),
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: rating,
            items: [
              for (final r in ProgressService.ratings)
                DropdownMenuItem(
                  value: r,
                  child: Text(ProgressService.ratingLabel(r),
                      style: GoogleFonts.poppins(fontSize: 14)),
                ),
            ],
            onChanged: (v) {
              if (v != null) onRating(v);
            },
            style: GoogleFonts.poppins(
                fontSize: 14, color: const Color(0xFF111827)),
            dropdownColor: Colors.white,
            decoration: InputDecoration(
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
                      const BorderSide(color: Color(0xFF1565C0), width: 2)),
            ),
          ),
          const SizedBox(height: 12),
          Text(tr('pg_comment'),
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 6),
          TextFormField(
            controller: commentController,
            maxLines: 2,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: InputDecoration(
              hintText: commentHint,
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
                      const BorderSide(color: Color(0xFF1565C0), width: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _starsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(tr('pg_overall_rating'),
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(tr('pg_star_hint'),
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          StarPicker(
            stars: _stars,
            onChanged: (v) => setState(() => _stars = v),
          ),
          const SizedBox(height: 10),
          Text(
            _stars == 0
                ? tr('pg_not_rated')
                : '$_stars.0 / 5 · ${ProgressService.starLabel(_stars)}',
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFB45309)),
          ),
        ],
      ),
    );
  }
}
