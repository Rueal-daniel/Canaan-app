import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/password_reset_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';

/// Admin → Authentication → Password Reset Requests. Cards (never a
/// plain table), summary counts, filters, search and realtime
/// updates. Passwords are never displayed.
class PasswordResetRequestsPage extends StatefulWidget {
  final String adminName;
  const PasswordResetRequestsPage({super.key, this.adminName = ''});

  @override
  State<PasswordResetRequestsPage> createState() =>
      _PasswordResetRequestsPageState();
}

class _PasswordResetRequestsPageState
    extends State<PasswordResetRequestsPage> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _loadError;
  String _filter = 'all';
  String _search = '';
  bool _busyAction = false;
  StreamSubscription? _realtimeSub;

  static const _filters = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('link_sent', 'Link Sent'),
    ('completed', 'Completed'),
    ('rejected', 'Rejected'),
  ];

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(PasswordResetService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchRequests(silent: true);
          });
    } catch (_) {}
  }

  int _count(String status) =>
      _requests.where((r) => (r['status'] ?? '') == status).length;

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    return _requests.where((r) {
      if (_filter != 'all' && (r['status'] ?? '') != _filter) return false;
      if (q.isEmpty) return true;
      final name = (r['full_name'] ?? '').toString().toLowerCase();
      final role = PasswordResetService.prettyRole(r['role']?.toString())
          .toLowerCase();
      final date = PasswordResetService.prettyDate(
              r['created_at']?.toString())
          .toLowerCase();
      return name.contains(q) || role.contains(q) || date.contains(q);
    }).toList();
  }

  Future<void> _fetchRequests({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(PasswordResetService.table)
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
        if (e.toString().contains('password_reset_requests') ||
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

  Future<String> _adminLabel() async {
    if (widget.adminName.isNotEmpty) return widget.adminName;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        final profile = await AuthService().getUserById(
            userId: session.userId, role: UserRole.admin);
        final name = (profile?['full_name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'Admin';
  }

  /// Matches the request to a teacher/student account by full name.
  /// Selects contact info only — the password column is never read.
  /// For students with no personal phone, falls back to a guardian phone.
  Future<Map<String, dynamic>?> _matchAccount(
      Map<String, dynamic> req) async {
    final role = (req['role'] ?? '').toString();
    final table =
        role == PasswordResetService.roleTeacher ? 'teachers' : 'students';
    final hintId = (req['user_id'] ?? '').toString();
    Future<Map<String, dynamic>?> byId(String id) async {
      try {
        final row = await _client
            .from(table)
            .select('id, full_name, username, phone, email, section')
            .eq('id', id)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row);
      } catch (_) {}
      return null;
    }

    Map<String, dynamic>? account;
    if (hintId.isNotEmpty) account = await byId(hintId);
    if (account == null) {
      try {
        final rows = await _client
            .from(table)
            .select('id, full_name, username, phone, email, section')
            .limit(300);
        final want = PasswordResetService.norm(req['full_name']?.toString());
        for (final r in (rows as List)) {
          final m = Map<String, dynamic>.from(r as Map);
          if (PasswordResetService.norm(m['full_name']?.toString()) == want) {
            account = m;
            break;
          }
        }
      } catch (_) {}
    }
    // Student with no own phone → use a guardian phone as backup contact.
    if (account != null &&
        role != PasswordResetService.roleTeacher &&
        (account['phone'] ?? '').toString().trim().isEmpty) {
      try {
        final row = await _client
            .from(table)
            .select('guardian_phone, father_phone, mother_phone')
            .eq('id', (account['id'] ?? '').toString())
            .maybeSingle();
        if (row != null) {
          final m = Map<String, dynamic>.from(row);
          for (final k in ['guardian_phone', 'father_phone', 'mother_phone']) {
            final p = (m[k] ?? '').toString().trim();
            if (p.isNotEmpty) {
              account['phone'] = p;
              break;
            }
          }
        }
      } catch (_) {}
    }
    return account;
  }

  void _viewRequest(Map<String, dynamic> req) async {
    _snack('Looking up the matching account…', const Color(0xFF1565C0));
    final account = await _matchAccount(req);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _detailSheet(req, account);
  }

  void _detailSheet(
      Map<String, dynamic> req, Map<String, dynamic>? account) {
    final id = (req['id'] as num?)?.toInt();
    final status = (req['status'] ?? '').toString();
    final contact = [
      if ((account?['phone'] ?? '').toString().isNotEmpty)
        '📱 ${(account!['phone'])}',
      if ((account?['email'] ?? '').toString().isNotEmpty)
        '✉️ ${(account!['email'])}',
    ].join('\n');
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
              Text('Password Reset Request',
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 4),
              Text(
                  PasswordResetService.prettyDate(
                      req['created_at']?.toString()),
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              _infoGrid([
                ('Full Name', (req['full_name'] ?? '').toString()),
                ('Role', PasswordResetService.prettyRole(req['role']?.toString())),
                ('Requested',
                    PasswordResetService.prettyType(req['request_type']?.toString())),
                ('Status', PasswordResetService.prettyStatus(status)),
              ]),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: account == null
                    ? Text(
                        '⚠️ No matching account found by full name. Verify the person manually before approving.',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: const Color(0xFFB45309),
                            height: 1.5))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Matched account ✅',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF15803D))),
                          const SizedBox(height: 6),
                          Text(
                              '${(account['full_name'] ?? '').toString()} • ${(account['section'] ?? '').toString()}\nUsername: ${(account['username'] ?? '').toString()}${contact.isEmpty ? '' : '\n$contact'}',
                              style: GoogleFonts.poppins(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: const Color(0xFF1F2937))),
                          const SizedBox(height: 6),
                          Text(
                              'Passwords are never displayed — only updated through the secure recovery flow.',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade600)),
                        ],
                      ),
              ),
              if (status == PasswordResetService.statusCompleted) ...[
                const SizedBox(height: 12),
                Text('John Doe has successfully completed the account recovery process.'
                    .replaceFirst('John Doe',
                        (req['full_name'] ?? 'The user').toString()),
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF15803D))),
              ],
              const SizedBox(height: 20),
              if (status == PasswordResetService.statusPending) ...[
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _busyAction || id == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _approveRequest(req, account);
                              },
                        icon: const Icon(Icons.check_circle_rounded, size: 19),
                        label: Text('Approve Request',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _busyAction || id == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _setStatus(req, PasswordResetService.statusRejected);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text('Reject',
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

  Future<void> _setStatus(Map<String, dynamic> req, String status) async {
    final id = (req['id'] as num?)?.toInt();
    if (id == null || _busyAction) return;
    setState(() => _busyAction = true);
    try {
      final admin = await _adminLabel();
      final now = DateTime.now().toIso8601String();
      await _client.from(PasswordResetService.table).update({
        'status': status,
        'processed_by': admin,
        'processed_at': now,
        'updated_at': now,
      }).eq('id', id);
      // 🔔 Notify the user of the rejection (fire-and-forget).
      if (status == PasswordResetService.statusRejected) {
        try {
          final targetUserId = (req['user_id'] ?? '').toString();
          if (targetUserId.isNotEmpty) {
            NotificationService.passwordResetDecided(
              requestId: id.toString(),
              userId: targetUserId,
              approved: false,
            );
          }
        } catch (_) {}
      }
      _snack(
          status == PasswordResetService.statusRejected
              ? 'Request rejected.'
              : 'Request updated.',
          status == PasswordResetService.statusRejected
              ? Colors.red
              : Colors.green);
      await _fetchRequests(silent: true);
    } catch (e) {
      _snack('Could not update. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  /// Approves the request so the person can continue straight into
  /// account recovery in the app. Records the admin + timestamp and
  /// opens a 30-minute approval window. No codes, no SMS.
  Future<void> _approveRequest(
      Map<String, dynamic> req, Map<String, dynamic>? account) async {
    final id = (req['id'] as num?)?.toInt();
    if (id == null || _busyAction) return;
    if (account == null) {
      _snack(
          'No matching account found. Verify the person before approving.',
          Colors.orange);
      return;
    }
    setState(() => _busyAction = true);
    try {
      final admin = await _adminLabel();
      final now = DateTime.now();
      await _client.from(PasswordResetService.table).update({
        'status': PasswordResetService.statusLinkSent,
        'token_expires_at':
            now.add(const Duration(minutes: PasswordResetService.tokenValidityMinutes)).toIso8601String(),
        'attempts': 0,
        'user_id': (account['id'] ?? '').toString(),
        'processed_by': admin,
        'processed_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }).eq('id', id);
      await _fetchRequests(silent: true);
      // 🔔 Notify the user of the approval (fire-and-forget).
      try {
        final targetUserId = (account['id'] ?? '').toString();
        if (targetUserId.isNotEmpty) {
          NotificationService.passwordResetDecided(
            requestId: id.toString(),
            userId: targetUserId,
            approved: true,
          );
        }
      } catch (_) {}
      _snack('Approved. The user can now continue in the app.',
          Colors.green);
    } catch (e) {
      _snack('Could not approve. Please try again. ($e)', Colors.red);
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
        title: Text('Password Reset Requests',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
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
              _headerCard(),
              const SizedBox(height: 12),
              _summaryGrid(),
              const SizedBox(height: 16),
              Text('Password Reset Requests',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 10),
              _searchBox(),
              const SizedBox(height: 10),
              _filterChips(),
              const SizedBox(height: 12),
              _requestList(),
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
            child: const Icon(Icons.lock_person_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Authentication',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Review account recovery requests from students and teachers.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _summaryGrid() {
    final cards = [
      _miniStat('Pending Requests', '${_count(PasswordResetService.statusPending)}',
          Icons.hourglass_top_rounded, const Color(0xFFF59E0B)),
      _miniStat('Link Sent', '${_count(PasswordResetService.statusLinkSent)}',
          Icons.send_rounded, const Color(0xFF1565C0)),
      _miniStat('Completed', '${_count(PasswordResetService.statusCompleted)}',
          Icons.verified_rounded, const Color(0xFF22C55E)),
      _miniStat('Total Requests', '${_requests.length}',
          Icons.folder_rounded, const Color(0xFF7B1FA2)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 112,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                    height: 1)),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6B7280))),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _search = v),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: '🔍 Search by name, role, date...',
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

  Widget _filterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in _filters)
          ChoiceChip(
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
            selectedColor: const Color(0xFF1565C0),
            labelStyle: GoogleFonts.poppins(
                color:
                    _filter == value ? Colors.white : const Color(0xFF374151)),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case PasswordResetService.statusPending:
        return const Color(0xFFF59E0B);
      case PasswordResetService.statusLinkSent:
        return const Color(0xFF1565C0);
      case PasswordResetService.statusCompleted:
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
                  ? 'The password_reset_requests table does not exist yet. Run the one-time setup SQL in Supabase, then pull to refresh.'
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
        child: Column(children: [
          Icon(Icons.mark_email_read_outlined,
              size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No reset requests found.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
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
      itemBuilder: (_, i) => _requestCard(items[i]),
    );
  }

  Widget _requestCard(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final color = _statusColor(status);
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
            child: Text(PasswordResetService.prettyStatus(status),
                style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            '${PasswordResetService.prettyRole(r['role']?.toString())}\nRequest: ${PasswordResetService.prettyType(r['request_type']?.toString())}\nSubmitted: ${PasswordResetService.prettyDate(r['created_at']?.toString())}',
            style: GoogleFonts.poppins(
                fontSize: 13, height: 1.6, color: Colors.grey.shade600)),
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
            child: Text('View Request',
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
            Text(rows[i].$2,
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
