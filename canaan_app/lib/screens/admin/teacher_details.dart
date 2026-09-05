import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin → Teachers → Teacher Details.
///
/// Section tabs (Sub Junior / Junior / Senior) loaded live from the
/// `teachers` table, with view sheet + edit dialog + delete.
class TeacherDetails extends StatefulWidget {
  const TeacherDetails({super.key});

  @override
  State<TeacherDetails> createState() => _TeacherDetailsState();
}

class _TeacherDetailsState extends State<TeacherDetails>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _allTeachers = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchTeachers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTeachers() async {
    setState(() => _isLoading = true);
    try {
      final data = await _client
          .from('teachers')
          .select('*')
          .order('full_name');
      if (mounted) {
        setState(() {
          _allTeachers = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filterBySection(String section) {
    return _allTeachers.where((t) {
      final matchesSection = t['section'] == section;
      if (_searchQuery.isEmpty) return matchesSection;
      final q = _searchQuery.toLowerCase();
      final name = (t['full_name'] ?? '').toString().toLowerCase();
      final email = (t['email'] ?? '').toString().toLowerCase();
      final username = (t['username'] ?? '').toString().toLowerCase();
      return matchesSection &&
          (name.contains(q) || email.contains(q) || username.contains(q));
    }).toList();
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

  void _showDetails(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor:
                      const Color(0xFF1565C0).withValues(alpha: 0.1),
                  child: Text(
                    _initials((t['full_name'] ?? '').toString()),
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1565C0)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  (t['full_name'] ?? '').toString(),
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              Center(child: _sectionBadge((t['section'] ?? '').toString())),
              const SizedBox(height: 24),
              _detailRow('Email', (t['email'] ?? '').toString()),
              _detailRow('Mobile', (t['phone'] ?? '').toString()),
              _detailRow('Age', '${t['age'] ?? ''}'),
              _detailRow('Username', (t['username'] ?? '').toString()),
              _detailRow('Status', (t['status'] ?? 'active').toString()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _editDialog(Map<String, dynamic> t) {
    final name = TextEditingController(text: (t['full_name'] ?? '').toString());
    final email = TextEditingController(text: (t['email'] ?? '').toString());
    final phone = TextEditingController(text: (t['phone'] ?? '').toString());
    final age = TextEditingController(text: '${t['age'] ?? ''}');
    final username =
        TextEditingController(text: (t['username'] ?? '').toString());
    final password = TextEditingController();
    String section = (t['section'] ?? 'sub-junior').toString();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Teacher',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _editField(name, 'Full Name'),
                  const SizedBox(height: 10),
                  _editField(email, 'Email'),
                  const SizedBox(height: 10),
                  _editField(phone, 'Mobile'),
                  const SizedBox(height: 10),
                  _editField(age, 'Age',
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: ['sub-junior', 'junior', 'senior']
                            .contains(section)
                        ? section
                        : 'sub-junior',
                    decoration: InputDecoration(
                      labelText: 'Section',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'sub-junior', child: Text('Sub Junior')),
                      DropdownMenuItem(
                          value: 'junior', child: Text('Junior')),
                      DropdownMenuItem(
                          value: 'senior', child: Text('Senior')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => section = v ?? section),
                  ),
                  const SizedBox(height: 10),
                  _editField(username, 'Username'),
                  const SizedBox(height: 10),
                  _editField(password,
                      'New password (leave blank to keep)'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      try {
                        final payload = <String, dynamic>{
                          'full_name': name.text.trim(),
                          'email': email.text.trim(),
                          'phone': phone.text.trim(),
                          'age':
                              int.tryParse(age.text.trim()) ?? t['age'] ?? 0,
                          'section': section,
                          'username': username.text.trim(),
                        };
                        if (password.text.trim().isNotEmpty) {
                          payload['password'] = password.text.trim();
                        }
                        await _client
                            .from('teachers')
                            .update(payload)
                            .eq('id', t['id']);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _fetchTeachers();
                        _snack('Teacher updated.', Colors.green);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _snack('Could not update. Please try again.',
                            Colors.red);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Save',
                      style:
                          GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(TextEditingController controller, String label,
      {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: label.startsWith('New password')
          ? null
          : (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  void _confirmDelete(Map<String, dynamic> t) {
    final name = (t['full_name'] ?? '').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Teacher',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to delete $name?',
            style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _client.from('teachers').delete().eq('id', t['id']);
                if (!mounted) return;
                _snack('$name deleted', Colors.red);
                _fetchTeachers();
              } catch (e) {
                if (!mounted) return;
                _snack('Error deleting teacher', Colors.red);
              }
            },
            child: Text('Delete',
                style: GoogleFonts.poppins(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        title: Text(
          'Teacher Details',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Sub Junior'),
            Tab(text: 'Junior'),
            Tab(text: 'Senior'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search teachers...',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF1565C0), width: 2),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _teacherList(_filterBySection('sub-junior')),
                      _teacherList(_filterBySection('junior')),
                      _teacherList(_filterBySection('senior')),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _teacherList(List<Map<String, dynamic>> teachers) {
    if (teachers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.co_present_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No teachers found in this section.',
              style: GoogleFonts.poppins(
                  fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: teachers.length,
      itemBuilder: (context, index) {
        final t = teachers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    const Color(0xFF1565C0).withValues(alpha: 0.1),
                child: Text(
                  _initials((t['full_name'] ?? '').toString()),
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1565C0)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (t['full_name'] ?? '').toString(),
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (t['username'] ?? '').toString(),
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              _sectionBadge((t['section'] ?? '').toString()),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.visibility_rounded,
                    color: Colors.grey.shade500, size: 20),
                tooltip: 'View Details',
                onPressed: () => _showDetails(t),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded,
                    color: Color(0xFF1565C0), size: 20),
                tooltip: 'Edit',
                onPressed: () => _editDialog(t),
              ),
              IconButton(
                icon:
                    const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(t),
              ),
            ],
          ),
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Widget _sectionBadge(String section) {
    Color color;
    String label;
    switch (section) {
      case 'sub-junior':
        color = const Color(0xFF7B1FA2);
        label = 'Sub Jr';
        break;
      case 'junior':
        color = const Color(0xFF1565C0);
        label = 'Jun';
        break;
      case 'senior':
        color = const Color(0xFF43A047);
        label = 'Sen';
        break;
      default:
        color = Colors.grey;
        label = section;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
