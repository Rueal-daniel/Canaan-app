import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/session_service.dart';
import '../../services/student_update_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/student_update_detail.dart';

/// Admin → Management → Student Update.
///
/// Pick a section → pick a student (info auto-loads, never editable) →
/// write the three observations → stars + percentage → Send. Below, the
/// full update history with search + filters and View | Edit | Delete.
class AdminStudentUpdatePage extends StatefulWidget {
  final String adminName;
  const AdminStudentUpdatePage({super.key, this.adminName = ''});

  @override
  State<AdminStudentUpdatePage> createState() => _AdminStudentUpdatePageState();
}

class _AdminStudentUpdatePageState extends State<AdminStudentUpdatePage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _studentSearchController = TextEditingController();
  final _histSearchController = TextEditingController();

  final _didController = TextEditingController();
  final _learnedController = TextEditingController();
  final _behaviourController = TextEditingController();
  final _percentController = TextEditingController();
  final _notesController = TextEditingController();

  String _sectionTab = StudentUpdateService.sectionSubJunior;
  List<Map<String, dynamic>> _students = [];
  bool _loadingStudents = false;
  String _studentSearch = '';

  Map<String, dynamic>? _selectedStudent;
  String _teacherNames = '';
  bool _loadingTeacher = false;

  int _rating = 0;
  bool _isSaving = false;
  int? _editingId;

  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _loadError;

  String _histSearch = '';
  String _histMonth = '';
  String _histRating = '';
  String _histPct = '';

  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
    _fetchHistory();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _studentSearchController.dispose();
    _histSearchController.dispose();
    _didController.dispose();
    _learnedController.dispose();
    _behaviourController.dispose();
    _percentController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(StudentUpdateService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
        if (mounted) _fetchHistory(silent: true);
      });
    } catch (_) {}
  }

  Future<void> _fetchStudents() async {
    if (mounted) setState(() => _loadingStudents = true);
    try {
      var query = _client
          .from('students')
          .select('id, full_name, section');
      if (_sectionTab != StudentUpdateService.sectionAll) {
        query = query.eq('section', _sectionTab);
      }
      final rows = await query.order('full_name');
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(rows);
          _loadingStudents = false;
          _selectedStudent = null;
          _teacherNames = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  Future<void> _fetchHistory({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(StudentUpdateService.table)
          .select('*')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _history = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load updates. Check your connection and try again. ($e)';
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

  Future<Map<String, String?>> _adminIdentity() async {
    var name = widget.adminName;
    String? id;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        id = session.userId;
        if (name.isEmpty) {
          final auth = AuthService();
          final profile = await auth.getUserById(
              userId: session.userId, role: UserRole.admin);
          name = (profile?['full_name'] ?? '').toString();
        }
      }
    } catch (_) {}
    return {'name': name.isEmpty ? 'Canaan Administrator' : name, 'id': id};
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final q = _studentSearch.trim().toLowerCase();
    if (q.isEmpty) return _students;
    return _students.where((s) {
      final name = (s['full_name'] ?? '').toString().toLowerCase();
      final id = (s['id'] ?? '').toString().toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  Future<void> _selectStudent(Map<String, dynamic>? s) async {
    setState(() {
      _selectedStudent = s;
      _teacherNames = '';
      _loadingTeacher = s != null;
    });
    if (s == null) return;
    final names = await StudentUpdateService.teacherNamesFor(
        _client, (s['section'] ?? '').toString());
    if (mounted) {
      setState(() {
        _teacherNames = names;
        _loadingTeacher = false;
      });
    }
  }

  String get _todayLabel {
    final now = DateTime.now();
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _send() async {
    if (_isSaving) return;
    if (_selectedStudent == null) {
      _snack('Please select a student first.', Colors.orange);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_rating < 1) {
      _snack('Please select a Saturday Rating (1–5 stars).', Colors.orange);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final identity = await _adminIdentity();
      final now = DateTime.now().toIso8601String();
      final s = _selectedStudent!;
      final payload = <String, dynamic>{
        'student_id': (s['id'] ?? '').toString(),
        'student_name': (s['full_name'] ?? '').toString(),
        'section': StudentUpdateService.normalizeSection(
            (s['section'] ?? '').toString()),
        'behaviour_detail': StudentUpdateService.combineDetail(
          didToday: _didController.text,
          learned: _learnedController.text,
          behaviour: _behaviourController.text,
        ),
        'saturday_rating': _rating,
        'total_percentage': int.parse(_percentController.text.trim()),
        'additional_notes': _notesController.text.trim(),
        'updated_at': now,
      };
      final isNew = _editingId == null;
      int savedId = _editingId ?? -1;
      String savedStudentId = payload['student_id'] as String;
      if (isNew) {
        payload['created_by'] = identity['name'];
        if ((identity['id'] ?? '').isNotEmpty) {
          payload['created_by_id'] = identity['id'];
        }
        try {
          final created = await _client
              .from(StudentUpdateService.table)
              .insert(payload)
              .select('id')
              .single();
          savedId = (created['id'] as num).toInt();
        } catch (_) {
          payload.remove('created_by_id');
          final created = await _client
              .from(StudentUpdateService.table)
              .insert(payload)
              .select('id')
              .single();
          savedId = (created['id'] as num).toInt();
        }
      } else {
        await _client
            .from(StudentUpdateService.table)
            .update(payload)
            .eq('id', _editingId!);
      }
      _resetForm(keepStudent: false);
      await _fetchHistory(silent: true);
      _snack(
        isNew
            ? 'Student Update Sent Successfully'
            : '✅ Student update saved.',
        Colors.green,
      );
      // 🔔 Only the specific student is notified — never others.
      if (isNew && savedId >= 0) {
        try {
          await NotificationService.studentUpdateSent(
            updateId: savedId.toString(),
            studentId: savedStudentId,
          );
        } catch (_) {}
      }
    } catch (e) {
      _snack('Could not send update. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm({bool keepStudent = false}) {
    _formKey.currentState?.reset();
    _didController.clear();
    _learnedController.clear();
    _behaviourController.clear();
    _percentController.clear();
    _notesController.clear();
    if (mounted) {
      setState(() {
        _rating = 0;
        _editingId = null;
        if (!keepStudent) {
          _selectedStudent = null;
          _teacherNames = '';
        }
      });
    }
  }

  void _startEdit(Map<String, dynamic> update) {
    final parts = StudentUpdateService.splitDetail(
        (update['behaviour_detail'] ?? '').toString());
    _didController.text = parts.$1;
    _learnedController.text = parts.$2;
    _behaviourController.text = parts.$3;
    _percentController.text =
        StudentUpdateService.percentageOf(update).toString();
    _notesController.text = (update['additional_notes'] ?? '').toString();
    setState(() {
      _rating = StudentUpdateService.ratingOf(update);
      _editingId = StudentUpdateService.updateIdOf(update);
      // Lock the form to this update's student.
      _selectedStudent = {
        'id': (update['student_id'] ?? '').toString(),
        'full_name': (update['student_name'] ?? '').toString(),
        'section': (update['section'] ?? '').toString(),
      };
      _teacherNames = '';
      _loadingTeacher = true;
    });
    StudentUpdateService.teacherNamesFor(
            _client, (update['section'] ?? '').toString())
        .then((names) {
      if (mounted) {
        setState(() {
          _teacherNames = names;
          _loadingTeacher = false;
        });
      }
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    _snack('Editing mode — update the fields and send again.',
        const Color(0xFF1565C0));
  }

  void _confirmDelete(Map<String, dynamic> update) {
    final id = StudentUpdateService.updateIdOf(update);
    final name = (update['student_name'] ?? 'this student').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Update?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Delete the update for "$name"?',
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
              try {
                await _client
                    .from(StudentUpdateService.table)
                    .delete()
                    .eq('id', id);
                if (_editingId == id) _resetForm();
                await _fetchHistory(silent: true);
                _snack('Update deleted.', Colors.green);
              } catch (e) {
                _snack('Could not delete. Please try again. ($e)', Colors.red);
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

  // -- history filters ---------------------------------------------------------------------

  List<String> get _monthOptions {
    final set = <String>{};
    for (final u in _history) {
      final k = StudentUpdateService.monthKeyOf(u);
      if (k.isNotEmpty) set.add(k);
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  String _monthOptionLabel(String ym) {
    final parts = ym.split('-');
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
    if (y == 0) return ym;
    return StudentUpdateService.monthLabel(y, m);
  }

  bool _pctMatch(int pct) {
    switch (_histPct) {
      case 'lt50':
        return pct < 50;
      case '50-69':
        return pct >= 50 && pct <= 69;
      case '70-84':
        return pct >= 70 && pct <= 84;
      case '85-100':
        return pct >= 85;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    final q = _histSearch.trim().toLowerCase();
    return _history.where((u) {
      if (_sectionTab != StudentUpdateService.sectionAll &&
          StudentUpdateService.normalizeSection(
                  u['section']?.toString()) != _sectionTab) {
        return false;
      }
      if (_histMonth.isNotEmpty &&
          StudentUpdateService.monthKeyOf(u) != _histMonth) {
        return false;
      }
      if (_histRating.isNotEmpty &&
          StudentUpdateService.ratingOf(u).toString() != _histRating) {
        return false;
      }
      if (!_pctMatch(StudentUpdateService.percentageOf(u))) return false;
      if (q.isNotEmpty) {
        final hay =
            '${u['student_name']} ${u['student_id']}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // -- build --------------------------------------------------------------------------------------

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
        title: Text('Student Update',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchStudents();
          await _fetchHistory();
        },
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
              _sectionTabs(),
              const SizedBox(height: 12),
              _studentPicker(),
              if (_selectedStudent != null) ...[
                const SizedBox(height: 12),
                _autoInfoCard(),
                const SizedBox(height: 12),
                _formCard(),
              ],
              const SizedBox(height: 20),
              Text('Update History (${_filteredHistory.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _historySearch(),
              const SizedBox(height: 10),
              _historyFilters(),
              const SizedBox(height: 12),
              _historyList(),
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
            colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
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
            child: const Icon(Icons.assignment_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Student Update',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Weekly personal feedback for each student — delivered straight to them.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTabs() {
    final tabs = [
      (StudentUpdateService.sectionAll, 'All'),
      (StudentUpdateService.sectionSubJunior, 'Sub Junior'),
      (StudentUpdateService.sectionJunior, 'Junior'),
      (StudentUpdateService.sectionSenior, 'Senior'),
    ];
    return FadeInSlide(
      index: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Class Section',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tabs)
                  ChoiceChip(
                    label: Text(t.$2,
                        style: GoogleFonts.poppins(fontSize: 13)),
                    selected: _sectionTab == t.$1,
                    selectedColor: const Color(0xFF1565C0)
                        .withValues(alpha: 0.15),
                    checkmarkColor: const Color(0xFF1565C0),
                    onSelected: (_) {
                      setState(() => _sectionTab = t.$1);
                      _fetchStudents();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentPicker() {
    return FadeInSlide(
      index: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Student',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _studentSearch = v),
              controller: _studentSearchController,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: '🔍 Search student...',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 13.5),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                suffixIcon: _studentSearch.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _studentSearchController.clear();
                          setState(() => _studentSearch = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
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
                        color: Color(0xFF1565C0), width: 2)),
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingStudents)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0))),
              )
            else if (_filteredStudents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No students found in this section.',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade500)),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedStudent == null
                    ? null
                    : (_selectedStudent!['id'] ?? '').toString(),
                isExpanded: true,
                hint: Text('Choose a student',
                    style: GoogleFonts.poppins(fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                items: _filteredStudents.map((s) {
                  final id = (s['id'] ?? '').toString();
                  final name = (s['full_name'] ?? '').toString();
                  return DropdownMenuItem(
                    value: id,
                    child: Text(name,
                        style: GoogleFonts.poppins(fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _editingId != null
                    ? null
                    : (id) {
                        if (id == null) return;
                        final match = _filteredStudents.firstWhere(
                          (s) =>
                              (s['id'] ?? '').toString() == id,
                          orElse: () => {},
                        );
                        if (match.isNotEmpty) {
                          _selectStudent(match);
                        }
                      },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
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
                          color: Color(0xFF1565C0), width: 2)),
                ),
              ),
            if (_editingId != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Student is locked while editing — cancel to pick another student.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _autoInfoCard() {
    final s = _selectedStudent!;
    Widget line(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
            ),
            Expanded(
              child: Text(
                  value.isEmpty ? '—' : value,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827))),
            ),
          ],
        ),
      );
    }

    return FadeInSlide(
      index: 3,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF1565C0).withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_rounded,
                    size: 15, color: Color(0xFF1565C0)),
                const SizedBox(width: 6),
                Text('Student Information (automatic)',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0))),
              ],
            ),
            const SizedBox(height: 10),
            line('Student Name',
                (s['full_name'] ?? '').toString()),
            line('Student ID', (s['id'] ?? '').toString()),
            line('Section',
                StudentUpdateService.prettySection(
                    (s['section'] ?? '').toString())),
            if (_loadingTeacher)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Loading teacher…',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: Colors.grey.shade500)),
              )
            else
              line('Teacher Name', _teacherNames),
            line('Update Date', _todayLabel),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13.5),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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

  Widget _fieldLabel(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827)),
          children: [
            TextSpan(text: text),
            if (optional)
              TextSpan(
                text: ' (optional)',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade500,
                    fontSize: 12.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _formCard() {
    final isEditing = _editingId != null;
    return FadeInSlide(
      index: 4,
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
              Row(children: [
                Expanded(
                  child: Text(
                      isEditing
                          ? 'Edit Student Update'
                          : 'New Student Update',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                if (isEditing)
                  TextButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _resetForm(),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text('Cancel',
                        style:
                            GoogleFonts.poppins(fontSize: 12.5)),
                  ),
              ]),
              const SizedBox(height: 14),
              _fieldLabel('What Did the Student Do Today?'),
              TextFormField(
                controller: _didController,
                enabled: !_isSaving,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    "Write what the student did during today's Sunday School..."),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please describe what the student did today'
                    : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('What Did the Student Learn?'),
              TextFormField(
                controller: _learnedController,
                enabled: !_isSaving,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Write what the student learned today...'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please describe what the student learned'
                    : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Student Behaviour — Behaviour Description'),
              TextFormField(
                controller: _behaviourController,
                enabled: !_isSaving,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    "Describe the student's behaviour during Sunday School..."),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please describe the behaviour'
                    : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Saturday Rating'),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: _isSaving
                          ? null
                          : () => setState(() => _rating = i),
                      tooltip: '$i Star${i == 1 ? '' : 's'}',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 44, minHeight: 44),
                      icon: Icon(
                        i <= _rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 36,
                        color: i <= _rating
                            ? const Color(0xFFF59E0B)
                            : Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _rating == 0
                    ? '☆☆☆☆☆  Tap a star (1–5)'
                    : 'Saturday Rating: ${StudentUpdateService.starsLabel(_rating)}',
                style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _rating == 0
                        ? Colors.grey.shade500
                        : const Color(0xFFB45309)),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Student Performance Percentage (0–100)'),
              TextFormField(
                controller: _percentController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration('e.g. 85').copyWith(
                  suffixText: '%',
                  suffixStyle: GoogleFonts.poppins(
                      fontSize: 14, color: Colors.grey.shade500),
                ),
                validator: StudentUpdateService.validatePercentage,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Additional Notes', optional: true),
              TextFormField(
                controller: _notesController,
                enabled: !_isSaving,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Add any additional information about the student...'),
              ),
              const SizedBox(height: 18),
              if (_isSaving) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    color: Color(0xFF1565C0),
                    backgroundColor: Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _send,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5))
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    isEditing
                        ? 'Save Changes'
                        : 'Send Student Update',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1565C0)
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

  Widget _historySearch() {
    return TextField(
      controller: _histSearchController,
      onChanged: (v) => setState(() => _histSearch = v),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: '🔍 Search student...',
        hintStyle:
            GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: Color(0xFF1565C0)),
        suffixIcon: _histSearch.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  _histSearchController.clear();
                  setState(() => _histSearch = '');
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
    );
  }

  Widget _historyFilters() {
    Widget drop({
      required String value,
      required String hint,
      required List<(String, String)> options,
      required ValueChanged<String?> onChanged,
    }) {
      return Expanded(
        child: DropdownButtonFormField<String>(
          value: value.isEmpty ? null : value,
          isExpanded: true,
          hint: Text(hint,
              style: GoogleFonts.poppins(fontSize: 12.5),
              overflow: TextOverflow.ellipsis),
          items: [
            DropdownMenuItem(
                value: '',
                child:
                    Text('All', style: GoogleFonts.poppins(fontSize: 12.5))),
            ...options.map((o) => DropdownMenuItem(
                  value: o.$1,
                  child: Text(o.$2,
                      style: GoogleFonts.poppins(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
          style: GoogleFonts.poppins(
              fontSize: 12.5, color: const Color(0xFF111827)),
        ),
      );
    }

    return Row(
      children: [
        drop(
          value: _histMonth,
          hint: 'Date',
          options:
              _monthOptions.map((m) => (m, _monthOptionLabel(m))).toList(),
          onChanged: (v) => setState(() => _histMonth = v ?? ''),
        ),
        const SizedBox(width: 8),
        drop(
          value: _histRating,
          hint: 'Rating',
          options: const [
            ('5', '⭐ 5'),
            ('4', '⭐ 4'),
            ('3', '⭐ 3'),
            ('2', '⭐ 2'),
            ('1', '⭐ 1'),
          ],
          onChanged: (v) => setState(() => _histRating = v ?? ''),
        ),
        const SizedBox(width: 8),
        drop(
          value: _histPct,
          hint: '%',
          options: const [
            ('85-100', '85–100%'),
            ('70-84', '70–84%'),
            ('50-69', '50–69%'),
            ('lt50', 'Below 50%'),
          ],
          onChanged: (v) => setState(() => _histPct = v ?? ''),
        ),
      ],
    );
  }

  Widget _historyList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
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
            onPressed: () => _fetchHistory(),
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
        ]),
      );
    }
    final items = _filteredHistory;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('📋', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No updates found.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 4),
          Text('Select a student above to send the first update.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade500)),
        ]),
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

  Widget _historyCard(Map<String, dynamic> update) {
    final id = StudentUpdateService.updateIdOf(update);
    final isEditingThis = _editingId == id && _editingId != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(
                color: isEditingThis
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF3B82F6),
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
                child: Text(
                    '👤 ${(update['student_name'] ?? '').toString()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
              ),
              Text('${StudentUpdateService.percentageOf(update)}%',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1565C0))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '📅 ${StudentUpdateService.prettyShortDate(update)}'
            ' · ${StudentUpdateService.prettySection(update['section']?.toString())}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            StudentUpdateService.starsLabel(
                StudentUpdateService.ratingOf(update)),
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => showStudentUpdateDetail(
                    context, update),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text('View',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  color: Color(0xFF1565C0), size: 20),
              tooltip: 'Edit',
              onPressed: () => _startEdit(update),
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  color: Colors.red, size: 20),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(update),
            ),
          ]),
        ],
      ),
    );
  }
}
