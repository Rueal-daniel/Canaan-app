import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/credential_service.dart';
import '../services/notification_service.dart';
import '../services/session_service.dart';
import '../widgets/animations.dart';
import 'login_screen.dart';

/// Sidebar → Change Credentials (shared by Teacher & Student).
///
/// The user proves their recent credentials, picks what to change,
/// and submits a PENDING request — nothing changes until the Admin
/// approves. Passwords are never stored in the request table and
/// never shown to anyone; after approval of a password change the
/// user sets the new password here, written straight to their own
/// account row.
class ChangeCredentialsPage extends StatefulWidget {
  /// 'teacher' | 'student'
  final String role;
  final String fullName;
  const ChangeCredentialsPage({
    super.key,
    required this.role,
    this.fullName = '',
  });

  @override
  State<ChangeCredentialsPage> createState() => _ChangeCredentialsPageState();
}

class _ChangeCredentialsPageState extends State<ChangeCredentialsPage> {
  final _client = Supabase.instance.client;
  final _scrollController = ScrollController();

  final _recentUserController = TextEditingController();
  final _newUserController = TextEditingController();
  final _confirmUserController = TextEditingController();
  final _recentPassController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();
  final _setRecentController = TextEditingController();
  final _setNewController = TextEditingController();
  final _setConfirmController = TextEditingController();

  bool _obscureRecent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String _changeKind = CredentialService.typeUsername;
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _myRequests = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSettingPassword = false;
  String? _loadError;
  StreamSubscription? _realtimeSub;

  bool get _isTeacher => widget.role == CredentialService.roleTeacher;
  Color get _brand =>
      _isTeacher ? const Color(0xFF7C3AED) : const Color(0xFF0E9F6E);

  Map<String, dynamic>? get _pendingReq {
    for (final r in _myRequests) {
      if ((r['status'] ?? '') == CredentialService.statusPending) return r;
    }
    return null;
  }

  /// Approved password/both request still needing the new password.
  Map<String, dynamic>? get _approvedNeedingPassword {
    for (final r in _myRequests) {
      if ((r['status'] ?? '') != CredentialService.statusApproved) continue;
      final t = (r['change_type'] ?? '').toString();
      if (t == CredentialService.typePassword ||
          t == CredentialService.typeBoth) {
        return r;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _init();
    _subscribeRealtime();
  }

  Future<void> _init() async {
    await _loadAccount();
    await _fetchMine();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _recentUserController.dispose();
    _newUserController.dispose();
    _confirmUserController.dispose();
    _recentPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    _setRecentController.dispose();
    _setNewController.dispose();
    _setConfirmController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(CredentialService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchMine(silent: true);
          });
    } catch (_) {}
  }

  Future<void> _loadAccount() async {
    try {
      Map<String, dynamic>? row;
      try {
        final session = await SessionService.getSession();
        if (session != null && session.role == widget.role) {
          final res = await _client
              .from(CredentialService.userTable(widget.role))
              .select('id, username, password, full_name, section, email')
              .eq('id', session.userId)
              .maybeSingle();
          if (res != null) row = Map<String, dynamic>.from(res);
        }
      } catch (_) {}
      if (row == null && widget.fullName.isNotEmpty) {
        try {
          final res = await _client
              .from(CredentialService.userTable(widget.role))
              .select('id, username, password, full_name, section, email')
              .eq('full_name', widget.fullName)
              .limit(1);
          final list = List<Map<String, dynamic>>.from(res);
          if (list.isNotEmpty) row = list.first;
        } catch (_) {}
      }
      if (mounted) setState(() => _account = row);
    } catch (_) {}
  }

