import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/complaint_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';

/// Admin Dashboard → Management → Complaint.
///
/// Reviews problem reports submitted (without login) from the Login
/// page. New complaints arrive live via Supabase Realtime with a pending
/// count. Emergency rows are highlighted 🔴. Approve / Reject (with
/// reason) / Delete — records stay in history; nothing auto-resolves.
class AdminComplaintsPage extends StatefulWidget {
  final String adminName;
  const AdminComplaintsPage({super.key, this.adminName = ''});

  @override
  State<AdminComplaintsPage> createState() => _AdminComplaintsPageState();
}

class _AdminComplaintsPageState extends State<AdminComplaintsPage> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  bool _isLoading = true;
  String? _loadError;
  String _search = '';
  String _filterRole = '';
  String _filterType = '';
  String _filterStatus = '';
  String _adminId = '';
  StreamSubscription? _complaintSub;

  @override
  void initState() {
    super.initState();
    _init();
    _watchRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _complaintSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        _adminId = session.userId;
      }
    } catch (_) {}
    await _load();
  }

  void _watchRealtime() {
    try {
      _complaintSub = Supabase.instance.client
          .from(ComplaintService.table)
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _load(silent: true);
      });
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await ComplaintService.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load complaints. Run supabase/complaints.sql once, then retry. ($e)';
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

  int get _pendingCount => _all
      .where((c) =>
          (c['status'] ?? '') == ComplaintService.statusPending)
      .length;

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((c) {
      if (q.isNotEmpty) {
        final name = (c['full_name'] ?? '').toString().toLowerCase();
        final phone = (c['phone_number'] ?? '').toString().toLowerCase();
        final desc = (c['description'] ?? '').toString().toLowerCase();
        if (!name.contains(q) &&
            !phone.contains(q) &&
            !desc.contains(q)) {
          return false;
        }
      }
      if (_filterRole.isNotEmpty &&
          (c['role'] ?? '').toString() != _filterRole) {
        return false;
      }
      if (_filterType.isNotEmpty &&
          (c['complaint_type'] ?? '').toString() != _filterType) {
        return false;
      }
      if (_filterStatus.isNotEmpty &&
          (c['status'] ?? '').toString() != _filterStatus) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openDetail(Map<String, dynamic> c) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComplaintDetailSheet(
        complaint: c,
        adminId: _adminId,
      ),
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Complaint?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
            'Are you sure you want to delete this complaint?',
            style: GoogleFonts.poppins(fontSize: 13.5)),
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
    final ok = await ComplaintService.remove(
        (c['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Complaint deleted.', const Color(0xFF0E9F6E));
      _load(silent: true);
    } else {
      _snack('Could not delete. Please try again.', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
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
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text('Complaints',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
          if (_pendingCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$_pendingCount pending',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ]),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        color: const Color(0xFF1565C0),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF1565C0)))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _searchBox(),
                      const SizedBox(height: 10),
                      _filters(),
                      const SizedBox(height: 16),
                      Text(
                          'Complaints (${_visible.length}) · $_pendingCount pending',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827))),
                      const SizedBox(height: 10),
                      if (_loadError != null)
                        _errorCard()
                      else
                        _list(),
                    ]),
              ),
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _search = v),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search name, phone or description...',
        hintStyle: GoogleFonts.poppins(
            color: Colors.grey.shade400, fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: Color(0xFF1565C0)),
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

  Widget _filters() {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: _dropdown(
              value: _filterRole,
              items: const {
                '': 'Role: All',
                'teacher': 'Teacher',
                'student': 'Student',
              },
              onChanged: (v) =>
                  setState(() => _filterRole = v ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdown(
              value: _filterType,
              items: const {
                '': 'Type: All',
                'emergency': '🔴 Emergency',
                'reminder': '🔔 Reminder',
              },
              onChanged: (v) =>
                  setState(() => _filterType = v ?? ''),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _dropdown(
          value: _filterStatus,
          items: const {
            '': 'Status: All',
            'pending': 'Pending',
            'approved': 'Approved',
            'rejected': 'Rejected',
          },
          onChanged: (v) =>
              setState(() => _filterStatus = v ?? ''),
        ),
      ],
    );
  }

  Widget _dropdown({
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: GoogleFonts.poppins(
              fontSize: 13, color: const Color(0xFF111827)),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
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
      child: Column(children: [
        const Icon(Icons.storage_rounded,
            size: 48, color: Color(0xFFF59E0B)),
        const SizedBox(height: 12),
        Text(_loadError ?? '',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => _load(),
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

  Widget _list() {
    final items = _visible;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('📭', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text("You're all caught up!",
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _card(items[i], i),
    );
  }

  Widget _card(Map<String, dynamic> c, int index) {
    final emergency =
        (c['complaint_type'] ?? '') == ComplaintService.typeEmergency;
    final status = (c['status'] ?? '').toString();
    final statusColor = status == ComplaintService.statusApproved
        ? const Color(0xFF0E9F6E)
        : status == ComplaintService.statusRejected
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    return FadeInSlide(
      index: index % 6,
      child: GestureDetector(
        onTap: () => _openDetail(c),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: emergency
                ? const Color(0xFFFEF2F2)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(
                  color: emergency
                      ? const Color(0xFFEF4444)
                      : statusColor,
                  width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(emergency ? '🔴' : '🔔',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        (c['full_name'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        '${emergency ? 'Emergency · ' : ''}${status[0].toUpperCase()}${status.substring(1)}',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: statusColor)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                    '${(c['role'] ?? '').toString()} · ${(c['phone_number'] ?? '').toString()} · ${ComplaintService.prettyDateTime((c['created_at'] ?? '').toString())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 6),
                Text((c['description'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        color: const Color(0xFF374151))),
                const SizedBox(height: 10),
                Row(children: [
                  _miniAction(Icons.visibility_rounded,
                      'View', const Color(0xFF1565C0),
                      () => _openDetail(c)),
                  const SizedBox(width: 8),
                  _miniAction(Icons.delete_rounded, 'Delete',
                      const Color(0xFFEF4444), () => _delete(c)),
                ]),
              ]),
        ),
      ),
    );
  }

  Widget _miniAction(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ]),
      ),
    );
  }
}

/// Bottom sheet: full complaint details + Admin Comment + Approve /
/// Reject (with reason) actions.
class _ComplaintDetailSheet extends StatefulWidget {
  final Map<String, dynamic> complaint;
  final String adminId;
  const _ComplaintDetailSheet({
    required this.complaint,
    required this.adminId,
  });

  @override
  State<_ComplaintDetailSheet> createState() =>
      _ComplaintDetailSheetState();
}

class _ComplaintDetailSheetState
    extends State<_ComplaintDetailSheet> {
  final _commentController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _commentController.text =
        (widget.complaint['admin_comment'] ?? '').toString();
    _reasonController.text =
        (widget.complaint['rejection_reason'] ?? '').toString();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _approve() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Approve this complaint?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E9F6E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Approve',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _isBusy = true);
    final ok = await ComplaintService.approve(
      complaintId: (widget.complaint['id'] ?? '').toString(),
      adminComment: _commentController.text,
      adminId: widget.adminId,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (ok) {
      Navigator.pop(context);
      _snack('Complaint approved.', const Color(0xFF0E9F6E));
    } else {
      _snack('Could not approve. Please try again.', Colors.red);
    }
  }

  Future<void> _reject() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final ok = await ComplaintService.reject(
      complaintId: (widget.complaint['id'] ?? '').toString(),
      reason: _reasonController.text,
      adminId: widget.adminId,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (ok) {
      Navigator.pop(context);
      _snack('Complaint rejected.', const Color(0xFF0E9F6E));
    } else {
      _snack('Could not reject. Please try again.', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final emergency =
        (c['complaint_type'] ?? '') == ComplaintService.typeEmergency;
    final status = (c['status'] ?? '').toString();
    final pending = status == ComplaintService.statusPending;
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF0F4F8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Text(emergency ? '🔴' : '🔔',
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Complaint Details',
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                  ),
                ]),
                const SizedBox(height: 14),
                _row('Full Name:',
                    (c['full_name'] ?? '').toString()),
                _row('Role:', (c['role'] ?? '').toString()),
                _row('Phone Number:',
                    (c['phone_number'] ?? '').toString()),
                _row(
                    'Type:',
                    emergency
                        ? '🔴 Emergency'
                        : '🔔 Reminder'),
                _row('Submitted:',
                    ComplaintService.prettyDateTime(
                        (c['created_at'] ?? '').toString())),
                _row('Status:',
                    '${status[0].toUpperCase()}${status.substring(1)}'),
                const SizedBox(height: 10),
                Text('Description:',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6B7280))),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text((c['description'] ?? '').toString(),
                      style: GoogleFonts.poppins(
                          fontSize: 14, height: 1.6)),
                ),
                const SizedBox(height: 12),
                Text('Admin Comment (optional):',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6B7280))),
                const SizedBox(height: 6),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText:
                        'e.g. The login issue has been fixed. Please try again.',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400,
                        fontSize: 13),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF1565C0), width: 2)),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                if (pending) ...[
                  const SizedBox(height: 12),
                  Text('Reason / Admin Comment (for rejection):',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6B7280))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reasonController,
                    maxLines: 3,
                    style:
                        GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText:
                          'e.g. This issue has been forwarded to the technical team.',
                      hintStyle: GoogleFonts.poppins(
                          color: Colors.grey.shade400,
                          fontSize: 13),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF1565C0),
                              width: 2)),
                      contentPadding:
                          const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _isBusy ? null : _approve,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF0E9F6E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12)),
                            elevation: 0,
                          ),
                          child: Text('Approve',
                              style: GoogleFonts.poppins(
                                  fontWeight:
                                      FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _isBusy ? null : _reject,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12)),
                            elevation: 0,
                          ),
                          child: Text('Reject Complaint',
                              style: GoogleFonts.poppins(
                                  fontWeight:
                                      FontWeight.w700)),
                        ),
                      ),
                    ),
                  ]),
                ] else ...[
                  if (((c['admin_comment'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) ||
                          ((c['rejection_reason'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.grey.shade200),
                      ),
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            if ((c['admin_comment'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                              Text('Admin Comment',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      fontWeight:
                                          FontWeight.w700,
                                      color: const Color(
                                          0xFF6B7280))),
                              Text(
                                  (c['admin_comment'] ?? '')
                                      .toString(),
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5)),
                            ],
                            if ((c['rejection_reason'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('Rejection Reason',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      fontWeight:
                                          FontWeight.w700,
                                      color: const Color(
                                          0xFF6B7280))),
                              Text(
                                  (c['rejection_reason'] ??
                                          '')
                                      .toString(),
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5)),
                            ],
                          ]),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
