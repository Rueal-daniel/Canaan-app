import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin → Teachers → Teacher Attendance.
///
/// Admin marks teacher attendance per section. Exactly two statuses:
/// Present / Absent — no Late anywhere. One record per teacher + date
/// (re-submit updates instead of duplicating).
class TeacherAttendanceAdmin extends StatefulWidget {
  const TeacherAttendanceAdmin({super.key});

  @override
  State<TeacherAttendanceAdmin> createState() =>
      _TeacherAttendanceAdminState();
}

class _TeacherAttendanceAdminState extends State<TeacherAttendanceAdmin>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;
  final _searchController = TextEditingController();

  static const _sections = ['sub-junior', 'junior', 'senior'];

  List<Map<String, dynamic>> _teachers = [];
  // teacher id -> present|absent for today's date
  Map<String, String> _statuses = {};
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSubmitting = false;
  // One-time rule: once today's attendance is submitted, it locks.
  bool _alreadySubmitted = false;

  // Saturday-only marking (teachers' Sunday School day).
  // Set to false to temporarily allow marking on any day.
  static const bool _enforceSaturdayOnly = true;

  bool get _isSaturday =>
      !_enforceSaturdayOnly ||
      DateTime.now().weekday == DateTime.saturday;

  String get _currentSection => _sections[_tabController.index];

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String get _todayLabel {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  int get _total => _visible.length;
  int get _present =>
      _visible.where((t) => _statuses[t['id'].toString()] == 'present').length;
  int get _absent => _total - _present;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _prettySection(String section) {
    if (section == 'sub-junior') return 'Sub Junior';
    if (section.isEmpty) return section;
    return section[0].toUpperCase() + section.substring(1);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  List<Map<String, dynamic>> get _visible {
    final q = _searchQuery.toLowerCase();
    return _teachers.where((t) {
      if (t['section'] != _currentSection) return false;
      if (q.isEmpty) return true;
      final name = (t['full_name'] ?? '').toString().toLowerCase();
      final email = (t['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final teachers = await _client
          .from('teachers')
          .select('id, full_name, email, section')
          .order('full_name');
      final list = List<Map<String, dynamic>>.from(teachers);

      // Existing records for today (dedupe key: teacher + date).
      // Any record means today was already submitted → lock everything.
      Map<String, String> statuses = {};
      bool alreadySubmitted = false;
      try {
        final existing = await _client
            .from('teacher_attendance')
            .select('teacher_id, status')
            .eq('date', _todayStr);
        final rows = (existing as List);
        alreadySubmitted = rows.isNotEmpty;
        for (final r in rows) {
          final st = (r['status'] ?? '').toString().trim().toLowerCase();
          statuses[r['teacher_id'].toString()] =
              st == 'absent' ? 'absent' : 'present';
        }
      } catch (_) {}

      // Default everyone visible to present.
      for (final t in list) {
        statuses.putIfAbsent(t['id'].toString(), () => 'present');
      }

      if (mounted) {
        setState(() {
          _teachers = list;
          _statuses = statuses;
          _alreadySubmitted = alreadySubmitted;
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

  Future<void> _submit() async {
    if (!_isSaturday) {
      _snack('Attendance can only be done on Saturday.', Colors.orange);
      return;
    }
    if (_alreadySubmitted) {
      _showAlreadyDonePopup();
      return;
    }
    if (_teachers.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final existingRows = await _client
          .from('teacher_attendance')
          .select('teacher_id')
          .eq('date', _todayStr);
      final existingIds = {
        for (final r in (existingRows as List)) r['teacher_id'].toString()
      };

      // Save every loaded teacher (all sections), not just the open tab.
      for (final t in _teachers) {
        final tid = t['id'].toString();
        final row = <String, dynamic>{
          'teacher_id': tid,
          'teacher_name': (t['full_name'] ?? '').toString(),
          'date': _todayStr,
          'status': _statuses[tid] ?? 'present',
        };
        if (existingIds.contains(tid)) {
          await _client
              .from('teacher_attendance')
              .update(row)
              .eq('teacher_id', tid)
              .eq('date', _todayStr);
        } else {
          await _client.from('teacher_attendance').insert(row);
        }
      }

      if (mounted) {
        setState(() => _alreadySubmitted = true);
      }
      _snack('Teacher attendance submitted successfully!', Colors.green);
    } catch (e) {
      _snack('Could not submit attendance: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
                gradient: LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF4ADE80)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Already Submitted',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
            const SizedBox(height: 8),
            Text(
              'Today\'s teacher attendance has already been submitted. Thank you!',
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
        title: Text('Teacher Attendance',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Sub Junior'),
            Tab(text: 'Junior'),
            Tab(text: 'Senior'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mark and manage attendance for teachers.',
                    style: GoogleFonts.poppins(
                        fontSize: 13.5, color: Colors.grey.shade600)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          color: Color(0xFF1565C0), size: 22),
                      const SizedBox(width: 10),
                      Text('Attendance Date: $_todayLabel',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF111827))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _summaryRow(),
                if (!_isSaturday || _alreadySubmitted) ...[
                  const SizedBox(height: 12),
                  _lockNotice(),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search teachers',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xFF1565C0)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF1565C0), width: 2)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _teacherList(),
                      _teacherList(),
                      _teacherList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _lockNotice() {
    final saturdayLock = !_isSaturday;
    final color = saturdayLock
        ? const Color(0xFFF59E0B)
        : const Color(0xFF22C55E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
              saturdayLock
                  ? Icons.lock_outline_rounded
                  : Icons.check_circle_rounded,
              color: color,
              size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                saturdayLock
                    ? 'Attendance can only be done on Saturday.'
                    : 'Today\'s attendance is already submitted.',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827))),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow() {
    return Row(
      children: [
        Expanded(
            child: _miniStat(
                '$_total', 'Total Teachers', const Color(0xFF6366F1))),
        const SizedBox(width: 10),
        Expanded(
            child: _miniStat(
                '$_present', 'Present', const Color(0xFF22C55E))),
        const SizedBox(width: 10),
        Expanded(
            child:
                _miniStat('$_absent', 'Absent', const Color(0xFFEF4444))),
      ],
    );
  }

  Widget _miniStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                  height: 1)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color)),
        ],
      ),
    );
  }

  /// Editing allowed only on Saturday and only before submission.
  bool get _editingAllowed => _isSaturday && !_alreadySubmitted;

  Widget _teacherList() {
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.co_present_rounded,
                size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No teachers in this section.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == items.length) {
          // Locked: greyed button that explains itself via popup on tap.
          if (!_editingAllowed) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _showAlreadyDonePopup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                          _alreadySubmitted
                              ? 'Attendance Submitted'
                              : 'Submit Attendance',
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              height: 54,
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
                    : Text('Submit Attendance',
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          );
        }
        final t = items[i];
        final id = t['id'].toString();
        final name = (t['full_name'] ?? '').toString();
        final current = _statuses[id] ?? 'present';
        final color = current == 'present'
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(_initials(name),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text((t['email'] ?? '').toString(),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                              _prettySection(
                                  (t['section'] ?? '').toString()),
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF6366F1))),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                              current == 'present' ? 'Present' : 'Absent',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: current,
                    icon: Icon(
                        Icons.arrow_drop_down_rounded,
                        color: _editingAllowed
                            ? color
                            : Colors.grey.shade400),
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _editingAllowed
                            ? color
                            : Colors.grey.shade400),
                    dropdownColor: Colors.white,
                    items: const [
                      DropdownMenuItem(
                          value: 'present', child: Text('Present')),
                      DropdownMenuItem(
                          value: 'absent', child: Text('Absent')),
                    ],
                    onChanged: _editingAllowed
                        ? (v) {
                            if (v != null) {
                              setState(() => _statuses[id] = v);
                            }
                          }
                        : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
