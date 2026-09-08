import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/credential_service.dart';
import '../../services/notification_service.dart';
import '../../services/session_service.dart';

/// Admin → Authentication → Change Credentials Requests.
///
/// Reviews username/password change requests. Approving a username
/// change updates the account row (after a fresh uniqueness check);
/// password changes contain no passwords at all — the user sets the
/// new password themselves after approval. A request is marked
/// Approved only when its update actually succeeds.
class CredentialRequestsPage extends StatefulWidget {
  final String adminName;
  const CredentialRequestsPage({super.key, this.adminName = ''});

  @override
  State<CredentialRequestsPage> createState() => _CredentialRequestsPageState();
}

class _CredentialRequestsPageState extends State<CredentialRequestsPage> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _loadError;
  String _search = '';
  bool _busyAction = false;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(CredentialService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchRequests(silent: true);
          });
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _requests;
    return _requests.where((r) {
      final name = (r['full_name'] ?? '').toString().toLowerCase();
      final user = (r['current_username'] ?? '').toString().toLowerCase();
      final role =
          CredentialService.prettyRole(r['role']?.toString()).toLowerCase();
      return name.contains(q) || user.contains(q) || role.contains(q);
    }).toList();
  }

  int get _pendingCount => _requests
      .where((r) => (r['status'] ?? '') == CredentialService.statusPending)
      .length;

  Future<void> _fetchRequests({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(CredentialService.table)
          .select('*')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('credential_change_requests') ||
            e.toString().contains('PGRST205')) {
          setState(() {
            _isLoading = false;
            _loadError =
                'TABLE_MISSING: ask the developer for the one-time setup, then pull to refresh.';
          });
        } else {
          setState(() {
            _isLoading = false;
            _loadError =
                'Could not load requests. Check your connection and try again. ($e)';
          });
        }
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

  Future<String> _adminId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        return session.userId;
      }
    } catch (_) {}
    return '';
  }

  /// Fresh uniqueness check across students, teachers and admin,
  /// ignoring the requester's own row.
  Future<bool> _usernameTaken(String username, String excludeUserId) async {
    final name = username.trim();
    if (name.isEmpty) return true;
    for (final t in ['teachers', 'students', 'admin']) {
      try {
        final rows = await _client
            .from(t)
            .select('id, username')
            .eq('username', name)
            .limit(5);
        for (final r in (rows as List)) {
          final m = Map<String, dynamic>.from(r as Map);
          if ((m['id'] ?? '').toString() != excludeUserId) return true;
        }
      } catch (_) {}
    }
    return false;
  }

  void _viewRequest(Map<String, dynamic> req) {
    final status = (req['status'] ?? '').toString();
    final type = (req['change_type'] ?? '').toString();
    final wantsUsername = type == CredentialService.typeUsername ||
        type == CredentialService.typeBoth;
    final wantsPassword = type == CredentialService.typePassword ||
        type == CredentialService.typeBoth;
    final requestedUsername = (req['requested_username'] ?? '').toString();
    final reason = (req['rejection_reason'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
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
              Text('Credential Change Request',
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 4),
              Text(
                  CredentialService.prettyDate(
                      req['created_at']?.toString()),
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              _infoGrid([
                ('Full Name', (req['full_name'] ?? '').toString()),
                ('Role',
                    CredentialService.prettyRole(req['role']?.toString())),
                ('Section',
                    _prettySection((req['section'] ?? '').toString())),
                ('Status',
                    CredentialService.prettyStatus(status)),
              ]),
              const SizedBox(height: 12),
              _kv('Email', (req['email'] ?? '').toString()),
              _kv('Current Username',
                  (req['current_username'] ?? '').toString()),
              _kv('Requested Change',
                  CredentialService.prettyType(type)),
              if (wantsUsername)
                _kv('Current Username',
                    (req['current_username'] ?? '').toString()),
              if (wantsUsername)
                _kv('Requested Username',
                    requestedUsername.isEmpty ? '—' : requestedUsername),
              if (wantsPassword)
                _kv('Password Change', 'Password Change Requested'),
              if (wantsUsername && wantsPassword) ...[
                _kv('Username Change', 'Requested'),
                _kv('Password Change', 'Requested'),
              ],
              if (status == CredentialService.statusRejected &&
                  reason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFEF4444)
                            .withValues(alpha: 0.25)),
                  ),
                  child: Text('Rejection reason: "$reason"',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: const Color(0xFF374151))),
                ),
              ],
              const SizedBox(height: 20),
              if (status == CredentialService.statusPending) ...[
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _busyAction
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _approveRequest(req);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text('Approve Request',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 14)),
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
                            : () {
                                Navigator.pop(ctx);
                                _rejectDialog(req);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text('Reject Request',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ),
                ]),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      side: const BorderSide(color: Color(0xFF1565C0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Close',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _prettySection(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return '—';
    if (t == 'sub-junior' || t == 'sub junior') return 'Sub Junior';
    return t[0].toUpperCase() + t.substring(1);
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: const Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(value.isEmpty ? '—' : value,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827))),
        ),
      ]),
    );
  }

  /// Approves only after the credential update succeeds.
  Future<void> _approveRequest(Map<String, dynamic> req) async {
    final id = (req['id'] ?? '').toString();
    if (id.isEmpty || _busyAction) return;
    setState(() => _busyAction = true);
    try {
      final type = (req['change_type'] ?? '').toString();
      final role = (req['role'] ?? '').toString();
      final userId = (req['user_id'] ?? '').toString();
      final table = CredentialService.userTable(role);
      final wantsUsername = type == CredentialService.typeUsername ||
          type == CredentialService.typeBoth;
      final requestedUsername =
          (req['requested_username'] ?? '').toString().trim();

      if (userId.isEmpty) {
        throw Exception('request has no linked account');
      }
      if (wantsUsername) {
        if (requestedUsername.isEmpty) {
          throw Exception('request has no new username');
        }
        // Fresh uniqueness check at approval time.
        if (await _usernameTaken(requestedUsername, userId)) {
          _snack(
              'Cannot approve — "$requestedUsername" is already used by another account. The request stays pending.',
              Colors.red);
          return;
        }
        await _client.from(table).update(
            {'username': requestedUsername}).eq('id', userId);
      }
      final adminId = await _adminId();
      final now = DateTime.now().toIso8601String();
      final update = <String, dynamic>{
        'status': CredentialService.statusApproved,
        'reviewed_at': now,
        'updated_at': now,
      };
      if (adminId.isNotEmpty) update['reviewed_by'] = adminId;
      await _client
          .from(CredentialService.table)
          .update(update)
          .eq('id', id);
      // 🔔 Notify the user of the approval (fire-and-forget).
      try {
        if (userId.isNotEmpty) {
          NotificationService.credentialRequestDecided(
            requestId: id,
            userId: userId,
            approved: true,
          );
        }
      } catch (_) {}
      _snack('✅ Request approved.', Colors.green);
      await _fetchRequests(silent: true);
    } catch (e) {
      _snack('Approval failed safely — nothing was changed. ($e)',
          Colors.red);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  void _rejectDialog(Map<String, dynamic> req) {
    _reasonController.clear();
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Reject Request',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Optionally tell the user why (shown on their page).',
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Reason for rejection (optional)...',
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
                          const BorderSide(color: Color(0xFFEF4444), width: 2)),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _rejectRequest(
                    req, _reasonController.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Reject',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectRequest(
      Map<String, dynamic> req, String reason) async {
    final id = (req['id'] ?? '').toString();
    if (id.isEmpty || _busyAction) return;
    setState(() => _busyAction = true);
    try {
      final adminId = await _adminId();
      final now = DateTime.now().toIso8601String();
      final update = <String, dynamic>{
        'status': CredentialService.statusRejected,
        'rejection_reason': reason.isEmpty ? null : reason,
        'reviewed_at': now,
        'updated_at': now,
      };
      if (adminId.isNotEmpty) update['reviewed_by'] = adminId;
      await _client
          .from(CredentialService.table)
          .update(update)
          .eq('id', id);
      // 🔔 Notify the user of the rejection (fire-and-forget).
      try {
        final targetUserId = (req['user_id'] ?? '').toString();
        if (targetUserId.isNotEmpty) {
          NotificationService.credentialRequestDecided(
            requestId: id,
            userId: targetUserId,
            approved: false,
          );
        }
      } catch (_) {}
      _snack('Request rejected.', Colors.red);
      await _fetchRequests(silent: true);
    } catch (e) {
      _snack('Could not reject. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyAction = false);
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
        title: Text('Change Credentials Requests',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchRequests(),
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  _pendingCount > 0
                      ? '$_pendingCount waiting for review'
                      : 'All reviewed 🎉',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 10),
              _searchBox(),
              const SizedBox(height: 12),
              _requestList(),
            ],
          ),
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
        hintText: '🔍 Search name, username, role...',
        hintStyle:
            GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13.5),
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

  Color _statusColor(String status) {
    switch (status) {
      case CredentialService.statusPending:
        return const Color(0xFFF59E0B);
      case CredentialService.statusApproved:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFFEF4444);
    }
  }

  Widget _requestList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }
    if (_loadError != null) {
      final missing = _loadError!.startsWith('TABLE_MISSING');
      return Container(
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
                  ? 'The credential_change_requests table does not exist yet. Run the one-time setup SQL in Supabase, then pull to refresh.'
                  : _loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _fetchRequests(),
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
    final items = _visible;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Text('No credential requests found.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151))),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _requestCard(items[i]),
    );
  }

  Widget _requestCard(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final color = _statusColor(status);
    final requestedUsername = (r['requested_username'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(18),
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
            child: Text((r['full_name'] ?? '').toString(),
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827))),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(CredentialService.prettyStatus(status),
                style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            '${CredentialService.prettyRole(r['role']?.toString())} • ${_prettySection((r['section'] ?? '').toString())}\n'
            'Current: ${(r['current_username'] ?? '').toString()}${requestedUsername.isNotEmpty ? ' → $requestedUsername' : ''}\n'
            '${CredentialService.prettyType(r['change_type']?.toString())} • ${CredentialService.prettyDate(r['created_at']?.toString())}',
            style: GoogleFonts.poppins(
                fontSize: 13, height: 1.65, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () => _viewRequest(r),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('View',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
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
            Text(rows[i].$2.isEmpty ? '—' : rows[i].$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
