import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/task_service.dart';
import '../../widgets/animations.dart';
import 'teacher_task_form.dart';

/// Admin Dashboard → Teachers → Teacher Tasks.
///
/// Full monitoring: summary counts, filters (teacher / section /
/// status / type + search), per-teacher assignment cards with edit /
/// delete. Live via Supabase Realtime.
class AdminTeacherTasksPage extends StatefulWidget {
  final String adminName;
  const AdminTeacherTasksPage({super.key, this.adminName = ''});

  @override
  State<AdminTeacherTasksPage> createState() => _AdminTeacherTasksPageState();
}

class _AdminTeacherTasksPageState extends State<AdminTeacherTasksPage> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<TaskAssignment> _all = [];
  List<Map<String, dynamic>> _teachers = [];
  bool _isLoading = true;
  String? _loadError;

  String _search = '';
  String _teacherFilter = 'all';
  String _sectionFilter = 'all';
  String _statusFilter = 'all';
  String _typeFilter = 'all';

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _fetch();
    _watch();
  }

  @override
  void dispose() {
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

    listen(TaskService.tasksTable);
    listen(TaskService.assignTable);
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait([
        TaskService.fetchAll(),
        TaskService.teachersIn(null),
      ]);
      if (!mounted) return;
      setState(() {
        _all = results[0] as List<TaskAssignment>;
        _teachers = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load tasks. ($e)';
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

  // -- filtering ------------------------------------------------------------------

  List<String> get _typeOptions {
    final set = <String>{};
    for (final a in _all) {
      if (a.taskType.trim().isNotEmpty) set.add(a.taskType.trim());
    }
    final list = set.toList()..sort();
    return ['all', ...list];
  }

  List<TaskAssignment> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((a) {
      if (_teacherFilter != 'all' && a.teacherId != _teacherFilter) {
        return false;
      }
      if (_sectionFilter != 'all' &&
          TaskService.normalizeSection(a.section) != _sectionFilter) {
        return false;
      }
      if (_statusFilter != 'all' && a.bucket != _statusFilter) return false;
      if (_typeFilter != 'all' && a.taskType.trim() != _typeFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${a.title} ${a.teacherName} ${a.description}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  int _count(String bucket) =>
      _all.where((a) => a.bucket == bucket).length;
  int get _overdue =>
      _all.where((a) => a.bucket == 'overdue').length;

  // -- actions ----------------------------------------------------------------------

  Future<void> _openForm({TaskAssignment? existing}) async {
    final saved = await Navigator.push(
      context,
      SlidePageRoute(
        page: TeacherTaskFormPage(
          adminName: widget.adminName,
          existingTaskId: existing?.taskId,
          initialTitle: existing?.title ?? '',
          initialDescription: existing?.description ?? '',
          initialType: existing?.taskType ?? 'Other',
          initialSection: existing == null
              ? ''
              : TaskService.normalizeSection(existing.section),
          initialDue: TaskService.parseDate(existing?.dueDate) ??
              TaskService.defaultDueDate(),
        ),
      ),
    );
    if (saved == true && mounted) _fetch(silent: true);
  }

  Future<void> _confirmDelete(TaskAssignment a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Task?',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          '"${a.title}" and its assignments will be permanently removed.',
          style: GoogleFonts.poppins(
              fontSize: 14, color: Colors.grey.shade600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
    if (yes != true) return;
    final ok = await TaskService.deleteTask(a.taskId);
    if (!mounted) return;
    _snack(ok ? 'Task deleted.' : 'Could not delete. Please try again.',
        ok ? Colors.green : Colors.red);
    if (ok) _fetch(silent: true);
  }

  void _viewDetails(TaskAssignment a) {
    final msgController = TextEditingController();
    var warnings = <Map<String, dynamic>>[];
    var warningsLoading = true;
    var warningsStarted = false;
    var sending = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          if (!warningsStarted) {
            warningsStarted = true;
            TaskService.warningsForAssignment(a.id).then((w) {
              if (ctx.mounted) {
                setD(() {
                  warnings = w;
                  warningsLoading = false;
                });
              }
            });
          }

          Future<void> sendWarning() async {
            final text = msgController.text.trim();
            if (text.isEmpty) {
              _snack('Please write the warning message first.',
                  Colors.orange);
              return;
            }
            if (sending) return;
            setD(() => sending = true);
            try {
              final ok = await TaskService.sendWarning(
                assignmentId: a.id,
                taskId: a.taskId,
                teacherId: a.teacherId,
                teacherName: a.teacherName,
                taskTitle: a.title,
                message: text,
                createdBy: widget.adminName,
              );
              if (!ctx.mounted) return;
              if (ok) {
                msgController.clear();
                final fresh =
                    await TaskService.warningsForAssignment(a.id);
                if (!ctx.mounted) return;
                setD(() => warnings = fresh);
                _snack('⚠️ Warning sent to ${a.teacherName}.',
                    Colors.green);
              } else {
                _snack('Could not send. Please try again.', Colors.red);
              }
            } catch (_) {
              _snack('Could not send. Please try again.', Colors.red);
            } finally {
              if (ctx.mounted) setD(() => sending = false);
            }
          }

          return AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(a.title,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Teacher', a.teacherName),
              _detailRow('Section',
                  TaskService.prettySection(a.section)),
              _detailRow('Type',
                  a.taskType.isEmpty ? 'Other' : a.taskType),
              _detailRow('Due',
                  '${TaskService.prettyDate(a.dueDate)} (${TaskService.dueLabel(a.dueDate)})'),
              _detailRow('Status',
                  '${TaskService.statusLabel(a.status)}${a.overdue ? ' · Overdue' : ''}'),
              if (a.isCompleted && a.completedAt.isNotEmpty)
                _detailRow('Completed',
                    TaskService.prettyDate(a.completedAt)),
              if (a.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(a.description,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        height: 1.6,
                        color: const Color(0xFF374151))),
              ],
              // -- overdue warning box -----------------------------------
              if (a.overdue) ...[
                const SizedBox(height: 14),
                Container(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFEF4444), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Send Warning to Teacher',
                          style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827))),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'This task is ${TaskService.dueLabel(a.dueDate).toLowerCase()}. '
                  'Write a warning — it appears in the teacher\'s task instantly.',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                if (warningsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                        child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF1565C0)))),
                  )
                else if (warnings.isNotEmpty) ...[
                  for (final wmn in warnings)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444)
                            .withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFEF4444)
                                .withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text((wmn['message'] ?? '').toString(),
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  height: 1.5,
                                  color:
                                      const Color(0xFF111827))),
                          const SizedBox(height: 4),
                          Text(
                            TaskService.prettyDate(
                                (wmn['created_at'] ?? '')
                                    .toString()),
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                ],
                TextField(
                  controller: msgController,
                  maxLines: 3,
                  maxLength: 500,
                  style: GoogleFonts.poppins(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText:
                        'e.g. Please complete this task by tomorrow…',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFFEF4444), width: 2)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: sending ? null : sendWarning,
                    icon: sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text('Send Warning',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFEF4444)
                              .withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openForm(existing: a);
            },
            icon: const Icon(Icons.edit_rounded,
                size: 18, color: Color(0xFF1565C0)),
            label: Text('Edit',
                style: GoogleFonts.poppins(
                    color: const Color(0xFF1565C0),
                    fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDelete(a);
            },
            icon: const Icon(Icons.delete_rounded,
                size: 18, color: Color(0xFFEF4444)),
            label: Text('Delete',
                style: GoogleFonts.poppins(
                    color: const Color(0xFFEF4444),
                    fontWeight: FontWeight.w600)),
          ),
        ],
          );
        },
      ),
    ).then((_) => msgController.dispose());
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827))),
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
        title: Text('Teacher Tasks',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF1565C0),
        onRefresh: () => _fetch(),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF1565C0)))
            : _loadError != null
                ? _errorState()
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerCard(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add_rounded, size: 22),
                            label: Text('+ Add Teacher Task',
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _statsGrid(),
                        const SizedBox(height: 16),
                        _filters(),
                        const SizedBox(height: 12),
                        Text(
                          'Assignments (${_visible.length})',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827)),
                        ),
                        const SizedBox(height: 10),
                        if (_visible.isEmpty) _emptyState(),
                        for (final a in _visible) _taskCard(a),
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
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B2A5B), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.3),
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
          child: const Icon(Icons.task_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Teacher Tasks',
                    style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text('Assign work and monitor teacher progress.',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9))),
              ]),
        ),
      ]),
    );
  }

  Widget _statsGrid() {
    final cards = [
      _stat('Total Tasks', '${_all.length}', Icons.task_rounded,
          const Color(0xFF6366F1)),
      _stat('Completed', '${_count(TaskService.statusCompleted)}',
          Icons.check_circle_rounded, const Color(0xFF22C55E)),
      _stat('Working', '${_count(TaskService.statusWorking)}',
          Icons.hourglass_top_rounded, const Color(0xFFF59E0B)),
      _stat('Not Completed',
          '${_count(TaskService.statusNotCompleted)}',
          Icons.radio_button_unchecked_rounded,
          const Color(0xFFEF4444)),
      _stat('Overdue', '$_overdue', Icons.warning_amber_rounded,
          const Color(0xFFEF4444)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 104,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                      height: 1)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _search = v),
            style: GoogleFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Search title, teacher…',
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Color(0xFF1565C0), size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _dropDown(
                value: _teacherFilter,
                hint: 'Teacher',
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All Teachers')),
                  for (final t in _teachers)
                    DropdownMenuItem(
                      value: (t['id'] ?? '').toString(),
                      child: Text(
                        (t['full_name'] ?? '').toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _teacherFilter = v ?? 'all'),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _dropDown(
                value: _sectionFilter,
                hint: 'Section',
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('All Sections')),
                  DropdownMenuItem(
                      value: 'sub-junior', child: Text('Sub Junior')),
                  DropdownMenuItem(
                      value: 'junior', child: Text('Junior')),
                  DropdownMenuItem(
                      value: 'senior', child: Text('Senior')),
                ],
                onChanged: (v) =>
                    setState(() => _sectionFilter = v ?? 'all'),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _dropDown(
                value: _statusFilter,
                hint: 'Status',
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(
                      value: TaskService.statusNotCompleted,
                      child: Text('Not Completed')),
                  DropdownMenuItem(
                      value: TaskService.statusWorking,
                      child: Text('Working')),
                  DropdownMenuItem(
                      value: TaskService.statusCompleted,
                      child: Text('Completed')),
                  DropdownMenuItem(
                      value: 'overdue', child: Text('Overdue')),
                ],
                onChanged: (v) =>
                    setState(() => _statusFilter = v ?? 'all'),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _dropDown(
                value: _typeOptions.contains(_typeFilter)
                    ? _typeFilter
                    : 'all',
                hint: 'Type',
                items: [
                  const DropdownMenuItem(
                      value: 'all', child: Text('All Types')),
                  for (final t in _typeOptions.skip(1))
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) =>
                    setState(() => _typeFilter = v ?? 'all'),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropDown({
    required String value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      style:
          GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF111827)),
      dropdownColor: Colors.white,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Icon(Icons.task_outlined,
            size: 52, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('No tasks found.',
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151))),
        const SizedBox(height: 4),
        Text('Tap + Add Teacher Task to assign the first one.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _taskCard(TaskAssignment a) {
    final color =
        TaskService.statusColor(a.status, overdue: a.overdue);
    final statusText = a.overdue
        ? 'Overdue'
        : TaskService.statusLabel(a.status);
    return GestureDetector(
      onTap: () => _viewDetails(a),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(
              left: BorderSide(color: color, width: 4)),
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
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(TaskService.typeIcon(a.taskType),
                        color: color, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827))),
                        Text(
                          'Teacher: ${a.teacherName.isEmpty ? '—' : a.teacherName} · ${TaskService.prettySection(a.section)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    statusText,
                    color,
                    TaskService.statusIcon(a.status,
                        overdue: a.overdue),
                  ),
                  _chip('Due: ${TaskService.prettyDate(a.dueDate)}',
                      Colors.grey.shade600, Icons.event_rounded),
                  _chip(
                      TaskService.dueLabel(a.dueDate),
                      a.overdue
                          ? const Color(0xFFEF4444)
                          : a.dueSoon
                              ? const Color(0xFFF59E0B)
                              : Colors.grey.shade600,
                      Icons.schedule_rounded),
                ],
              ),
              if (a.isCompleted && a.completedAt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Completed: ${TaskService.prettyDate(a.completedAt)}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: const Color(0xFF22C55E)),
                ),
              ],
            ]),
      ),
    );
  }

  Widget _chip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}
