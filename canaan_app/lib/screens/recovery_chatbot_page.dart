import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/password_reset_service.dart';

/// "Canaan Account Recovery" chatbot.
///
/// Opened with an Admin-approved reset request. Verifies the full
/// name against that request, then dynamically shows only the
/// recovery form(s) matching the original request (username /
/// password / both). Approvals expire after 30 minutes and name
/// checks lock after 5 wrong attempts. Old passwords are never shown.
class RecoveryChatbotPage extends StatefulWidget {
  final Map<String, dynamic> request;
  const RecoveryChatbotPage({super.key, required this.request});

  @override
  State<RecoveryChatbotPage> createState() => _RecoveryChatbotPageState();
}

class _ChatMsg {
  final bool bot;
  final String text;
  _ChatMsg(this.bot, this.text);
}

class _RecoveryChatbotPageState extends State<RecoveryChatbotPage> {
  final _client = Supabase.instance.client;
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _newUserController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();

  final List<_ChatMsg> _messages = [];
  bool _typing = false;
  bool _awaitingName = true;
  bool _verified = false;
  bool _busy = false;
  bool _done = false;
  bool _usernameOk = false;
  bool _bothPasswordStep = false;

  Map<String, dynamic>? _request;
  String? _accountId;

  String get _requestType =>
      (_request?['request_type'] ?? '').toString().toLowerCase();
  bool get _wantsUsername => _requestType == PasswordResetService.typeUsername ||
      _requestType == PasswordResetService.typeBoth;
  bool get _wantsPassword => _requestType == PasswordResetService.typePassword ||
      _requestType == PasswordResetService.typeBoth;
  bool get _isBoth => _requestType == PasswordResetService.typeBoth;

  @override
  void initState() {
    super.initState();
    _botSay('Welcome back! 👋');
    _botSay(
        'Your account recovery request has been approved by the Admin.');
    _botSay('Before we continue, I need to verify your identity.');
    _botSay('Please enter your full name.');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _newUserController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _botSay(String text) {
    setState(() => _messages.add(_ChatMsg(true, text)));
    _scrollDown();
  }

  void _userSay(String text) {
    setState(() => _messages.add(_ChatMsg(false, text)));
    _scrollDown();
  }

  Future<void> _setTyping(bool v) async {
    if (!mounted) return;
    setState(() => _typing = v);
    _scrollDown();
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

  // -- verification -------------------------------------------------------------

  Future<void> _submitName() async {
    final name = _inputController.text.trim();
    if (name.isEmpty || _busy || _done) return;
    _userSay(name);
    _inputController.clear();
    setState(() {
      _awaitingName = false;
      _busy = true;
    });
    await _setTyping(true);
    _botSay('🔄 Verifying your information...');
    await Future.delayed(const Duration(milliseconds: 900));
    try {
      // Re-read the request fresh — its status may have changed.
      final reqId = (widget.request['id'] as num?)?.toInt();
      if (reqId == null) {
        await _failVerify();
        return;
      }
      final row = await _client
          .from(PasswordResetService.table)
          .select('*')
          .eq('id', reqId)
          .maybeSingle();
      if (row == null) {
        await _failVerify();
        return;
      }
      final req = Map<String, dynamic>.from(row);
      final status = (req['status'] ?? '').toString();
      if (status != PasswordResetService.statusLinkSent) {
        await _failVerify(consumed: true);
        return;
      }
      if (PasswordResetService.isExpired(req)) {
        await _failVerify(
            message:
                'This approval has expired. Please ask the Admin to approve again.');
        return;
      }
      if (PasswordResetService.isLocked(req)) {
        await _failVerify(
            message:
                'Too many wrong attempts. Please ask the Admin for help.');
        return;
      }
      final okName = PasswordResetService.norm(
              req['full_name']?.toString()) ==
          PasswordResetService.norm(name);
      if (!okName) {
        try {
          final id = (req['id'] as num).toInt();
          final attempts = (req['attempts'] is num)
              ? (req['attempts'] as num).toInt()
              : int.tryParse('${req['attempts']}') ?? 0;
          await _client.from(PasswordResetService.table).update(
              {'attempts': attempts + 1}).eq('id', id);
        } catch (_) {}
        await _failVerify();
        return;
      }
      final role = (req['role'] ?? '').toString();
      final accountId = await _resolveAccountId(
          role, req['full_name']?.toString() ?? name,
          req['user_id']?.toString() ?? '');
      if (accountId == null || accountId.isEmpty) {
        await _failVerify(
            message:
                'We could not find your account. Please contact the Admin.');
        return;
      }
      _request = req;
      _accountId = accountId;
      await _setTyping(false);
      if (!mounted) return;
      setState(() => _busy = false);
      _botSay('✅ Identity verified successfully!');
      _botSay('You can now update your account.');
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() => _verified = true);
      if (_isBoth) {
        _botSay("No problem! Let's update both your username and password.");
        _botSay('Step 1 — choose a new username.');
      } else if (_wantsUsername) {
        _botSay("Let's create a new username for your account.");
      } else {
        _botSay("Let's create a new password for your account.");
      }
      _scrollDown();
    } catch (_) {
      _failVerify();
    }
  }

  Future<void> _failVerify({String? message, bool consumed = false}) async {
    await _setTyping(false);
    if (!mounted) return;
    setState(() => _busy = false);
    _botSay(message ??
        (consumed
            ? 'This approval is no longer valid. Please contact the Admin.'
            : 'Verification failed. Check your full name, then try again.'));
    if (!consumed) {
      if (mounted) setState(() => _awaitingName = true);
    } else {
      _botSay('You can close this page.');
      if (mounted) setState(() => _done = true);
    }
  }

  Future<String?> _resolveAccountId(
      String role, String fullName, String hintId) async {
    final table =
        role == PasswordResetService.roleTeacher ? 'teachers' : 'students';
    if (hintId.isNotEmpty) {
      try {
        final row = await _client
            .from(table)
            .select('id')
            .eq('id', hintId)
            .maybeSingle();
        if (row != null) return (row['id'] ?? '').toString();
      } catch (_) {}
    }
    try {
      final rows = await _client.from(table).select('id, full_name').limit(300);
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        if (PasswordResetService.norm(m['full_name']?.toString()) ==
            PasswordResetService.norm(fullName)) {
          return (m['id'] ?? '').toString();
        }
      }
    } catch (_) {}
    return null;
  }