  Future<void> _fetchMine({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final me = _account?['id']?.toString() ?? '';
      final myName =
          (_account?['full_name'] ?? widget.fullName).toString();
      List<Map<String, dynamic>> mine = [];
      if (me.isNotEmpty) {
        try {
          final res = await _client
              .from(CredentialService.table)
              .select('*')
              .eq('user_id', me)
              .order('created_at', ascending: false);
          mine = List<Map<String, dynamic>>.from(res);
        } catch (_) {}
      }
      if (mine.isEmpty && myName.trim().isNotEmpty) {
        try {
          final res = await _client
              .from(CredentialService.table)
              .select('*')
              .eq('role', widget.role)
              .order('created_at', ascending: false)
              .limit(50);
          for (final r in (res as List)) {
            final m = Map<String, dynamic>.from(r as Map);
            if (CredentialService.norm(m['full_name']?.toString()) ==
                CredentialService.norm(myName)) {
              mine.add(m);
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      final prevPending = _pendingReq;
      setState(() {
        _myRequests = mine;
        _isLoading = false;
        _loadError = null;
      });
      // Realtime status transitions on the previously-pending request.
      if (silent && prevPending != null) {
        final id = (prevPending['id'] ?? '').toString();
        Map<String, dynamic>? now;
        for (final r in mine) {
          if ((r['id'] ?? '').toString() == id) {
            now = r;
            break;
          }
        }
        final st = (now?['status'] ?? '').toString();
        if (st == CredentialService.statusApproved) {
          _onApproved(now!);
        } else if (st == CredentialService.statusRejected) {
          final reason = (now?['rejection_reason'] ?? '').toString().trim();
          _decisionDialog(
            approved: false,
            message: reason.isEmpty
                ? 'Your credential change request was not approved. Please contact the Admin.'
                : 'Your request was not approved.\n\nReason: $reason',
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load your requests. Check your connection. ($e)';
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

  Future<bool> _usernameTaken(String username) async {
    final name = username.trim();
    if (name.isEmpty) return true;
    for (final t in ['teachers', 'students', 'admin']) {
      try {
        final rows = await _client
            .from(t)
            .select('id, username')
            .eq('username', name)
            .limit(1);
        if ((rows as List).isNotEmpty) {
          // Taken by someone else (ignore our own row).
          for (final r in rows) {
            final m = Map<String, dynamic>.from(r as Map);
            if ((m['id'] ?? '').toString() !=
                (_account?['id'] ?? '').toString()) {
              return true;
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  bool get _wantsUsername => _changeKind == CredentialService.typeUsername ||
      _changeKind == CredentialService.typeBoth;
  bool get _wantsPassword => _changeKind == CredentialService.typePassword ||
      _changeKind == CredentialService.typeBoth;

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;
    if (_account == null) {
      _snack('Could not identify your account. Please log in again.',
          Colors.red);
      return;
    }
    if (_pendingReq != null) {
      _snack(
          'You already have a credential change request waiting for Admin approval.',
          Colors.orange);
      return;
    }
    final currentUsername = (_account!['username'] ?? '').toString();
    final currentPassword = (_account!['password'] ?? '').toString();

    if (_wantsUsername) {
      final recent = _recentUserController.text.trim();
      final next = _newUserController.text.trim();
      final confirm = _confirmUserController.text.trim();
      if (recent.isEmpty || next.isEmpty || confirm.isEmpty) {
        _snack('Fill in all username fields.', Colors.orange);
        return;
      }
      if (recent != currentUsername) {
        _snack('Recent username is not correct.', Colors.red);
        return;
      }
      if (next == currentUsername) {
        _snack('New username must be different from the recent one.',
            Colors.orange);
        return;
      }
      if (next != confirm) {
        _snack('Confirm username does not match.', Colors.red);
        return;
      }
      if (next.length < 3) {
        _snack('New username must be at least 3 characters.', Colors.orange);
        return;
      }
    }

    if (_wantsPassword) {
      final recent = _recentPassController.text;
      final next = _newPassController.text;
      final confirm = _confirmPassController.text;
      if (recent.isEmpty || next.isEmpty || confirm.isEmpty) {
        _snack('Fill in all password fields.', Colors.orange);
        return;
      }
      if (recent != currentPassword) {
        _snack('Recent password is not correct.', Colors.red);
        return;
      }
      final err = CredentialService.validateNewPassword(next);
      if (err != null) {
        _snack(err, Colors.orange);
        return;
      }
      if (next != confirm) {
        _snack('Confirm password does not match.', Colors.red);
        return;
      }
      if (next == currentPassword) {
        _snack('New password must be different from the recent one.',
            Colors.orange);
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      // Re-check uniqueness right before insert (usernames only).
      if (_wantsUsername) {
        if (await _usernameTaken(_newUserController.text.trim())) {
          _snack('This username is already being used by another account.',
              Colors.red);
          return;
        }
      }
      final now = DateTime.now().toIso8601String();
      final insert = <String, dynamic>{
        'user_id': (_account!['id'] ?? '').toString(),
        'role': widget.role,
        'section': (_account!['section'] ?? '').toString(),
        'full_name': (_account!['full_name'] ?? '').toString(),
        'email': (_account!['email'] ?? '').toString(),
        'current_username': currentUsername,
        'change_type': _changeKind,
        'status': CredentialService.statusPending,
        'requested_at': now,
        'created_at': now,
        'updated_at': now,
      };
      if (_wantsUsername) {
        insert['requested_username'] = _newUserController.text.trim();
      }
      String requestId = '';
      try {
        final created = await _client
            .from(CredentialService.table)
            .insert(insert)
            .select('id')
            .single();
        requestId = (created['id'] ?? '').toString();
      } catch (_) {
        // Row may already exist despite the failed round-trip:
        // recover its id instead of submitting a duplicate.
        requestId = await NotificationService.recoverNewestId(
          table: CredentialService.table,
          match: {'user_id': (_account!['id'] ?? '').toString()},
        );
      }
      _clearForms();
      await _fetchMine(silent: true);
      // 🔔 Notify admins of the new request (fire-and-forget).
      if (requestId.isNotEmpty) {
        try {
          NotificationService.credentialRequestSubmitted(
            requestId: requestId,
            role: widget.role,
            fullName: (_account!['full_name'] ?? '').toString(),
          );
        } catch (_) {}
      }
      if (!mounted) return;
      _pendingDialog();
    } catch (e) {
      _snack('Could not submit. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _clearForms() {
    _recentUserController.clear();
    _newUserController.clear();
    _confirmUserController.clear();
    _recentPassController.clear();
    _newPassController.clear();
    _confirmPassController.clear();
  }

  void _pendingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                color: Color(0xFFF59E0B), size: 36),
          ),
          const SizedBox(height: 16),
          Text('Please Wait for Admin Approval',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              'Your credential change request has been submitted successfully. Please wait for Admin approval.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Request Status: Pending',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309))),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('OK',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  void _onApproved(Map<String, dynamic> req) {
    final t = (req['change_type'] ?? '').toString();
    final needsPassword = t == CredentialService.typePassword ||
        t == CredentialService.typeBoth;
    if (needsPassword) {
      _decisionDialog(
        approved: true,
        message:
            'Admin has approved your request. Now set your new password below — nothing changes until you save it.',
      );
    } else {
      _decisionDialog(
        approved: true,
        message:
            'Admin Has Successfully Approved Your Request.\n\nYour credential change has been successfully approved by Admin. You can now log in using your new credentials.',
        logoutAfter: true,
      );
    }
    if (mounted) setState(() {});
  }

  void _decisionDialog(
      {required bool approved,
      required String message,
      bool logoutAfter = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: approved
                  ? [const Color(0xFF22C55E), const Color(0xFF4ADE80)]
                  : [const Color(0xFFEF4444), const Color(0xFFF87171)]),
              shape: BoxShape.circle,
            ),
            child: Icon(
                approved
                    ? Icons.verified_rounded
                    : Icons.cancel_rounded,
                color: Colors.white,
                size: 36),
          ),
          const SizedBox(height: 16),
          Text(
              approved
                  ? 'Admin Has Successfully Approved Your Request'
                  : 'Request Update',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (logoutAfter) _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    approved ? const Color(0xFF22C55E) : const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(logoutAfter ? 'OK — Log Out' : 'OK',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await AuthService().logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// Post-approval step: the user sets the new password themselves.
  /// It is written straight to their own account row — never into
  /// the request table and never shown to the Admin.
  Future<void> _saveNewPassword() async {
    if (_isSettingPassword || _account == null) return;
    final recent = _setRecentController.text;
    final next = _setNewController.text;
    final confirm = _setConfirmController.text;
    if (recent.isEmpty || next.isEmpty || confirm.isEmpty) {
      _snack('Fill in all password fields.', Colors.orange);
      return;
    }
    if (recent != (_account!['password'] ?? '').toString()) {
      _snack('Recent password is not correct.', Colors.red);
      return;
    }
    final err = CredentialService.validateNewPassword(next);
    if (err != null) {
      _snack(err, Colors.orange);
      return;
    }
    if (next != confirm) {
      _snack('Confirm password does not match.', Colors.red);
      return;
    }
    if (next == (_account!['password'] ?? '').toString()) {
      _snack('New password must be different from the recent one.',
          Colors.orange);
      return;
    }
    setState(() => _isSettingPassword = true);
    try {
      await _client
          .from(CredentialService.userTable(widget.role))
          .update({'password': next}).eq(
              'id', (_account!['id'] ?? '').toString());
      _setRecentController.clear();
      _setNewController.clear();
      _setConfirmController.clear();
      await _loadAccount();
      if (!mounted) return;
      _decisionDialog(
        approved: true,
        message:
            'Your new password has been saved securely. Please log in again with your new credentials.',
        logoutAfter: true,
      );
    } catch (e) {
      _snack('Could not save. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSettingPassword = false);
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
        title: Text('Change Credentials',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadAccount();
          await _fetchMine();
        },
        color: _brand,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1565C0))),
                )
              else if (_loadError != null)
                _errorCard()
              else ...[
                if (_approvedNeedingPassword != null) ...[
                  _setPasswordCard(),
                  const SizedBox(height: 12),
                ],
                if (_pendingReq == null &&
                    _approvedNeedingPassword == null) ...[
                  _formCard(),
                  const SizedBox(height: 20),
                ],
                if (_pendingReq != null) _pendingCard(),
                if (_pendingReq != null) const SizedBox(height: 20),
                _historySection(),
              ],
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
          gradient: LinearGradient(
            colors: [_brand, _brand.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _brand.withValues(alpha: 0.3),
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
            child: const Icon(Icons.manage_accounts_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Change Your Username & Password',
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Choose what you want to change. Your request will require Admin approval before the new credentials become active.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
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
        const Icon(Icons.cloud_off_rounded,
            size: 48, color: Color(0xFFEF4444)),
        const SizedBox(height: 12),
        Text(_loadError ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style:
                GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _init,
          style: ElevatedButton.styleFrom(
            backgroundColor: _brand,
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

  InputDecoration _dec(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _brand, width: 2)),
    );
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

  Widget _typeSelector() {
    final options = [
      (CredentialService.typeUsername, 'Change Username',
          Icons.person_rounded),
      (CredentialService.typePassword, 'Change Password',
          Icons.lock_rounded),
      (CredentialService.typeBoth, 'Change Username & Password',
          Icons.manage_accounts_rounded),
    ];
    return Column(children: [
      _label('What would you like to change?'),
      for (final (v, t, icon) in options) ...[
        GestureDetector(
          onTap: () => setState(() => _changeKind = v),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: _changeKind == v
                  ? _brand.withValues(alpha: 0.08)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _changeKind == v ? _brand : Colors.grey.shade200,
                  width: _changeKind == v ? 2 : 1),
            ),
            child: Row(children: [
              Icon(icon,
                  color:
                      _changeKind == v ? _brand : Colors.grey.shade400,
                  size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _changeKind == v
                            ? _brand
                            : const Color(0xFF374151))),
              ),
              if (_changeKind == v)
                Icon(Icons.check_circle_rounded, color: _brand, size: 22),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _formCard() {
    return FadeInSlide(
      index: 1,
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
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _typeSelector(),
              const SizedBox(height: 8),
              if (_wantsUsername) ...[
                _label('Recent Username'),
                TextField(
                  controller: _recentUserController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _dec('Recent Username', 'Recent Username'),
                ),
                const SizedBox(height: 12),
                _label('New Username'),
                TextField(
                  controller: _newUserController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _dec('New Username', 'New Username'),
                ),
                const SizedBox(height: 12),
                _label('Confirm New Username'),
                TextField(
                  controller: _confirmUserController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration:
                      _dec('Confirm New Username', 'Confirm New Username'),
                ),
                const SizedBox(height: 12),
              ],
              if (_wantsPassword) ...[
                _label('Recent Password'),
                TextField(
                  controller: _recentPassController,
                  obscureText: _obscureRecent,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _dec('Recent Password', 'Recent Password')
                      .copyWith(
                          suffixIcon: IconButton(
                              icon: Icon(
                                  _obscureRecent
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 20),
                              onPressed: () => setState(() =>
                                  _obscureRecent = !_obscureRecent))),
                ),
                const SizedBox(height: 12),
                _label('New Password'),
                TextField(
                  controller: _newPassController,
                  obscureText: _obscureNew,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration:
                      _dec('New Password', 'New Password').copyWith(
                          suffixIcon: IconButton(
                              icon: Icon(
                                  _obscureNew
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 20),
                              onPressed: () => setState(
                                  () => _obscureNew = !_obscureNew))),
                ),
                const SizedBox(height: 12),
                _label('Confirm New Password'),
                TextField(
                  controller: _confirmPassController,
                  obscureText: _obscureConfirm,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _dec(
                          'Confirm New Password', 'Confirm New Password')
                      .copyWith(
                          suffixIcon: IconButton(
                              icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  size: 20),
                              onPressed: () => setState(() =>
                                  _obscureConfirm = !_obscureConfirm))),
                ),
                const SizedBox(height: 6),
                Text('At least 6 characters. Your passwords are never shown to the Admin.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 12),
              ],
              if (_isSubmitting) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    color: _brand,
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _brand.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text('Submit Request',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
      ),
    );
  }

  Widget _pendingCard() {
    final p = _pendingReq!;
    return FadeInSlide(
      index: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                color: Color(0xFFB45309), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'You already have a credential change request waiting for Admin approval.',
                      style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1F2937))),
                  const SizedBox(height: 6),
                  Text(
                      '${CredentialService.prettyShortType(p['change_type']?.toString())} • ${CredentialService.prettyDate(p['created_at']?.toString())} • Pending',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, color: Colors.grey.shade600)),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _setPasswordCard() {
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.verified_rounded,
                    color: Color(0xFF22C55E), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Approved — set your new password',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                  'Your password change was approved. Save the new password now — it goes straight to your account and is never shown to the Admin.',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade600)),
              const SizedBox(height: 14),
              _label('Recent Password'),
              TextField(
                controller: _setRecentController,
                obscureText: true,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _dec('Recent Password', 'Recent Password'),
              ),
              const SizedBox(height: 12),
              _label('New Password'),
              TextField(
                controller: _setNewController,
                obscureText: true,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _dec('New Password', 'New Password'),
              ),
              const SizedBox(height: 12),
              _label('Confirm New Password'),
              TextField(
                controller: _setConfirmController,
                obscureText: true,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration:
                    _dec('Confirm New Password', 'Confirm New Password'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      _isSettingPassword ? null : _saveNewPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF22C55E)
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSettingPassword
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text('Save New Password',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
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

  Widget _historySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('My Credential Requests (${_myRequests.length})',
          style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827))),
      const SizedBox(height: 10),
      if (_myRequests.isEmpty)
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18)),
          child: Text('No requests yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade500)),
        )
      else
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _myRequests.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final r = _myRequests[i];
            final st = (r['status'] ?? '').toString();
            final color = _statusColor(st);
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            CredentialService.prettyShortType(
                                r['change_type']?.toString()),
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF111827))),
                        const SizedBox(height: 2),
                        Text(
                            CredentialService.prettyShortDate(
                                r['created_at']?.toString()),
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(CredentialService.prettyStatus(st),
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ]),
            );
          },
        ),
    ]);
  }
}
