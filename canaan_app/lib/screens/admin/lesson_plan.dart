import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/lesson_plan_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../lesson_pdf_viewer.dart';

/// Admin → Management → Lesson Plan.
///
/// Creates and publishes PDF lesson plans for the upcoming Saturday,
/// scoped to a single section (Sub Junior / Junior / Senior).
/// Uses the existing `lesson_plans` + `lesson_plan_files` tables and
/// the existing `lesson-files` storage bucket.
class AdminLessonPlanPage extends StatefulWidget {
  final String adminName;
  const AdminLessonPlanPage({super.key, this.adminName = ''});

  @override
  State<AdminLessonPlanPage> createState() => _AdminLessonPlanPageState();
}

class _AdminLessonPlanPageState extends State<AdminLessonPlanPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _titleController = TextEditingController();
  final _aboutController = TextEditingController();
  final _summaryEnController = TextEditingController();
  final _summaryNeController = TextEditingController();

  String? _section;
  PlatformFile? _pickedFile;
  Uint8List? _pickedBytes;

  bool _isPicking = false;
  bool _isPublishing = false;
  bool _isLoading = true;
  String? _loadError;
  String _sectionFilter = 'all';

  List<Map<String, dynamic>> _plans = [];
  // lesson_id -> lesson_plan_files row (one file per plan).
  Map<int, Map<String, dynamic>> _files = {};
  StreamSubscription? _realtimeSub;

  int? _editingId;

  DateTime get _upcomingSaturday => LessonPlanService.upcomingSaturday();
  String get _upcomingSaturdayLabel =>
      LessonPlanService.prettyLessonDate(_upcomingSaturday);

  @override
  void initState() {
    super.initState();
    _fetchPlans();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _aboutController.dispose();
    _summaryEnController.dispose();
    _summaryNeController.dispose();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(LessonPlanService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchPlans(silent: true);
          });
    } catch (_) {
      // Realtime unavailable — pull-to-refresh still works.
    }
  }

  List<Map<String, dynamic>> get _filteredPlans {
    final list = _sectionFilter == 'all'
        ? List<Map<String, dynamic>>.from(_plans)
        : _plans
            .where((p) =>
                LessonPlanService.normalizeSection(p['grade']?.toString()) ==
                _sectionFilter)
            .toList();
    list.sort((a, b) => LessonPlanService.publishDateOf(b)
        .compareTo(LessonPlanService.publishDateOf(a)));
    return list;
  }

  Future<void> _fetchPlans({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(LessonPlanService.table)
          .select('*')
          .order('created_at', ascending: false);
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
        } catch (_) {
          // Plans still display without file info.
        }
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

  // ------------------------------------------------------------------
  // 3. Choose File — PDF only.
  // ------------------------------------------------------------------

  Future<void> _pickPdf() async {
    setState(() => _isPicking = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (file == null) return; // user canceled
      if (!LessonPlanService.isPdfName(file.name)) {
        _snack('Only PDF files are allowed.', Colors.orange);
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _snack('Could not read the selected PDF.', Colors.red);
        return;
      }
      if (bytes.length > 20 * 1024 * 1024) {
        _snack('PDF is too large. Please choose a file under 20 MB.',
            Colors.orange);
        return;
      }
      if (mounted) {
        setState(() {
          _pickedFile = file;
          _pickedBytes = bytes;
        });
      }
    } catch (e) {
      _snack('Could not open file picker. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _clearFile() {
    setState(() {
      _pickedFile = null;
      _pickedBytes = null;
    });
  }

  // ------------------------------------------------------------------
  // 8. Submit / Publish — writes lesson_plans + lesson_plan_files,
  // uploads the PDF to the lesson-files bucket.
  // ------------------------------------------------------------------

  Future<Map<String, String>> _adminIdentity() async {
    var id = '';
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        id = session.userId;
      }
    } catch (_) {}
    return {'id': id, 'name': widget.adminName};
  }

  Future<void> _publish() async {
    if (_isPublishing) return;
    if (!_formKey.currentState!.validate()) return;
    if (_section == null || _section!.isEmpty) {
      _snack('Please select a section.', Colors.orange);
      return;
    }
    final isEditing = _editingId != null;
    if (!isEditing && _pickedBytes == null) {
      _snack('Please choose a PDF lesson file.', Colors.orange);
      return;
    }
    if (_pickedFile != null &&
        !LessonPlanService.isPdfName(_pickedFile!.name)) {
      _snack('Only PDF files are allowed.', Colors.orange);
      return;
    }

    setState(() => _isPublishing = true);
    try {
      final grade = LessonPlanService.normalizeSection(_section);
      final now = DateTime.now().toIso8601String();
      final identity = await _adminIdentity();

      int lessonId;
      if (isEditing) {
        lessonId = _editingId!;
        final update = <String, dynamic>{
          'title': _titleController.text.trim(),
          'subject': _aboutController.text.trim(),
          'summary_en': _summaryEnController.text.trim(),
          'summary_np': _summaryNeController.text.trim(),
          'grade': grade,
          'updated_at': now,
        };
        await _client
            .from(LessonPlanService.table)
            .update(update)
            .eq('id', lessonId);
      } else {
        final insert = <String, dynamic>{
          'title': _titleController.text.trim(),
          'subject': _aboutController.text.trim(),
          'summary_en': _summaryEnController.text.trim(),
          'summary_np': _summaryNeController.text.trim(),
          'grade': grade,
          'status': LessonPlanService.statusPublished,
          'published_at': now,
          'updated_at': now,
        };
        if (identity['id']!.isNotEmpty) {
          insert['created_by'] = identity['id'];
        }
        if (identity['name']!.isNotEmpty) {
          insert['created_by_name'] = identity['name'];
        }
        final created = await _client
            .from(LessonPlanService.table)
            .insert(insert)
            .select('id')
            .single();
        lessonId = (created['id'] as num).toInt();
      }

      // Upload (or replace) the PDF in the lesson-files bucket and
      // link it from lesson_plan_files.
      if (_pickedBytes != null && _pickedFile != null) {
        final fileName = _pickedFile!.name;
        final filePath = LessonPlanService.storagePath(fileName);
        try {
          await _client.storage.from(LessonPlanService.bucket).uploadBinary(
                filePath,
                _pickedBytes!,
                fileOptions: const FileOptions(
                    contentType: 'application/pdf', upsert: true),
              );
        } catch (e) {
          throw Exception(
              'Lesson saved but PDF upload failed. Check the lesson-files bucket, then Edit to attach the PDF. ($e)');
        }
        final filePayload = <String, dynamic>{
          'lesson_id': lessonId,
          'file_name': fileName,
          'file_path': filePath,
          'file_size': _pickedBytes!.length,
          'mime_type': 'application/pdf',
        };
        final oldFile = _files[lessonId];
        if (oldFile != null && oldFile['id'] != null) {
          await _client
              .from(LessonPlanService.filesTable)
              .update(filePayload)
              .eq('id', oldFile['id']);
          final oldPath = LessonPlanService.filePathOf(oldFile);
          if (oldPath.isNotEmpty && oldPath != filePath) {
            try {
              await _client.storage
                  .from(LessonPlanService.bucket)
                  .remove([oldPath]);
            } catch (_) {}
          }
        } else {
          await _client
              .from(LessonPlanService.filesTable)
              .insert(filePayload);
        }
      }

      _snack(
        isEditing
            ? '✅ Lesson plan updated successfully!'
            : '✅ Lesson plan published successfully!',
        Colors.green,
      );
      _resetForm();
      await _fetchPlans(silent: true);
    } catch (e) {
      _snack('Could not publish. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _aboutController.clear();
    _summaryEnController.clear();
    _summaryNeController.clear();
    if (mounted) {
      setState(() {
        _section = null;
        _pickedFile = null;
        _pickedBytes = null;
        _editingId = null;
      });
    }
  }

  void _startEdit(Map<String, dynamic> plan) {
    _titleController.text = (plan['title'] ?? '').toString();
    _aboutController.text = LessonPlanService.aboutOf(plan);
    _summaryEnController.text = LessonPlanService.summaryEnOf(plan);
    _summaryNeController.text = LessonPlanService.summaryNeOf(plan);
    setState(() {
      _section = LessonPlanService.normalizeSection(plan['grade']?.toString());
      _editingId = (plan['id'] as num?)?.toInt();
      _pickedFile = null;
      _pickedBytes = null;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
    _snack('Editing mode — update the form, optionally replace the PDF.',
        const Color(0xFF1565C0));
  }

  void _confirmDelete(Map<String, dynamic> plan) {
    final id = (plan['id'] as num?)?.toInt();
    if (id == null) return;
    final title = (plan['title'] ?? 'this lesson plan').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Lesson Plan?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Are you sure you want to delete "$title"?\n\n'
            'Its PDF file will also be removed from storage.',
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
              await _deletePlan(plan);
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

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final id = (plan['id'] as num).toInt();
    final file = _files[id];
    try {
      if (file != null) {
        try {
          await _client
              .from(LessonPlanService.filesTable)
              .delete()
              .eq('lesson_id', id);
        } catch (_) {}
        final path = LessonPlanService.filePathOf(file);
        if (path.isNotEmpty) {
          try {
            await _client.storage
                .from(LessonPlanService.bucket)
                .remove([path]);
          } catch (_) {}
        }
      }
      await _client.from(LessonPlanService.table).delete().eq('id', id);
      if (_editingId == id) _resetForm();
      await _fetchPlans(silent: true);
      _snack('Lesson plan deleted.', Colors.green);
    } catch (e) {
      _snack('Could not delete. Please try again. ($e)', Colors.red);
    }
  }

  Future<void> _viewPdf(Map<String, dynamic> plan) async {
    final id = (plan['id'] as num?)?.toInt();
    final path = id == null ? '' : LessonPlanService.filePathOf(_files[id] ?? {});
    if (path.isEmpty) {
      _snack('No PDF attached to this lesson plan.', Colors.orange);
      return;
    }
    final url = await LessonPlanService.resolvePdfUrl(_client, path);
    if (url == null || url.isEmpty || !mounted) {
      _snack('Could not open PDF. File missing in storage.', Colors.red);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonPdfViewerScreen(
          title: (plan['title'] ?? 'Lesson Plan').toString(),
          pdfUrl: url,
          fileName: LessonPlanService.fileNameOf(_files[id] ?? {}),
        ),
      ),
    );
  }

  Future<void> _downloadPdf(Map<String, dynamic> plan) async {
    final id = (plan['id'] as num?)?.toInt();
    final path = id == null ? '' : LessonPlanService.filePathOf(_files[id] ?? {});
    if (path.isEmpty) {
      _snack('No PDF attached to this lesson plan.', Colors.orange);
      return;
    }
    try {
      // Verify the real bytes exist in the lesson-files bucket first.
      try {
        final bytes = await _client.storage
            .from(LessonPlanService.bucket)
            .download(path);
        if (bytes.isEmpty) throw Exception('empty file');
      } catch (e) {
        _snack('Download failed — file not found in storage. ($e)', Colors.red);
        return;
      }
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
      _snack('Download failed. ($e)', Colors.red);
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
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              _formCard(),
              const SizedBox(height: 20),
              Text(
                'Published Lesson Plans (${_filteredPlans.length})',
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827)),
              ),
              const SizedBox(height: 10),
              _filterChips(),
              const SizedBox(height: 12),
              _historyList(),
              const SizedBox(height: 12),
              if (kIsWeb)
                Text(
                  'PDFs are stored in the lesson-files bucket and linked from lesson_plan_files.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
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
            colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B1FA2).withValues(alpha: 0.3),
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
                  Text(
                    'Create and publish lesson plans for the upcoming Saturday.',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF7B1FA2), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  Widget _formCard() {
    final isEditing = _editingId != null;
    return FadeInSlide(
      index: 1,
      child: Container(
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
              Row(
                children: [
                  Expanded(
                    child: Text(isEditing ? 'Edit Lesson Plan' : 'Add Lesson Plan',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                  ),
                  if (isEditing)
                    TextButton.icon(
                      onPressed: _isPublishing ? null : _resetForm,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: Text('Cancel',
                          style: GoogleFonts.poppins(fontSize: 12.5)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // 1. Title
              _fieldLabel('1. Title'),
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration:
                    _inputDecoration('Title', 'Enter lesson title'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 14),
              // 2. About
              _fieldLabel('2. About'),
              TextFormField(
                controller: _aboutController,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'About', 'Write what this lesson is about...'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'About is required' : null,
              ),
              const SizedBox(height: 14),
              // 3. Choose File
              _fieldLabel('3. 📎 Choose Lesson File'),
              _filePickerBox(isEditing),
              const SizedBox(height: 14),
              // 4. Summary — English
              _fieldLabel('4. 🇬🇧 Summary (English)'),
              TextFormField(
                controller: _summaryEnController,
                maxLines: 5,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration('Summary (English)',
                    'Write the lesson summary in English...'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'English summary is required'
                    : null,
              ),
              const SizedBox(height: 14),
              // 5. Summary — Nepali
              _fieldLabel('5. 🇳🇵 Summary (Nepali)'),
              TextFormField(
                controller: _summaryNeController,
                maxLines: 5,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration('Summary (Nepali)',
                    'पाठको सारांश नेपालीमा लेख्नुहोस्...'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Nepali summary is required'
                    : null,
              ),
              const SizedBox(height: 14),
              // 6. Select Section
              _fieldLabel('6. Select Section'),
              DropdownButtonFormField<String>(
                initialValue: _section,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: const Color(0xFF111827)),
                decoration: _inputDecoration('Select Section', 'Select Section'),
                items: const [
                  DropdownMenuItem(
                      value: LessonPlanService.sectionSubJunior,
                      child: Text('Sub Junior')),
                  DropdownMenuItem(
                      value: LessonPlanService.sectionJunior,
                      child: Text('Junior')),
                  DropdownMenuItem(
                      value: LessonPlanService.sectionSenior,
                      child: Text('Senior')),
                ],
                onChanged: _isPublishing
                    ? null
                    : (v) => setState(() => _section = v),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Please select a section' : null,
              ),
              const SizedBox(height: 14),
              // 7. Upcoming Saturday
              _fieldLabel('7. Upcoming Saturday'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_month_rounded,
                          color: Color(0xFF7B1FA2), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lesson Date',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.grey.shade500)),
                          const SizedBox(height: 2),
                          Text(_upcomingSaturdayLabel,
                              style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // 8. Submit / Publish
              if (_isPublishing) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    color: Color(0xFF7B1FA2),
                    backgroundColor: Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _pickedBytes != null
                      ? 'Uploading PDF and publishing…'
                      : 'Publishing lesson plan…',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isPublishing ? null : _publish,
                  icon: _isPublishing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.upload_rounded, size: 20),
                  label: Text(
                    isEditing ? 'Update Lesson Plan' : '📤 Publish Lesson Plan',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B1FA2),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF7B1FA2)
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filePickerBox(bool isEditing) {
    final hasFile = _pickedFile != null && _pickedBytes != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasFile ? const Color(0xFF22C55E) : Colors.grey.shade300,
          width: hasFile ? 2 : 1.5,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              size: 40, color: Color(0xFFEF4444)),
          const SizedBox(height: 8),
          Text('📄 Choose Lesson File',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Upload PDF lesson material',
              style:
                  GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          if (!hasFile)
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _isPicking || _isPublishing ? null : _pickPdf,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isPicking
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Choose File',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_rounded,
                      color: Color(0xFFEF4444), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_pickedFile!.name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text(
                          LessonPlanService.formatFileSize(_pickedBytes!.length),
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF22C55E), size: 22),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _isPicking || _isPublishing ? null : _pickPdf,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      side: const BorderSide(color: Color(0xFF1565C0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Replace',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _isPicking || _isPublishing ? null : _clearFile,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Remove',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
          if (isEditing && !hasFile) ...[
            const SizedBox(height: 8),
            Text(
              'Keeping the current PDF. Pick a file above to replace it.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChips() {
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
            onSelected: (_) => setState(() => _sectionFilter = value),
            selectedColor: const Color(0xFF7B1FA2),
            labelStyle: GoogleFonts.poppins(
                color: _sectionFilter == value
                    ? Colors.white
                    : const Color(0xFF374151)),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          ),
      ],
    );
  }

  Widget _historyList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF7B1FA2))),
      );
    }
    if (_loadError != null) {
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
            Text(_loadError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetchPlans(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B1FA2),
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
    final items = _filteredPlans;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          children: [
            Icon(Icons.menu_book_outlined,
                size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No lesson plans published yet.',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151))),
            const SizedBox(height: 4),
            Text('Publish your first plan with the form above.',
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _historyCard(items[i]),
    );
  }

  Widget _historyCard(Map<String, dynamic> plan) {
    final id = (plan['id'] as num?)?.toInt();
    final file = id == null ? null : _files[id];
    final fileName = file == null ? '' : LessonPlanService.fileNameOf(file);
    final section = LessonPlanService.prettySection(plan['grade']?.toString());
    final date =
        LessonPlanService.prettyDateTime(LessonPlanService.publishDateOf(plan));
    final isEditingThis = _editingId == id;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(
                color: isEditingThis
                    ? const Color(0xFF7B1FA2)
                    : const Color(0xFFFFA000),
                width: 4)),
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
                child: Text('📚 ${(plan['title'] ?? '').toString()}',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827))),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA000).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(section,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFB45309))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('📅 $date',
              style:
                  GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
          if (fileName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded,
                    size: 16, color: Color(0xFFEF4444)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('📄 $fileName',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, color: const Color(0xFF374151))),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _viewPdf(plan),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('View',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _downloadPdf(plan),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF15803D),
                    side: const BorderSide(color: Color(0xFF22C55E)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('PDF',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit_rounded,
                    color: Color(0xFF1565C0), size: 20),
                tooltip: 'Edit',
                onPressed: () => _startEdit(plan),
              ),
              IconButton(
                icon:
                    const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(plan),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
