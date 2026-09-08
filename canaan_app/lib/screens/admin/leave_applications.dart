import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/leave_service.dart';
import '../../services/notification_service.dart';
import '../../services/session_service.dart';

/// Admin → Students → Leave Application.
///
/// All student leave applications, split by section tabs, with
/// search + status filters. Approve/Reject with an Admin comment;
/// approved applications can then be Sent to Teacher.
class AdminLeaveApplicationsPage extends StatefulWidget {
  final String adminName;
  const AdminLeaveApplicationsPage({super.key, this.adminName = ''});

  @override
  State<AdminLeaveApplicationsPage> createState() =>
      _AdminLeaveApplicationsPageState();
}

class _AdminLeaveApplicationsPageState
    extends State<AdminLeaveApplicationsPage>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _commentController = TextEditingController();

  static const _sections = ['sub-junior', 'junior', 'senior'];

  List<Map<String, dynamic>> _all = [];
  String _search = '';
  String _statusFilter = 'all';
  bool _isLoading = true;
  String? _loadError;
  bool _busyAction = false;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _commentController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(LeaveService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchAll(silent: true);
          });
    } catch (_) {}
  }

  Future<void> _fetchAll({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(LeaveService.table)
          .select('*')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _all = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('student_leave_applications') ||
            e.toString().contains('PGRST205')) {
          setState(() {
            _isLoading = false;
            _loadError =
                'TABLE_MISSING: run the one-time setup SQL in Supabase, then pull to refresh.';
          });
        } else {
          setState(() {
            _isLoading = false;
            _loadError =
                'Could not load applications. Check your connection. ($e)';
          });
        }
      }
    }
  }

  List<Map<String, dynamic>> _forSection(String section) {
    final q = _search.trim().toLowerCase();
    return _all.where((m) {
      if (LeaveService.normalizeSection(m['section']?.toString()) !=
          section) {
        return false;
      }
      if (_statusFilter != 'all' &&
          (m['status'] ?? '').toString() != _statusFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = (m['student_name'] ?? '').toString().toLowerCase();
      final sec =
          LeaveService.prettySection(m['section']?.toString()).toLowerCase();
      return name.contains(q) || sec.contains(q);
    }).toList();
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

  Future<String> _adminId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        return session.userId;
      }
    } catch (_) {}
    return '';
  }

  Future<void> _decide(Map<String, dynamic> m, bool approve) async {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty || _busyAction) return;
    final comment = _commentController.text.trim();
    if (!approve && comment.isEmpty) {
      _snack('Please write a comment explaining the rejection.',
          Colors.orange);
      return;
    }
    setState(() => _busyAction = true);
    try {
      final adminId = await _adminId();
      final now = DateTime.now().toIso8601String();
      final update = <String, dynamic>{
        'status': approve
            ? LeaveService.statusApproved
            : LeaveService.statusRejected,
        'admin_comment': comment.isEmpty ? null : comment,
        'approved_at': approve ? now : null,
        'updated_at': now,
      };
      if (adminId.isNotEmpty) update['approved_by'] = adminId;
      try {
        await _client
            .from(LeaveService.table)
            .update(update)
            .eq('id', id);
      } catch (_) {
        // approved_by type may differ — retry without it.
        update.remove('approved_by');
        await _client
            .from(LeaveService.table)
            .update(update)
            .eq('id', id);
      }
      if (!mounted) return;
      Navigator.pop(context);
      // 🔔 Notify the student of the decision (fire-and-forget).
      try {
        final studentId = (m['student_id'] ?? '').toString();
        if (studentId.isNotEmpty) {
          NotificationService.leaveDecided(
            applicationId: id,
            studentId: studentId,
            approved: approve,
          );
        }
      } catch (_) {}
      _snack(
          approve
              ? '✅ Application approved.'
              : 'Application rejected.',
          approve ? Colors.green : Colors.red);
      await _fetchAll(silent: true);
    } catch (e) {
      _snack('Could not update. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  /// Forwards an approved application to the section's teacher.
  /// Visibility is section-based; teacher_id records one of the
  /// section's teachers when resolvable.
  Future<void> _sendToTeacher(Map<String, dynamic> m) async {
    final id = (m['id'] ?? '').toString();
    if (id.isEmpty || _busyAction) return;
    setState(() => _busyAction = true);
    try {
      final section =
          LeaveService.normalizeSection(m['section']?.toString());
      String teacherId = '';
      try {
        final rows = await _client
            .from('teachers')
            .select('id')
            .eq('section', section)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(rows);
        if (list.isNotEmpty) {
          teacherId = (list.first['id'] ?? '').toString();
        }
      } catch (_) {}
      final now = DateTime.now().toIso8601String();
      final update = <String, dynamic>{
        'sent_to_teacher': true,
        'sent_to_teacher_at': now,
        'updated_at': now,
      };
      if (teacherId.isNotEmpty) update['teacher_id'] = teacherId;
      await _client
          .from(LeaveService.table)
          .update(update)
          .eq('id', id);
      if (!mounted) return;
      Navigator.pop(context);
      // 🔔 Notify the section's teacher (fire-and-forget).
      try {
        NotificationService.leaveSentToTeacher(
          applicationId: id,
          section: (m['section'] ?? '').toString(),
        );
      } catch (_) {}
      _snack('📨 Sent to the ${LeaveService.prettySection(section)} teacher.',
          Colors.green);
      await _fetchAll(silent: true);
    } catch (e) {
      _snack('Could not send. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  void _viewApplication(Map<String, dynamic> m) {
    _commentController.text = (m['admin_comment'] ?? '').toString();
    final status = (m['status'] ?? '').toString();
    final sent = m['sent_to_teacher'] == true;
    final canSend =
        status == LeaveService.statusApproved && !sent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Text('Student Leave Application',
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 16),
              _infoGrid([
                ('Student Name',
                    (m['student_name'] ?? '').toString()),
                ('Section',
                    LeaveService.prettySection(m['section']?.toString())),
                ('Application Date',
                    LeaveService.prettyDate(
                        m['application_date']?.toString())),
                ('From Date',
                    LeaveService.prettyDate(m['from_date']?.toString())),
              ]),
              const SizedBox(height: 12),
              _pillRow(status, sent),
              const SizedBox(height: 14),
              Text('Description',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6B7280))),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Text((m['description'] ?? '').toString(),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        height: 1.6,
                        color: const Color(0xFF1F2937))),
              ),
              const SizedBox(height: 14),
              Text('Admin Comment',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6B7280))),
              const SizedBox(height: 6),
              TextField(
                controller: _commentController,
                maxLines: 3,
                enabled: !_busyAction &&
                    status == LeaveService.statusPending,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Write a comment about this application...',
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
                      borderSide: const BorderSide(
                          color: Color(0xFF1565C0), width: 2)),
                ),
              ),
              const SizedBox(height: 18),
              if (status == LeaveService.statusPending) ...[
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _busyAction
                            ? null
                            : () => _decide(m, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _busyAction
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5))
                            : Text('Approve',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _busyAction
                            ? null
                            : () => _decide(m, false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text('Reject',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                ]),
              ],
              if (canSend) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                        _busyAction ? null : () => _sendToTeacher(m),
                    icon: _busyAction
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.send_rounded, size: 19),
                    label: Text('Send to Teacher',
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
              ],
              if (sent) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      '📨 Sent to teacher${(m['sent_to_teacher_at'] ?? '').toString().isNotEmpty ? ' • ${LeaveService.prettyDate(m['sent_to_teacher_at']?.toString())}' : ''}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF15803D))),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoGrid(List<(String, String)> rows) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 74,
      ),
      itemCount: rows.length,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(rows[i].$1,
                style: GoogleFonts.poppins(
                    fontSize: 11.5, color: const Color(0xFF6B7280))),
            const SizedBox(height: 2),
            Text(
                rows[i].$2.isEmpty ? '—' : rows[i].$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _pillRow(String status, bool sent) {
    Color color;
    String label;
    if (status == LeaveService.statusApproved) {
      color = const Color(0xFF22C55E);
      label = 'Approved';
    } else if (status == LeaveService.statusRejected) {
      color = const Color(0xFFEF4444);
      label = 'Rejected';
    } else {
      color = const Color(0xFFF59E0B);
      label = 'Pending';
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _pill(label, color),
      if (sent) _pill('Sent to Teacher', const Color(0xFF1565C0)),
    ]);
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
        title: Text('Student Leave Applications',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 17)),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: '🔍 Search student name or section...',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 13.5),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF1565C0), width: 2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (v, l) in [
                  ('all', 'All'),
                  ('pending', 'Pending'),
                  ('approved', 'Approved'),
                  ('rejected', 'Rejected'),
                ])
                  ChoiceChip(
                    label: Text(l,
                        style: GoogleFonts.poppins(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    selected: _statusFilter == v,
                    onSelected: (_) =>
                        setState(() => _statusFilter = v),
                    selectedColor: const Color(0xFF1565C0),
                    labelStyle: GoogleFonts.poppins(
                        color: _statusFilter == v
                            ? Colors.white
                            : const Color(0xFF374151)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : _loadError != null
                    ? _errorBody()
                    : RefreshIndicator(
                        onRefresh: () => _fetchAll(),
                        color: const Color(0xFF1565C0),
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _sectionList(_sections[0]),
                            _sectionList(_sections[1]),
                            _sectionList(_sections[2]),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody() {
    final missing = _loadError!.startsWith('TABLE_MISSING');
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Icon(
              missing
                  ? Icons.storage_rounded
                  : Icons.cloud_off_rounded,
              size: 48,
              color: missing
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(
              missing
                  ? 'The student_leave_applications table does not exist yet. Run the one-time setup SQL in Supabase, then pull to refresh.'
                  : _loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _fetchAll(),
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
      ),
    );
  }

  Widget _sectionList(String section) {
    final items = _forSection(section);
    if (items.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18)),
          child: Text('No applications in this section.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade500)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _fetchAll(),
      color: const Color(0xFF1565C0),
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _rowCard(items[i]),
      ),
    );
  }

  Widget _rowCard(Map<String, dynamic> m) {
    final status = (m['status'] ?? '').toString();
    final color = status == LeaveService.statusApproved
        ? const Color(0xFF22C55E)
        : status == LeaveService.statusRejected
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    final sent = m['sent_to_teacher'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text((m['student_name'] ?? '').toString(),
                style: GoogleFonts.poppins(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(LeaveService.prettyStatus(status),
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            'From: ${LeaveService.prettyDate(m['from_date']?.toString())} • Applied: ${LeaveService.prettyDate(m['application_date']?.toString())}${sent ? ' • 📨 Sent' : ''}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Text((m['description'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 13, color: const Color(0xFF374151))),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: () => _viewApplication(m),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('View',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
