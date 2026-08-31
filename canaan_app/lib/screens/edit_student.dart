import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditStudent extends StatefulWidget {
  final Map<String, dynamic> student;
  const EditStudent({super.key, required this.student});

  @override
  State<EditStudent> createState() => _EditStudentState();
}

class _EditStudentState extends State<EditStudent> {
  final _formKey = GlobalKey<FormState>();
  final _client = Supabase.instance.client;
  bool _isLoading = false;

  late TextEditingController _fullName;
  late TextEditingController _age;
  late TextEditingController _email;
  late TextEditingController _phone;
  late TextEditingController _fatherName;
  late TextEditingController _fatherPhone;
  late TextEditingController _motherName;
  late TextEditingController _motherPhone;
  late TextEditingController _guardianPhone;
  late TextEditingController _teacherName;
  late TextEditingController _username;
  late TextEditingController _password;
  String _section = 'sub-junior';
  String _status = 'active';

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    _fullName = TextEditingController(text: s['full_name'] ?? '');
    _age = TextEditingController(text: '${s['age'] ?? ''}');
    _email = TextEditingController(text: s['email'] ?? '');
    _phone = TextEditingController(text: s['phone'] ?? '');
    _fatherName = TextEditingController(text: s['father_name'] ?? '');
    _fatherPhone = TextEditingController(text: s['father_phone'] ?? '');
    _motherName = TextEditingController(text: s['mother_name'] ?? '');
    _motherPhone = TextEditingController(text: s['mother_phone'] ?? '');
    _guardianPhone = TextEditingController(text: s['guardian_phone'] ?? '');
    _teacherName = TextEditingController(text: s['teacher_name'] ?? '');
    _username = TextEditingController(text: s['username'] ?? '');
    _password = TextEditingController(text: s['password'] ?? '');
    _section = s['section'] ?? 'sub-junior';
    _status = s['status'] ?? 'active';
  }

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

  Future<void> _updateStudent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await _client.from('students').update({
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
        'status': _status,
      }).eq('id', widget.student['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Student updated successfully', style: GoogleFonts.poppins()),
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
          content: Text('Error updating student', style: GoogleFonts.poppins()),
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
        backgroundColor: const Color(0xFF1565C0),
        title: Text(
          'Edit Student',
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
              _sectionTitle('Student Information'),
              const SizedBox(height: 12),
              _field(_fullName, 'Full Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(_age, 'Age', Icons.cake_rounded, keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _field(_email, 'Email', Icons.email_rounded, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _field(_phone, 'Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 20),
              _sectionTitle('Parent Information'),
              const SizedBox(height: 12),
              _field(_fatherName, 'Father Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(_fatherPhone, 'Father Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_motherName, 'Mother Name', Icons.person_rounded),
              const SizedBox(height: 12),
              _field(_motherPhone, 'Mother Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _field(_guardianPhone, 'Guardian Phone', Icons.phone_rounded, keyboardType: TextInputType.phone),
              const SizedBox(height: 20),
              _sectionTitle('Other Details'),
              const SizedBox(height: 12),
              _field(_teacherName, 'Teacher Name', Icons.school_rounded),
              const SizedBox(height: 12),
              _field(_username, 'Username', Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _field(_password, 'Password', Icons.lock_rounded),
              const SizedBox(height: 12),
              _dropdownSection(),
              const SizedBox(height: 12),
              _dropdownStatus(),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateStudent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text('Update Student', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
      items: [
        DropdownMenuItem(value: 'sub-junior', child: Text('Sub Junior', style: GoogleFonts.poppins())),
        DropdownMenuItem(value: 'junior', child: Text('Junior', style: GoogleFonts.poppins())),
        DropdownMenuItem(value: 'senior', child: Text('Senior', style: GoogleFonts.poppins())),
      ],
      onChanged: (v) => setState(() => _section = v!),
    );
  }

  Widget _dropdownStatus() {
    return DropdownButtonFormField<String>(
      initialValue: _status,
      decoration: InputDecoration(
        hintText: 'Status',
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: const Icon(Icons.toggle_on_rounded, color: Color(0xFF1565C0), size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
      items: [
        DropdownMenuItem(value: 'active', child: Text('Active', style: GoogleFonts.poppins())),
        DropdownMenuItem(value: 'inactive', child: Text('Inactive', style: GoogleFonts.poppins())),
      ],
      onChanged: (v) => setState(() => _status = v!),
    );
  }
}
