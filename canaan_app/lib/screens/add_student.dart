import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddStudent extends StatefulWidget {
  const AddStudent({super.key});

  @override
  State<AddStudent> createState() => _AddStudentState();
}

class _AddStudentState extends State<AddStudent> {
  final _formKey = GlobalKey<FormState>();
  final _client = Supabase.instance.client;
  bool _isLoading = false;

  final _fullName = TextEditingController();
  final _age = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _fatherName = TextEditingController();
  final _fatherPhone = TextEditingController();
  final _motherName = TextEditingController();
  final _motherPhone = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _teacherName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _section = 'sub-junior';

  @override
  void dispose() {
    _fullName.dispose();
    _age.dispose();
    _email.dispose();
    _phone.dispose();
    _fatherName.dispose();
    _fatherPhone.dispose();
    _motherName.dispose();
    _motherPhone.dispose();
    _guardianPhone.dispose();
    _teacherName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _addStudent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await _client.from('students').insert({
        'full_name': _fullName.text.trim(),
        'age': int.tryParse(_age.text.trim()) ?? 0,
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'father_name': _fatherName.text.trim(),
        'father_phone': _fatherPhone.text.trim(),
        'mother_name': _motherName.text.trim(),
        'mother_phone': _motherPhone.text.trim(),
        'guardian_phone': _guardianPhone.text.trim(),
        'teacher_name': _teacherName.text.trim(),
        'username': _username.text.trim(),
        'password': _password.text.trim(),
        'section': _section,
        'status': 'active',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Student added successfully!', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        title: Text(
          'Add Student',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Student Information', Icons.school_rounded, const Color(0xFF1565C0)),
              const SizedBox(height: 14),
              _field(_fullName, 'Full Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(_age, 'Age', Icons.cake_rounded, keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _field(_email, 'Email', Icons.email_rounded, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _field(_phone, 'Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 24),
              _sectionHeader('Parent Information', Icons.family_restroom_rounded, const Color(0xFFFFA000)),
              const SizedBox(height: 14),
              _field(_fatherName, 'Father Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(_fatherPhone, 'Father Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_motherName, 'Mother Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(_motherPhone, 'Mother Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_guardianPhone, 'Guardian Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 24),
              _sectionHeader('Account Details', Icons.lock_rounded, const Color(0xFF7B1FA2)),
              const SizedBox(height: 14),
              _field(_teacherName, 'Teacher Name', Icons.school_rounded),
              const SizedBox(height: 12),
              _field(_username, 'Username', Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _field(_password, 'Password', Icons.lock_rounded),
              const SizedBox(height: 12),
              _dropdownSection(),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addStudent,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: EdgeInsets.zero,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : Text(
                              'Add Student',
                              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0D47A1)),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String hint, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red)),
      ),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _dropdownSection() {
    return DropdownButtonFormField<String>(
      initialValue: _section,
      decoration: InputDecoration(
        hintText: 'Section',
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: const Icon(Icons.class_rounded, color: Color(0xFF1565C0), size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
      items: [
        DropdownMenuItem(value: 'sub-junior', child: Text('Sub Junior', style: GoogleFonts.poppins())),
        DropdownMenuItem(value: 'junior', child: Text('Junior', style: GoogleFonts.poppins())),
        DropdownMenuItem(value: 'senior', child: Text('Senior', style: GoogleFonts.poppins())),
      ],
      onChanged: (v) => setState(() => _section = v!),
    );
  }
}
