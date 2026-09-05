import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/recitation_service.dart';
import 'recitation.dart';

/// Teacher → Student → Memory Verse.
///
/// Section comes from the logged-in teacher (no manual picker).
/// Teachers create/edit/delete verses for their own section only.
/// With [isAdmin] the page becomes a read-only, all-sections overview
/// (delete still allowed) for Admin → Students → Memory Verses.
class TeacherMemoryVerse extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String? section;
  final bool isAdmin;
  const TeacherMemoryVerse({
    super.key,
    this.teacherId = '',
    this.teacherName = '',
    this.section,
    this.isAdmin = false,
  });

  @override
  State<TeacherMemoryVerse> createState() => _TeacherMemoryVerseState();
}

class _TeacherMemoryVerseState extends State<TeacherMemoryVerse> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _referenceController = TextEditingController();
  final _verseController = TextEditingController();

  bool get _adminView => widget.isAdmin;
  String? get _section =>
      _adminView ? (_sectionFilter == 'all' ? null : _sectionFilter) : widget.section;

  List<Map<String, dynamic>> _verses = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _sectionFilter = 'all';
  // Today's sent-report status per verse: verseId -> status.
  // pending/approved locks the recitation button.
  Map<int, String> _todayLocks = {};

  @override
  void initState() {
    super.initState();
    _fetchVerses();
    _fetchLocks();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _verseController.dispose();
    super.dispose();
  }

  String _prettySection(String? section) {
    final s = (section ?? '').trim();
    if (s == 'sub-junior') return 'Sub Junior';
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Reference for old rows that predate the verse_reference column.
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

  String _prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  Future<void> _fetchVerses() async {
    setState(() => _isLoading = true);
    try {
      // select('*') stays compatible with/without the verse_reference column.
      var query = _client.from('memory_verses').select('*');
      final section = _section;
      final rows = section == null || section.isEmpty
          ? await query.order('created_at', ascending: false)
          : await query.eq('section', section).order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _verses = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
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

  /// Loads today's sent reports (verse + teacher + date) to lock
  /// recitation buttons whose report already went to Admin.
  Future<void> _fetchLocks() async {
    if (_adminView || widget.teacherId.isEmpty) return;
    try {
      final rows = await _client
          .from('memory_verse_reports')
          .select('verse_id, status')
          .eq('teacher_id', widget.teacherId)
          .eq('date', _todayStr());
      final locks = <int, String>{};
      for (final r in (rows as List)) {
        final verseId = int.tryParse((r['verse_id'] ?? '').toString());
        if (verseId != null) {
          locks[verseId] =
              RecitationService.norm(r['status']?.toString());
        }
      }
      if (mounted) setState(() => _todayLocks = locks);
    } catch (_) {}
  }

  /// Locked when today's report is sent (pending) or approved.
  /// A rejected report unlocks for correction + resubmission.
  bool _isVerseLocked(Map<String, dynamic> v) {
    final verseId = (v['id'] as num?)?.toInt();
    if (verseId == null) return false;
    final st = _todayLocks[verseId] ?? '';
    return st == RecitationService.pending ||
        st == RecitationService.approved;
  }

  void _showAlreadyDonePopup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Color(0xFF22C55E),
                  Color(0xFF4ADE80)
                ]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Already Done',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            Text(
              'You have already done the recitation of students. Thank you!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('OK',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSaturdayPopup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  color: Color(0xFFF59E0B), size: 36),
            ),
            const SizedBox(height: 16),
            Text('Saturday Only',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            Text(
              'Recitation can only be done on Saturday.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('OK',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final reference = _referenceController.text.trim();
    final text = _verseController.text.trim();
    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{
        'title': reference,
        'verse_reference': reference,
        'content': text,
        'section': widget.section,
        'date': _todayStr(),
        'teacher_name': widget.teacherName,
      };
      if (widget.teacherId.isNotEmpty) {
        payload['teacher_id'] = widget.teacherId;
      }
      try {
        await _client.from('memory_verses').insert(payload);
      } catch (_) {
        // Retry without verse_reference if that column is missing.
        final fallback = Map<String, dynamic>.from(payload)
          ..remove('verse_reference');
        await _client.from('memory_verses').insert(fallback);
      }
      _referenceController.clear();
      _verseController.clear();
      await _fetchVerses();
      _snack('Memory verse submitted.', Colors.green);
    } catch (e) {
      _snack('Could not submit. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _editDialog(Map<String, dynamic> v) {
    final id = (v['id'] as num).toInt();
    final refController =
        TextEditingController(text: _referenceOf(v));
    final textController =
        TextEditingController(text: (v['content'] ?? '').toString());
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Memory Verse',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: refController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Verse Reference (e.g. John 3:16)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: textController,
                  maxLines: 4,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Memory Verse',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      try {
                        final payload = {
                          'title': refController.text.trim(),
                          'verse_reference': refController.text.trim(),
                          'content': textController.text.trim(),
                        };
                        try {
                          await _client
                              .from('memory_verses')
                              .update(payload)
                              .eq('id', id);
                        } catch (_) {
                          final fallback =
                              Map<String, dynamic>.from(payload)
                                ..remove('verse_reference');
                          await _client
                              .from('memory_verses')
                              .update(fallback)
                              .eq('id', id);
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _fetchVerses();
                        _snack('Memory verse updated.', Colors.green);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _snack('Could not update. Please try again.',
                            Colors.red);
                      } finally {
                        refController.dispose();
                        textController.dispose();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Save',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> v) {
    final id = (v['id'] as num).toInt();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Memory Verse?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Are you sure you want to delete "${_referenceOf(v)}"?',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _client.from('memory_verses').delete().eq('id', id);
                await _fetchVerses();
                _snack('Memory verse deleted.', Colors.green);
              } catch (e) {
                _snack('Could not delete. Please try again.', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
        title: Text(_adminView ? 'Memory Verses' : 'Memory Verse',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchVerses,
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              if (!_adminView) ...[
                const SizedBox(height: 12),
                _formCard(),
              ] else ...[
                const SizedBox(height: 12),
                _adminFilterChips(),
              ],
              const SizedBox(height: 20),
              Text(
                _adminView
                    ? 'All Memory Verses (${_verses.length})'
                    : 'Previously Added (${_verses.length})',
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827)),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1565C0))),
                )
              else
                _verseList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF22C55E), Color(0xFF4ADE80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.3),
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
                Text('Memory Verse',
                    style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _adminView
                        ? 'All Sections'
                        : 'Section: ${_prettySection(widget.section)}',
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
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Memory Verse',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 14),
            TextFormField(
              controller: _referenceController,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Verse Reference (e.g. John 3:16)',
                labelStyle:
                    GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
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
                        const BorderSide(color: Color(0xFF22C55E), width: 2)),
              ),
              validator: (val) =>
                  val == null || val.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _verseController,
              maxLines: 4,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Memory Verse',
                alignLabelWithHint: true,
                labelStyle:
                    GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
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
                        const BorderSide(color: Color(0xFF22C55E), width: 2)),
              ),
              validator: (val) =>
                  val == null || val.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF22C55E)
                      .withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Submit Memory Verse',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminFilterChips() {
    const options = [
      ('all', 'All'),
      ('sub-junior', 'Sub Junior'),
      ('junior', 'Junior'),
      ('senior', 'Senior'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            selected: _sectionFilter == value,
            onSelected: (_) {
              setState(() => _sectionFilter = value);
              _fetchVerses();
            },
            selectedColor: const Color(0xFF1565C0),
            labelStyle: GoogleFonts.poppins(
                color: _sectionFilter == value
                    ? Colors.white
                    : const Color(0xFF374151)),
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
      ],
    );
  }

  Widget _verseList() {
    if (_verses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.menu_book_outlined,
                size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No memory verses yet.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _verses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final v = _verses[i];
        final date = _prettyDate(
            (v['date'] ?? v['created_at'])?.toString());
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: const Border(
                left: BorderSide(color: Color(0xFF22C55E), width: 4)),
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
                    child: Text(_referenceOf(v),
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827))),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_prettySection(v['section']?.toString()),
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF15803D))),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('"${(v['content'] ?? '').toString().trim()}"',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFF374151),
                      height: 1.5)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${(v['teacher_name'] ?? '').toString()}${date.isNotEmpty ? ' • $date' : ''}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded,
                        color: Color(0xFF1565C0), size: 20),
                    tooltip: 'Edit',
                    onPressed: () => _editDialog(v),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_rounded,
                        color: Colors.red, size: 20),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(v),
                  ),
                ],
              ),
              if (!_adminView) ...[
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final locked = _isVerseLocked(v);
                  return SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (locked) {
                          _showAlreadyDonePopup();
                          return;
                        }
                        if (!RecitationService.markingAllowed) {
                          _showSaturdayPopup();
                          return;
                        }
                        final verseId = (v['id'] as num?)?.toInt();
                        if (verseId == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MarkRecitation(
                              teacherId: widget.teacherId,
                              teacherName: widget.teacherName,
                              section: (v['section'] ?? widget.section ?? '')
                                  .toString(),
                              verseId: verseId,
                              verseReference: _referenceOf(v),
                              verseText:
                                  (v['content'] ?? '').toString().trim(),
                            ),
                          ),
                        ).then((_) {
                          _fetchVerses();
                          _fetchLocks();
                        });
                      },
                      icon: Icon(
                          locked
                              ? Icons.lock_outline_rounded
                              : Icons.fact_check_rounded,
                          size: 20),
                      label: Text(
                          locked ? 'Recitation Done' : 'Mark Recitation',
                          style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: locked
                            ? Colors.grey.shade400
                            : const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}