  String get _roleTable =>
      ((_request?['role'] ?? '').toString() ==
              PasswordResetService.roleTeacher)
          ? 'teachers'
          : 'students';

  Future<bool> _usernameTaken(String username) async {
    final name = username.trim();
    if (name.isEmpty) return true;
    for (final t in ['teachers', 'students']) {
      try {
        final rows = await _client
            .from(t)
            .select('id, username')
            .eq('username', name)
            .limit(1);
        if ((rows as List).isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  // -- username step ---------------------------------------------------------------

  Future<void> _submitUsername({required bool bothContinue}) async {
    final name = _newUserController.text.trim();
    if (name.isEmpty || _busy || _accountId == null) {
      _snack('Enter your new username.', Colors.orange);
      return;
    }
    if (name.length < 3) {
      _snack('Username must be at least 3 characters.', Colors.orange);
      return;
    }
    setState(() => _busy = true);
    try {
      if (await _usernameTaken(name)) {
        _botSay('This username is not available. Please choose another username.');
        return;
      }
      if (bothContinue) {
        if (!mounted) return;
        setState(() => _usernameOk = true);
        _botSay('Username is available! ✅');
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        setState(() => _bothPasswordStep = true);
        _botSay('Step 2 — create your new password.');
        return;
      }
      await _client
          .from(_roleTable)
          .update({'username': name}).eq('id', _accountId!);
      _botSay('✅ Your username has been successfully updated.');
      await _finish();
    } catch (e) {
      _snack('Could not update. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- password step -----------------------------------------------------------------

  Future<void> _submitPassword() async {
    final p1 = _newPassController.text;
    final p2 = _confirmPassController.text;
    if (p1.isEmpty || p2.isEmpty || _busy || _accountId == null) {
      _snack('Enter and confirm your new password.', Colors.orange);
      return;
    }
    if (p1.length < 6) {
      _snack('Password must be at least 6 characters.', Colors.orange);
      return;
    }
    if (p1 != p2) {
      _snack('Passwords do not match.', Colors.orange);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isBoth) {
        final name = _newUserController.text.trim();
        await _client
            .from(_roleTable)
            .update({'username': name}).eq('id', _accountId!);
      }
      await _client
          .from(_roleTable)
          .update({'password': p1}).eq('id', _accountId!);
      if (_isBoth) {
        _botSay('🎉 Your account has been successfully recovered!');
        _botSay(
            'Your username has been updated and your new password has been saved securely. You can now log in to your Canaan account.');
      } else {
        _botSay('✅ Your password has been successfully reset.');
      }
      await _finish();
    } catch (e) {
      _snack('Could not reset. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Marks the request completed and clears the approval so it
  /// cannot be reused.
  Future<void> _finish() async {
    try {
      final id = (_request?['id'] as num?)?.toInt();
      if (id != null) {
        final now = DateTime.now().toIso8601String();
        await _client.from(PasswordResetService.table).update({
          'status': PasswordResetService.statusCompleted,
          'completed_at': now,
          'updated_at': now,
          'user_id': _accountId,
        }).eq('id', id);
        // Clear any legacy token field when the column exists.
        try {
          await _client.from(PasswordResetService.table).update(
              {'reset_token': null}).eq('id', id);
        } catch (_) {}
      }
    } catch (_) {}
    _newUserController.clear();
    _newPassController.clear();
    _confirmPassController.clear();
    if (mounted) setState(() => _done = true);
    _scrollDown();
  }

  Future<void> _close() async {
    // Leave nothing sensitive behind; the token is already consumed.
    _newUserController.clear();
    _newPassController.clear();
    _confirmPassController.clear();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF1F8),
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
          const CircleAvatar(
            radius: 15,
            backgroundColor: Colors.white24,
            child: Text('🤖', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Canaan Assistant',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 16)),
          ),
        ]),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: const Color(0xFF0D47A1).withValues(alpha: 0.06),
          child: Text('Canaan Account Recovery • secure session',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_typing ? 1 : 0),
            itemBuilder: (_, i) {
              if (_typing && i == _messages.length) {
                return const _BotRow(child: _TypingDots());
              }
              final m = _messages[i];
              return m.bot
                  ? _BotRow(
                      child: Text(m.text,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              height: 1.5,
                              color: const Color(0xFF1F2937))))
                  : _UserRow(
                      child: Text(m.text,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              height: 1.5,
                              color: Colors.white)));
            },
          ),
        ),
        _bottomArea(),
      ]),
    );
  }

