import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/complaint_service.dart';
import '../services/language_service.dart';
import '../widgets/animations.dart';

/// Login → Complaint. PUBLIC form — no login required.
///
/// Collects role (Teacher/Student only), full name, phone, type
/// (Emergency/Reminder) and description, then INSERTs a single `pending`
/// complaint row. This page NEVER reads or lists complaints, so anonymous
/// users cannot see anyone else's data. Client-side validation +
/// cooldown throttle sit on top of the database CHECK constraints.
class ComplaintPage extends StatefulWidget {
  const ComplaintPage({super.key});

  @override
  State<ComplaintPage> createState() => _ComplaintPageState();
}

class _ComplaintPageState extends State<ComplaintPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descController = TextEditingController();

  String _role = ComplaintService.roleStudent;
  String _type = ComplaintService.typeReminder;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _tablesReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_tablesReady) {
      _snack('Service unavailable. Please try again later.',
          Colors.red);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final result = await ComplaintService.submit(
        role: _role,
        fullName: _nameController.text,
        phoneNumber: _phoneController.text,
        complaintType: _type,
        description: _descController.text,
      );
      if (!mounted) return;
      if (result.isEmpty) {
        _successDialog();
      } else if (result.startsWith('cooldown:')) {
        final secs =
            int.tryParse(result.split(':').last) ?? 0;
        final mins = (secs / 60).ceil();
        _snack(
            'Please wait $mins minute${mins == 1 ? '' : 's'} before submitting again.',
            Colors.orange);
      } else if (result == 'validation') {
        _snack('Please check the highlighted fields.', Colors.red);
      } else {
        _snack('Connection error. Please try again.', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

  void _successDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [
                Color(0xFF0E9F6E),
                Color(0xFF4ADE80),
              ]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          Text(tr('cmp_success_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(tr('cmp_success_msg'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // dialog
                Navigator.pop(context); // back to Login
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(tr('c_close'),
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
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
        title: Text(tr('nav_complaint'),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LangBuilder(
        builder: (_) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerCard(),
                  const SizedBox(height: 16),
                  FadeInSlide(
                    index: 1,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _label(tr('cmp_role')),
                            _segmented(
                              value: _role,
                              options: {
                                ComplaintService.roleTeacher:
                                    '👩‍🏫 ${tr('cmp_teacher')}',
                                ComplaintService.roleStudent:
                                    '🎒 ${tr('cmp_student')}',
                              },
                              onChanged: (v) =>
                                  setState(() => _role = v),
                            ),
                            const SizedBox(height: 14),
                            _label(tr('cmp_full_name')),
                            TextFormField(
                              controller: _nameController,
                              style: GoogleFonts.poppins(
                                  fontSize: 14),
                              decoration:
                                  _dec('e.g. John Doe'),
                              validator: (v) =>
                                  v == null ||
                                          v.trim().isEmpty
                                      ? 'Please enter your full name.'
                                      : v.trim().length > 120
                                          ? 'Name is too long.'
                                          : null,
                            ),
                            const SizedBox(height: 14),
                            _label(tr('cmp_phone')),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType:
                                  TextInputType.phone,
                              style: GoogleFonts.poppins(
                                  fontSize: 14),
                              decoration:
                                  _dec('e.g. 98XXXXXXXX'),
                              validator: (v) =>
                                  !ComplaintService.isValidPhone(
                                          v ?? '')
                                      ? 'Please enter a valid phone number.'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            _label(tr('cmp_type')),
                            _segmented(
                              value: _type,
                              options: {
                                ComplaintService.typeEmergency:
                                    '🔴 ${tr('cmp_emergency')}',
                                ComplaintService.typeReminder:
                                    '🔔 ${tr('cmp_reminder')}',
                              },
                              onChanged: (v) =>
                                  setState(() => _type = v),
                            ),
                            const SizedBox(height: 14),
                            _label(tr('cmp_description')),
                            TextFormField(
                              controller: _descController,
                              maxLines: 6,
                              maxLength: ComplaintService
                                  .maxDescriptionLength,
                              style: GoogleFonts.poppins(
                                  fontSize: 14, height: 1.6),
                              decoration: _dec(
                                  tr('cmp_desc_hint')),
                              validator: (v) =>
                                  v == null ||
                                          v.trim().isEmpty
                                      ? 'Please describe the problem.'
                                      : v.trim().length >
                                              ComplaintService
                                                  .maxDescriptionLength
                                          ? 'Description is too long.'
                                          : null,
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : _submit,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child:
                                            CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth:
                                                    2.5))
                                    : const Icon(
                                        Icons.send_rounded,
                                        size: 19),
                                label: Text(tr('cmp_submit'),
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight:
                                            FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF1565C0),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFF1565C0)
                                          .withValues(
                                              alpha: 0.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(
                                              14)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ]),
                    ),
                  ),
                ]),
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
            child: const Icon(Icons.report_problem_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('cmp_title'),
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(tr('cmp_sub'),
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
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

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
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
              const BorderSide(color: Color(0xFF1565C0), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      counterStyle: GoogleFonts.poppins(
          fontSize: 11, color: Colors.grey.shade400),
    );
  }

  Widget _segmented({
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        for (final e in options.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: value == e.key
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: value == e.key
                      ? [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(e.value,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: value == e.key
                              ? const Color(0xFF0B2A5B)
                              : Colors.grey.shade500)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
