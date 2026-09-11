import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../services/task_service.dart';

/// Admin → Teachers → Teacher Tasks → + Add / Edit.
///
/// Create mode: title, description, type (predefined or custom),
/// section filter, teacher multi-picker (individual / multiple / all),
/// due date. Edit mode: the same task fields (assignments stay as-is).
class TeacherTaskFormPage extends StatefulWidget {
  final String adminName;

  /// Null when creating.
  final String? existingTaskId;
  final String initialTitle;
  final String initialDescription;
  final String initialType;
  final String initialSection;
  final DateTime initialDue;

  const TeacherTaskFormPage({
    super.key,
    this.adminName = '',
    this.existingTaskId,
    this.initialTitle = '',
    this.initialDescription = '',
    this.initialType = 'Other',
    this.initialSection = '',
    required this.initialDue,
  });

  @override
  State<TeacherTaskFormPage> createState() => _TeacherTaskFormPageState();
}

class _TeacherTaskFormPageState extends State<TeacherTaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _customTypeController = TextEditingController();

  bool get _isEditing => widget.existingTaskId != null;

  String _type = 'Memory Verse';
  bool _customType = false;
  String _section = '';
  DateTime _due = DateTime.now();
  List<Map<String, dynamic>> _teachers = [];
  final Set<String> _selected = {};
  bool _loadingTeachers = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.initialTitle;
    _descController.text = widget.initialDescription;
    _due = widget.initialDue;
    _section = TaskService.normalizeSection(widget.initialSection);
    final initial = widget.initialType.trim();
    if (initial.isNotEmpty &&
        TaskService.predefinedTypes.contains(initial)) {
      _type = initial;
      _customType = false;
    } else {
      _type = 'Other';
      _customType = initial.isNotEmpty && initial != 'Other';
      if (_customType) _customTypeController.text = initial;
    }
    _loadTeachers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  String get _effectiveType =>
      _customType ? _customTypeController.text.trim() : _type;

  Future<void> _loadTeachers() async {
    setState(() => _loadingTeachers = true);
    final list = await TaskService.teachersIn(
        _section.isEmpty ? null : _section);
    if (!mounted) return;
    setState(() {
      _teachers = list;
      _selected.removeWhere((id) =>
          !list.any((t) => (t['id'] ?? '').toString() == id));
      _loadingTeachers = false;
    });
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

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1565C0),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(
          () => _due = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<String> _adminLabel() async {
    if (widget.adminName.trim().isNotEmpty) {
      return widget.adminName.trim();
    }
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        final auth = AuthService();
        final profile = await auth.getUserById(
            userId: session.userId, role: UserRole.admin);
        final name = (profile?['full_name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'Canaan Administrator';
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_customType && _effectiveType.isEmpty) {
      _snack('Please type the custom task type.', Colors.orange);
      return;
    }
    if (!_isEditing && _selected.isEmpty) {
      _snack('Please select at least one teacher.', Colors.orange);
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        final ok = await TaskService.updateTask(
          taskId: widget.existingTaskId!,
          title: _titleController.text,
          description: _descController.text,
          taskType: _effectiveType,
          section: _section,
          dueDate: _due,
        );
        if (!mounted) return;
        _snack(ok ? '✅ Task updated.' : 'Could not update. Try again.',
            ok ? Colors.green : Colors.red);
        if (ok) Navigator.pop(context, true);
      } else {
        final chosen = _teachers
            .where((t) => _selected.contains((t['id'] ?? '').toString()))
            .toList();
        final id = await TaskService.createTask(
          title: _titleController.text,
          description: _descController.text,
          taskType: _effectiveType,
          section: _section,
          dueDate: _due,
          teachers: chosen,
          createdBy: await _adminLabel(),
        );
        if (!mounted) return;
        if (id.isEmpty) {
          _snack('Could not create the task. Try again.', Colors.red);
        } else {
          _snack(
              '✅ Task assigned to ${chosen.length} teacher${chosen.length == 1 ? '' : 's'}.',
              Colors.green);
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      _snack('Could not save. Please try again. ($e)', Colors.red);
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
        title: Text(_isEditing ? 'Edit Teacher Task' : 'Add Teacher Task',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Task Title'),
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _dec('e.g. Prepare Memory Verse Activity'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 14),
              _label('Description'),
              TextFormField(
                controller: _descController,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _dec(
                    'What should the teacher do, and for whom?'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Description is required'
                    : null,
              ),
              const SizedBox(height: 14),
              _label('Task Type'),
              DropdownButtonFormField<String>(
                initialValue: _customType ? 'Custom…' : _type,
                items: [
                  for (final t in TaskService.predefinedTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t,
                          style:
                              GoogleFonts.poppins(fontSize: 14)),
                    ),
                  DropdownMenuItem(
                    value: 'Custom…',
                    child: Text('Custom…',
                        style: GoogleFonts.poppins(fontSize: 14)),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _customType = v == 'Custom…';
                    if (!_customType) _type = v;
                  });
                },
                style: GoogleFonts.poppins(
                    fontSize: 14, color: const Color(0xFF111827)),
                dropdownColor: Colors.white,
                decoration: _dec(''),
              ),
              if (_customType) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _customTypeController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration:
                      _dec('Type the custom task type…'),
                  validator: (v) {
                    if (!_customType) return null;
                    return v == null || v.trim().isEmpty
                        ? 'Custom type is required'
                        : null;
                  },
                ),
              ],
              const SizedBox(height: 14),
              _label('Section'),
              DropdownButtonFormField<String>(
                initialValue: _section,
                items: const [
                  DropdownMenuItem(
                      value: '', child: Text('All Sections')),
                  DropdownMenuItem(
                      value: 'sub-junior', child: Text('Sub Junior')),
                  DropdownMenuItem(
                      value: 'junior', child: Text('Junior')),
                  DropdownMenuItem(
                      value: 'senior', child: Text('Senior')),
                ],
                onChanged: (v) {
                  setState(
                      () => _section = v ?? '');
                  _loadTeachers();
                },
                style: GoogleFonts.poppins(
                    fontSize: 14, color: const Color(0xFF111827)),
                dropdownColor: Colors.white,
                decoration: _dec(''),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _label('Assign To')),
                    TextButton(
                      onPressed: _loadingTeachers
                          ? null
                          : () => setState(() => _selected.addAll(
                              _teachers.map((t) =>
                                  (t['id'] ?? '').toString()))),
                      child: Text('Select all',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1565C0))),
                    ),
                    TextButton(
                      onPressed: _loadingTeachers
                          ? null
                          : () => setState(() => _selected.clear()),
                      child: Text('Clear',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Colors.grey.shade600)),
                    ),
                  ],
                ),
                _teacherPicker(),
              ],
              const SizedBox(height: 14),
              _label('Due Date'),
              GestureDetector(
                onTap: _pickDue,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          color: Color(0xFF1565C0), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _prettyDue(_due),
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF111827)),
                        ),
                      ),
                      Text(TaskService.dueLabel(
                          TaskService.dateStr(_due)),
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF22C55E).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text(
                          _isEditing
                              ? 'Save Changes'
                              : 'Create Task',
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

  String _prettyDue(DateTime d) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday'
    ];
    return '${weekdays[d.weekday - 1]}, ${TaskService.prettyDate(TaskService.dateStr(d))}';
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
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
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Widget _teacherPicker() {
    if (_loadingTeachers) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF1565C0))),
      );
    }
    if (_teachers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text('No teachers found for this section.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13.5, color: Colors.grey.shade500)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _teachers.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (_, i) {
          final t = _teachers[i];
          final id = (t['id'] ?? '').toString();
          final name = (t['full_name'] ?? '').toString();
          final checked = _selected.contains(id);
          return CheckboxListTile(
            value: checked,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(id);
              } else {
                _selected.remove(id);
              }
            }),
            title: Text(name,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF111827))),
            subtitle: Text(
                TaskService.prettySection(
                    (t['section'] ?? '').toString()),
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade500)),
            activeColor: const Color(0xFF1565C0),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12),
            dense: true,
          );
        },
      ),
    );
  }
}