  Widget _bottomArea() {
    if (_done) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _close,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text('Close',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }
    if (_verified && _request != null) return _recoveryForms();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        color: Colors.white,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              enabled: _awaitingName && !_busy,
              onSubmitted: (_) => _submitName(),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter your full name',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF1565C0),
            child: IconButton(
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
              onPressed: _busy ? null : _submitName,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _recoveryForms() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black12, blurRadius: 12, offset: Offset(0, -3))
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text('What would you like to update?',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                const SizedBox(height: 12),
                if (_wantsUsername &&
                    (!_isBoth || !_bothPasswordStep)) ...[
                  _miniLabel(_isBoth
                      ? 'Step 1 — New Username'
                      : 'Create New Username'),
                  TextField(
                    controller: _newUserController,
                    enabled: !_busy && !_usernameOk,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: _miniDec('Enter your new username'),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _submitUsername(
                              bothContinue: _isBoth),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Text(_isBoth ? 'Continue' : 'Update Username',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                if (_wantsPassword &&
                    (!_isBoth || _bothPasswordStep)) ...[
                  if (_isBoth) const SizedBox(height: 6),
                  _miniLabel(_isBoth
                      ? 'Step 2 — New Password'
                      : 'Create New Password'),
                  TextField(
                    controller: _newPassController,
                    obscureText: true,
                    enabled: !_busy,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: _miniDec('New Password'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmPassController,
                    obscureText: true,
                    enabled: !_busy,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: _miniDec('Confirm New Password'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'Use at least 6 characters. Never share your password.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submitPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Text(_isBoth ? 'Reset Account' : 'Reset Password',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ]),
        ),
      ),
    );
  }

  Widget _miniLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  InputDecoration _miniDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
    );
  }
}

class _BotRow extends StatelessWidget {
  final Widget child;
  const _BotRow({required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 48),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: Color(0xFF1565C0),
          child: Text('🤖', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: const Radius.circular(4)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: child,
          ),
        ),
      ]),
    );
  }
}

class _UserRow extends StatelessWidget {
  final Widget child;
  const _UserRow({required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 48),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: const Radius.circular(4)),
            ),
            child: child,
          ),
        ),
      ]),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> {
  int _tick = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _tick = (_tick + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('.' * (_tick + 1),
        style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500));
  }
}
