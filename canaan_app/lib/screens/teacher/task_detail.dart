import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/task_service.dart';

/// Teacher → Teacher Tasks → View Task.
///
/// Full task details (read-only — teachers can never change the title,
/// description, type or due date) plus the teacher's OWN status
/// selector: Not Completed / Working / Completed.
class TeacherTaskDetailPage extends StatefulWidget {
  final String assignmentId;
  final String teacherId;
  final String teacherName;
  const TeacherTaskDetailPage({
    super.key,
    required this.assignmentId,
    required this.teacherId,
    this.teacherName = '',
  });

  @override
  State<TeacherTaskDetailPage> createState() => _TeacherTaskDetailPageState();
}

class _TeacherTaskDetailPageState extends State<TeacherTaskDetailPage> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  TaskAssignment? _item;
  List<Map<String, dynamic>> _warnings = [];
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _fetch();
    void listen(String table) {
      try {
        _subs.add(_client
            .from(table)
            .stream(primaryKey: ['id']).listen((_) {
          if (mounted) _fetch(silent: true);
        }));
      } catch (_) {}
    }

    listen(TaskService.assignTable);
    listen(TaskService.warningsTable);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final items =
          await TaskService.fetchMine(widget.teacherId);
      TaskAssignment? hit;
      for (final a in items) {
        if (a.id == widget.assignmentId) {
          hit = a;
          break;
        }
      }
      if (!mounted) return;
      if (hit == null) throw Exception('task not found');
      final warnings = await TaskService.warningsForAssignment(
          widget.assignmentId);
      // Opening the warnings marks them read (best-effort).
      TaskService.markWarningsRead(
        assignmentId: widget.assignmentId,
        teacherId: widget.teacherId,
      );
      if (!mounted) return;
      setState(() {
        _item = hit;
        _warnings = warnings;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load the task. ($e)';
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

  Future<void> _setStatus(String status) async {
    final item = _item;
    if (item == null || _isSaving || item.status == status) return;
    setState(() => _isSaving = true);
    try {
      final ok = await TaskService.updateStatus(
        assignmentId: item.id,
        teacherId: widget.teacherId,
        teacherName: widget.teacherName,
        taskId: item.taskId,
        taskTitle: item.title,
        status: status,
      );
      if (!mounted) return;
      if (ok) {
        _snack(
          status == TaskService.statusCompleted
              ? '✅ Task marked as completed!'
              : 'Status updated to ${TaskService.statusLabel(status)}.',
          Colors.green,
        );
        await _fetch(silent: true);
      } else {
        _snack('Could not update. Please try again.', Colors.red);
      }
    } catch (e) {
      _snack('Could not update. Please try again. ($e)', Colors.red);
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
              colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Task Details',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFF7C3AED)))
          : _loadError != null || _item == null
              ? _errorState()
              : RefreshIndicator(
                  color: const Color(0xFF7C3AED),
                  onRefresh: () => _fetch(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerCard(_item!),
                        const SizedBox(height: 14),
                        _infoCard(_item!),
                        if (_warnings.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _warningsCard(),
                        ],
                        const SizedBox(height: 14),
                        _statusCard(_item!),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                backgroundColor: const Color(0xFF7C3AED),
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
      ),
    );
  }

  Widget _headerCard(TaskAssignment a) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E1065), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
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
          child: Icon(TaskService.typeIcon(a.taskType),
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  a.overdue
                      ? '🔴 Overdue · ${TaskService.dueLabel(a.dueDate)}'
                      : '${_dot(a.status)} ${TaskService.statusLabel(a.status)}',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.92))),
              ]),
        ),
      ]),
    );
  }

  String _dot(String status) {
    switch (status) {
      case TaskService.statusWorking:
        return '🟡';
      case TaskService.statusCompleted:
        return '🟢';
      default:
        return '🔴';
    }
  }

  Widget _infoCard(TaskAssignment a) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
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
          _kv('Task Type',
              a.taskType.isEmpty ? 'Other' : a.taskType),
          _kv('Description',
              a.description.trim().isEmpty ? '—' : a.description.trim(),
              multiline: true),
          _kv('Assigned By',
              a.createdBy.isEmpty ? 'Canaan Administrator' : a.createdBy),
          _kv('Section', TaskService.prettySection(a.section)),
          _kv('Due Date',
              '${TaskService.prettyDate(a.dueDate)} (${TaskService.dueLabel(a.dueDate)})'),
          if (a.isCompleted && a.completedAt.isNotEmpty)
            _kv('Completed', TaskService.prettyDate(a.completedAt)),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: multiline ? 1.6 : 1.3,
                  color: const Color(0xFF111827))),
        ],
      ),
    );
  }

  Widget _warningsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Warnings from Admin',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_warnings.length}',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final w in _warnings)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((w['message'] ?? '').toString(),
                      style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          height: 1.6,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 6),
                  Text(
                    TaskService.prettyDate(
                        (w['created_at'] ?? '').toString()),
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusCard(TaskAssignment a) {    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
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
          Text('Task Status',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 4),
          Text('Update your progress any time.',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          _statusOption(
            a,
            TaskService.statusNotCompleted,
            'Not Completed',
            'Not started yet',
            const Color(0xFFEF4444),
          ),
          const SizedBox(height: 8),
          _statusOption(
            a,
            TaskService.statusWorking,
            'Working',
            'Started working on it',
            const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 8),
          _statusOption(
            a,
            TaskService.statusCompleted,
            'Completed',
            'Finished — Admin is notified',
            const Color(0xFF22C55E),
          ),
        ],
      ),
    );
  }

  Widget _statusOption(
    TaskAssignment a,
    String value,
    String title,
    String subtitle,
    Color color,
  ) {
    final selected = a.status == value;
    return GestureDetector(
      onTap: _isSaving ? null : () => _setStatus(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? color : Colors.grey.shade400,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? color
                              : const Color(0xFF111827))),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (_isSaving && selected)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
          ],
        ),
      ),
    );
  }
}
