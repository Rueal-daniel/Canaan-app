import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../services/prayer_request_service.dart';
import '../services/linked_student_service.dart';
import '../services/session_service.dart';
import 'animations.dart';

/// Shared Prayer Request board used by the Admin, Teacher and Student
/// pages (identical behavior everywhere — one shared community feed).
///
/// Two tabs: ➕ Add Prayer Request (any role submits; identity is taken
/// from the logged-in account, never typed) and 🙏 Prayer Request
/// Details (search + role filter + newest/oldest sort, realtime).
/// ONLY admins get Reply / Edit Reply / Delete Reply controls; owners
/// may delete their own request and admins may delete any request.
/// Tapping a prayer notification deep-links here with [focusRequestId],
/// which scrolls to and highlights that exact card.
class PrayerRequestBoard extends StatefulWidget {
  final String role;
  final String hintUserId;
  final String hintFullName;
  final Color accent;
  final int? focusRequestId;

  const PrayerRequestBoard({
    super.key,
    required this.role,
    this.hintUserId = '',
    this.hintFullName = '',
    this.accent = const Color(0xFF1565C0),
    this.focusRequestId,
  });

  @override
  State<PrayerRequestBoard> createState() => _PrayerRequestBoardState();
}

class _PrayerRequestBoardState extends State<PrayerRequestBoard>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late final TabController _tabs;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _searchController = TextEditingController();

  String _userId = '';
  String _displayName = '';
  bool get _isAdmin =>
      PrayerRequestService.isAdmin(widget.role);

  bool _isSubmitting = false;
  bool _isLoading = true;
  String? _loadError;

  List<Map<String, dynamic>> _requests = [];
  Map<int, Map<String, dynamic>> _repliesByRequest = {};

  String _search = '';
  String _roleFilter = '';
  bool _newestFirst = true;

  int? _pendingFocus;
  int? _highlightId;
  Timer? _highlightTimer;
  final Map<int, GlobalKey> _cardKeys = {};
  final List<StreamSubscription> _realtimeSubs = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _userId = widget.hintUserId;
    _displayName = widget.hintFullName;
    _pendingFocus = widget.focusRequestId;
    _resolveIdentity();
    _fetchAll();
    _subscribeRealtime();
  }

  @override
  void didUpdateWidget(PrayerRequestBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequestId != null &&
        widget.focusRequestId != oldWidget.focusRequestId) {
      _pendingFocus = widget.focusRequestId;
      _focusIfPresent();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _titleController.dispose();
    _detailsController.dispose();
    _searchController.dispose();
    _highlightTimer?.cancel();
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  String get _profileTable {
    switch (PrayerRequestService.normalizeRole(widget.role)) {
      case PrayerRequestService.roleAdmin:
        return 'admin';
      case PrayerRequestService.roleTeacher:
        return 'teachers';
      default:
        return 'students';
    }
  }

  /// Identity comes from the logged-in account — name/role/user-id are
  /// never typed into the form. For students the VERIFIED active (linked)
  /// student is used so posts and reply notifications belong to the
  /// dashboard being viewed.
  Future<void> _resolveIdentity() async {
    var uid = widget.hintUserId;
    var name = widget.hintFullName;
    final isStudent =
        PrayerRequestService.normalizeRole(widget.role) == 'student';
    if (isStudent && uid.trim().isEmpty) {
      try {
        uid = await LinkedStudentService.effectiveStudentId();
      } catch (_) {}
    }
    try {
      final session = await SessionService.getSession();
      if (session != null &&
          session.role.trim().toLowerCase() ==
              PrayerRequestService.normalizeRole(widget.role) &&
          session.userId.isNotEmpty) {
        uid = session.userId;
      }
    } catch (_) {}
    if (uid.isNotEmpty) {
      try {
        final row = await _client
            .from(_profileTable)
            .select('id, full_name')
            .eq('id', uid)
            .maybeSingle();
        final n = (row?['full_name'] ?? '').toString().trim();
        if (n.isNotEmpty) name = n;
      } catch (_) {}
    }
    if (uid.isEmpty && name.trim().isNotEmpty) {
      try {
        final row = await _client
            .from(_profileTable)
            .select('id, full_name')
            .eq('full_name', name.trim())
            .limit(1)
            .maybeSingle();
        final id = (row?['id'] ?? '').toString();
        if (id.isNotEmpty) uid = id;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _userId = uid;
        _displayName = name;
      });
    }
  }

  void _subscribeRealtime() {
    for (final t in [
      PrayerRequestService.requestsTable,
      PrayerRequestService.repliesTable,
    ]) {
      try {
        _realtimeSubs.add(_client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
          if (mounted) _fetchAll(silent: true);
        }));
      } catch (_) {}
    }
  }

  Future<void> _fetchAll({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final before = _requests
          .map(PrayerRequestService.requestIdOf)
          .where((id) => id >= 0)
          .toSet();
      final results = await Future.wait([
        _client
            .from(PrayerRequestService.requestsTable)
            .select('*')
            .order('created_at', ascending: false),
        _client
            .from(PrayerRequestService.repliesTable)
            .select('*'),
      ]);
      final requests =
          List<Map<String, dynamic>>.from(results[0] as List);
      final replies =
          List<Map<String, dynamic>>.from(results[1] as List);
      final byRequest = <int, Map<String, dynamic>>{};
      for (final r in replies) {
        final pid = (r['prayer_request_id'] as num?)?.toInt();
        if (pid != null) byRequest[pid] = r;
      }
      if (mounted) {
        final hadBefore = before.isNotEmpty;
        final fresh = requests
            .where((r) =>
                !before.contains(PrayerRequestService.requestIdOf(r)))
            .toList();
        setState(() {
          _requests = requests;
          _repliesByRequest = byRequest;
          _isLoading = false;
          _loadError = null;
        });
        if (silent && hadBefore && fresh.isNotEmpty) {
          _snack(
            '🙏 ${fresh.length == 1 ? 'New prayer request shared' : '${fresh.length} new prayer requests shared'}',
            widget.accent,
          );
        }
        _focusIfPresent();
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load prayer requests. Check your connection and try again. ($e)';
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

  // -- submit ------------------------------------------------------------------------

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final now = DateTime.now().toIso8601String();
      final name =
          _displayName.trim().isEmpty ? 'Canaan Member' : _displayName.trim();
      final savedTitle = _titleController.text.trim();
      final created = await _client
          .from(PrayerRequestService.requestsTable)
          .insert({
            'user_id': _userId,
            'full_name': name,
            'role': PrayerRequestService.normalizeRole(widget.role),
            'title': savedTitle,
            'description': _detailsController.text.trim(),
            'updated_at': now,
          })
          .select('id')
          .single();
      final newId = (created['id'] as num?)?.toInt();
      // Clear only on success — a failure keeps the typed text.
      _titleController.clear();
      _detailsController.clear();
      _tabs.animateTo(1);
      await _fetchAll(silent: true);
      _snack('Prayer Request Submitted Successfully', Colors.green);
      if (newId != null) {
        try {
          await NotificationService.prayerRequestSubmitted(
            requestId: newId.toString(),
            title: savedTitle,
          );
        } catch (_) {}
      }
    } catch (e) {
      _snack(
          'Unable to submit your prayer request. Please try again. ($e)',
          Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // -- admin reply ---------------------------------------------------------------------

  void _openReplyDialog(Map<String, dynamic> request) {
    if (!_isAdmin) return;
    final id = PrayerRequestService.requestIdOf(request);
    final existing = _repliesByRequest[id];
    final controller =
        TextEditingController(text: (existing?['comment'] ?? '').toString());
    var sending = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('💬 Reply to Prayer Request',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 16.5)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prayer Request:',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text((request['title'] ?? '').toString(),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 12),
                Text('Admin Comment',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  enabled: !sending,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Write your reply here...',
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400, fontSize: 13.5),
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
                        borderSide: BorderSide(
                            color: widget.accent, width: 2)),
                  ),
                ),
                if (sending) ...[
                  const SizedBox(height: 10),
                  Text('Sending Reply...',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.grey.shade600)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style:
                      GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: sending
                  ? null
                  : () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Please write your reply first.',
                                style: GoogleFonts.poppins()),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      setDialog(() => sending = true);
                      final ok = await _saveReply(request, text);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (ok) {
                        _snack('✅ Reply sent.', Colors.green);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Send Reply',
                      style:
                          GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Inserts or updates the single reply, then notifies the original
  /// sender. Returns true on success (text is kept on failure).
  Future<bool> _saveReply(
      Map<String, dynamic> request, String text) async {
    final id = PrayerRequestService.requestIdOf(request);
    try {
      final now = DateTime.now().toIso8601String();
      final adminName = _displayName.trim().isEmpty
          ? 'Canaan Administrator'
          : _displayName.trim();
      final existing = _repliesByRequest[id];
      if (existing == null) {
        await _client
            .from(PrayerRequestService.repliesTable)
            .insert({
          'prayer_request_id': id,
          'admin_id': _userId,
          'admin_name': adminName,
          'comment': text,
          'updated_at': now,
        });
      } else {
        await _client
            .from(PrayerRequestService.repliesTable)
            .update({'comment': text, 'updated_at': now}).eq(
                'id', (existing['id'] as num).toInt());
      }
      await _fetchAll(silent: true);
      try {
        await NotificationService.prayerReplySent(
          requestId: id.toString(),
          senderUserId:
              PrayerRequestService.userIdOf(request),
        );
      } catch (_) {}
      return true;
    } catch (e) {
      _snack('Could not send reply. Please try again. ($e)', Colors.red);
      return false;
    }
  }

  Future<void> _deleteReply(Map<String, dynamic> request) async {
    if (!_isAdmin) return;
    final id = PrayerRequestService.requestIdOf(request);
    final reply = _repliesByRequest[id];
    final replyId = (reply?['id'] as num?)?.toInt();
    if (replyId == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Reply?',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Remove the admin reply from this prayer request?',
            style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style:
                    GoogleFonts.poppins(color: Colors.grey.shade600)),
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
    try {
      await _client
          .from(PrayerRequestService.repliesTable)
          .delete()
          .eq('id', replyId);
      await _fetchAll(silent: true);
      _snack('Reply deleted.', Colors.green);
    } catch (e) {
      _snack('Could not delete reply. ($e)', Colors.red);
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> request) async {
    final id = PrayerRequestService.requestIdOf(request);
    final title = (request['title'] ?? 'this prayer request').toString();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Prayer Request?',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Delete "$title"? Its admin reply goes with it.',
            style: GoogleFonts.poppins(
                fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style:
                    GoogleFonts.poppins(color: Colors.grey.shade600)),
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
    try {
      // The reply (if any) is removed by ON DELETE CASCADE — no orphans.
      await _client
          .from(PrayerRequestService.requestsTable)
          .delete()
          .eq('id', id);
      await _fetchAll(silent: true);
      _snack('Prayer request deleted.', Colors.green);
    } catch (e) {
      _snack('Could not delete. Please try again. ($e)', Colors.red);
    }
  }

  // -- deep-link focus ---------------------------------------------------------------------

  void _focusIfPresent() {
    final target = _pendingFocus;
    if (target == null || _requests.isEmpty) return;
    final exists = _requests.any(
        (r) => PrayerRequestService.requestIdOf(r) == target);
    if (!exists) return;
    _pendingFocus = null;
    if (_tabs.index != 1) _tabs.animateTo(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _cardKeys[target];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      }
      setState(() => _highlightId = target);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _highlightId = null);
      });
    });
  }

  // -- build --------------------------------------------------------------------------------------

  List<Map<String, dynamic>> get _visible {
    final filtered = PrayerRequestService.applySearchFilter(
      _requests,
      search: _search,
      roleFilter: _roleFilter,
    );
    return PrayerRequestService.sorted(
      filtered,
      newestFirst: _newestFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EEF6)),
          ),
          child: TabBar(
            controller: _tabs,
            labelColor: widget.accent,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: widget.accent,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: '➕ Add Prayer Request'),
              Tab(text: '🙏 Prayer Request Details'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _addTab(),
              _detailsTab(),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: widget.accent, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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

  Widget _addTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchAll(),
      color: widget.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: FadeInSlide(
          index: 0,
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
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('🙏',
                            style: GoogleFonts.poppins(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Add Prayer Request',
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('Prayer Request Title'),
                  TextFormField(
                    controller: _titleController,
                    enabled: !_isSubmitting,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: _inputDecoration(
                        'Enter prayer request title'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty
                            ? 'Please enter a title'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Prayer Request Details'),
                  TextFormField(
                    controller: _detailsController,
                    enabled: !_isSubmitting,
                    maxLines: 5,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: _inputDecoration(
                        'Write your prayer request here...'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty
                            ? 'Please write your prayer request'
                            : null,
                  ),
                  const SizedBox(height: 18),
                  if (_isSubmitting) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        color: widget.accent,
                        backgroundColor:
                            const Color(0xFFF1F5F9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Submitting Prayer Request...',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5))
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text('Submit Prayer Request',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: widget.accent
                            .withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchAll(),
      color: widget.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: '🔍 Search title or name...',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    color: widget.accent),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear_rounded, size: 20),
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
                    borderSide:
                        BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: widget.accent, width: 2)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final o in [
                          ('', 'All'),
                          (PrayerRequestService.roleAdmin, 'Admin'),
                          (PrayerRequestService.roleTeacher,
                              'Teacher'),
                          (PrayerRequestService.roleStudent,
                              'Student'),
                        ])
                          Padding(
                            padding:
                                const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(o.$2,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12.5)),
                              selected: _roleFilter == o.$1,
                              selectedColor: widget.accent
                                  .withValues(alpha: 0.15),
                              checkmarkColor: widget.accent,
                              onSelected: (_) => setState(
                                  () => _roleFilter = o.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.grey.shade200),
                  ),
                  child: DropdownButton<bool>(
                    value: _newestFirst,
                    underline: const SizedBox.shrink(),
                    icon: Icon(Icons.sort_rounded,
                        size: 18, color: widget.accent),
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: const Color(0xFF111827)),
                    items: [
                      DropdownMenuItem(
                        value: true,
                        child: Text('Newest First',
                            style: GoogleFonts.poppins(
                                fontSize: 12.5)),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Oldest First',
                            style: GoogleFonts.poppins(
                                fontSize: 12.5)),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _newestFirst = v);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _feedBody(),
          ],
        ),
      ),
    );
  }

  Widget _feedBody() {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: widget.accent),
              const SizedBox(height: 12),
              Text('Loading Prayer Requests...',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
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
            onPressed: () => _fetchAll(),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accent,
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
            const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('🙏', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No Prayer Requests Yet',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 6),
          Text(
              'Be the first to share a prayer request with the Canaan family.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _tabs.animateTo(0),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
            child: Text('Add Prayer Request',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
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

  Widget _requestCard(Map<String, dynamic> request) {
    final id = PrayerRequestService.requestIdOf(request);
    final key = _cardKeys.putIfAbsent(id, () => GlobalKey());
    final reply = _repliesByRequest[id];
    final highlighted = _highlightId == id;
    final canDelete = PrayerRequestService.canDeleteRequest(
      request,
      role: widget.role,
      userId: _userId,
    );
    return Container(
      key: key,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? widget.accent
              : const Color(0xFFF1F5F9),
          width: highlighted ? 2 : 1,
        ),
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
          Text('🙏 ${(request['title'] ?? '').toString()}',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 8),
          Text((request['description'] ?? '').toString(),
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  height: 1.6,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 10),
          Text(
            '— ${(request['full_name'] ?? '').toString().trim().isEmpty ? 'Canaan Member' : (request['full_name'] ?? '').toString()}'
            ' · ${PrayerRequestService.prettyRole(request['role']?.toString())}',
            style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            '📅 ${PrayerRequestService.prettyDate(request['created_at']?.toString())}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: reply == null
                ? Text('💬 Admin Reply\nNo reply yet',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.6,
                        color: Colors.grey.shade500))
                : Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('💬 Admin Reply',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: widget.accent)),
                      const SizedBox(height: 6),
                      Text((reply['comment'] ?? '').toString(),
                          style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              height: 1.6,
                              color: const Color(0xFF374151))),
                      const SizedBox(height: 8),
                      Text(
                        '— ${(reply['admin_name'] ?? '').toString().trim().isEmpty ? 'Canaan Administrator' : (reply['admin_name'] ?? '').toString()}'
                        ' · Canaan Administrator',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600),
                      ),
                      Text(
                        '📅 ${PrayerRequestService.prettyDate(reply['created_at']?.toString())}',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade500),
                      ),
                    ],
                  ),
          ),
          // Controls: admin-only reply tools + owner/admin delete.
          if (_isAdmin || canDelete) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => _openReplyDialog(request),
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 16),
                    label: Text(
                        reply == null ? 'Reply / Comment' : 'Edit Reply',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.accent,
                      side: BorderSide(color: widget.accent),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                if (_isAdmin && reply != null)
                  TextButton.icon(
                    onPressed: () => _deleteReply(request),
                    icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: Colors.red),
                    label: Text('Delete Reply',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5, color: Colors.red)),
                  ),
                if (canDelete)
                  TextButton.icon(
                    onPressed: () => _deleteRequest(request),
                    icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: Colors.red),
                    label: Text(
                        _isAdmin
                            ? 'Delete Request'
                            : 'Delete My Request',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5, color: Colors.red)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
