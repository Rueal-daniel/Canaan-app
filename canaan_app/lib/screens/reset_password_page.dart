import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/password_reset_service.dart';
import '../widgets/animations.dart';
import 'recovery_chatbot_page.dart';

/// Login → Forgot Password? → Reset Password.
///
/// Two modes: submit a new reset request, or check an approval and
/// jump straight into account recovery.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _statusNameController = TextEditingController();

  String _role = PasswordResetService.roleStudent;
  String _requestType = PasswordResetService.typeBoth;
  String _checkRole = PasswordResetService.roleStudent;
  bool _isSubmitting = false;
  bool _isChecking = false;

  @override
  void dispose() {
    _nameController.dispose();
    _statusNameController.dispose();
    super.dispose();
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

  /// Best-effort account match for the admin's convenience only.
  /// The response never reveals whether anyone matched.
  Future<void> _submitRequest() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final name = _nameController.text.trim();
      String? userId;
      try {
        final table =
            _role == PasswordResetService.roleTeacher ? 'teachers' : 'students';
        final rows =
            await _client.from(table).select('id, full_name').limit(200);
        for (final r in (rows as List)) {
          if (PasswordResetService.norm((r as Map)['full_name']?.toString()) ==
              PasswordResetService.norm(name)) {
            userId = (r['id'] ?? '').toString();
            break;
          }
        }
      } catch (_) {}
      final insert = <String, dynamic>{
        'full_name': name,
        'role': _role,
        'request_type': _requestType,
        'status': PasswordResetService.statusPending,
      };
      if (userId != null && userId.isNotEmpty) insert['user_id'] = userId;
      await _client.from(PasswordResetService.table).insert(insert);
      if (!mounted) return;
      _nameController.clear();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
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
            Text('Reset request submitted successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Please wait while the Admin reviews your request.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13.5, color: Colors.grey.shade600)),
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
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      _snack('Could not submit. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _checkStatus() async {
    final name = _statusNameController.text.trim();
    if (name.isEmpty) {
      _snack('Enter your full name.', Colors.orange);
      return;
    }
    setState(() => _isChecking = true);
    try {
      final rows = await _client
          .from(PasswordResetService.table)
          .select('*')
          .eq('role', _checkRole)
          .order('created_at', ascending: false)
          .limit(100);
      Map<String, dynamic>? mine;
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        if (PasswordResetService.norm(m['full_name']?.toString()) ==
            PasswordResetService.norm(name)) {
          mine = m;
          break;
        }
      }
      if (!mounted) return;
      if (mine == null) {
        _snack('No recovery request found for that name.',
            Colors.orange);
        return;
      }
      final status = (mine['status'] ?? '').toString();
      if (status == PasswordResetService.statusPending) {
        _snack('Your request is waiting for Admin review. Please check back soon.',
            const Color(0xFF1565C0));
      } else if (status == PasswordResetService.statusLinkSent) {
        if (PasswordResetService.isExpired(mine)) {
          _snack('Your approval expired. Please contact the Admin to approve again.',
              Colors.orange);
        } else {
          // Approved — straight into the recovery chatbot.
          Navigator.push(
            context,
            SlidePageRoute(
                page: RecoveryChatbotPage(request: mine)),
          );
        }
      } else if (status == PasswordResetService.statusCompleted) {
        _snack('Your account is already recovered. You can log in now.',
            Colors.green);
      } else {
        _snack('Your request was not approved. Please contact the Admin.',
            Colors.red);
      }
    } catch (e) {
      _snack('Could not check. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isChecking = false);
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
        title: Text('Reset Password',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(),
            const SizedBox(height: 12),
            _requestCard(),
            const SizedBox(height: 16),
            _codeCard(),
          ],
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
            child: const Icon(Icons.lock_reset_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reset Password',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Recover your username or password with Admin help.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
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
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
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

  Widget _requestCard() {
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
        child: Form(
          key: _formKey,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request Account Recovery',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 14),
                _label('I am a...'),
                Row(children: [
                  Expanded(
                      child: _roleCard(PasswordResetService.roleStudent,
                          'Student', Icons.school_rounded)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _roleCard(PasswordResetService.roleTeacher,
                          'Teacher', Icons.co_present_rounded)),
                ]),
                const SizedBox(height: 14),
                _label('Full Name'),
                TextFormField(
                  controller: _nameController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _dec('Full Name', 'Enter your full name'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Full name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                _label('What do you want to recover?'),
                RadioGroup<String>(
                  groupValue: _requestType,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _requestType = v);
                  },
                  child: Column(children: [
                    for (final (v, t) in [
                      (PasswordResetService.typeUsername, 'Username'),
                      (PasswordResetService.typePassword, 'Password'),
                      (PasswordResetService.typeBoth, 'Both Username & Password'),
                    ])
                      RadioListTile<String>(
                        value: v,
                        title: Text(t,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF111827))),
                        activeColor: const Color(0xFF1565C0),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        dense: true,
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF1565C0)
                          .withValues(alpha: 0.5),
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
      ),
    );
  }

  Widget _roleCard(String value, String label, IconData icon) {
    final selected = _role == value;
    return GestureDetector(
      onTap: () => setState(() => _role = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1565C0).withValues(alpha: 0.08)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected
                  ? const Color(0xFF1565C0)
                  : Colors.grey.shade200,
              width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Icon(icon,
              color: selected
                  ? const Color(0xFF1565C0)
                  : Colors.grey.shade400,
              size: 26),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? const Color(0xFF1565C0)
                      : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _codeCard() {
    return FadeInSlide(
      index: 2,
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.mark_chat_read_rounded,
                color: Color(0xFF22C55E), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Already requested? Check approval',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
            ),
          ]),
          const SizedBox(height: 6),
          Text('If the Admin approved you, you go straight into account recovery.',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          _label('I am a...'),
          DropdownButtonFormField<String>(
            initialValue: _checkRole,
            style: GoogleFonts.poppins(
                fontSize: 14, color: const Color(0xFF111827)),
            decoration: _dec('Role', 'Select role'),
            items: const [
              DropdownMenuItem(
                  value: PasswordResetService.roleStudent,
                  child: Text('Student')),
              DropdownMenuItem(
                  value: PasswordResetService.roleTeacher,
                  child: Text('Teacher')),
            ],
            onChanged:
                _isChecking ? null : (v) => setState(() => _checkRole = v!),
          ),
          const SizedBox(height: 12),
          _label('Full Name'),
          TextField(
            controller: _statusNameController,
            style: GoogleFonts.poppins(fontSize: 14),
            decoration: _dec('Full Name', 'Enter your full name'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isChecking ? null : _checkStatus,
              icon: _isChecking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.chat_rounded, size: 20),
              label: Text('Check & Continue to Recovery',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF22C55E)
                    .withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
