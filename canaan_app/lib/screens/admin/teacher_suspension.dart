import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/session_service.dart';

/// Admin → Teachers → Teacher Suspension.
///
/// Suspend / restore teacher accounts. Suspended teachers cannot log
/// in (blocked at authentication + session checks). Nothing is ever
/// deleted — only the `status` access flag changes.
class TeacherSuspension extends StatefulWidget {
  const TeacherSuspension({super.key});

  @override
  State<TeacherSuspension> createState() => _TeacherSuspensionState();
}

class _TeacherSuspensionState extends State<TeacherSuspension>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  final _authService = AuthService();
  late TabController _tabController;
  final _searchController = TextEditingController();

  static const _sections = ['sub-junior', 'junior', 'senior'];

  List<Map<String, dynamic>> _allTeachers = [];
  String _searchQuery = '';
  String _statusFilter = 'all'; // all|active|suspended
  bool _isLoading = true;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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
          .select('id, full_name, email, phone, section, username, status')
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

  String get _currentSection => _sections[_tabController.index];

  String _prettySection(String section) {
    if (section == 'sub-junior') return 'Sub Junior';
    if (section.isEmpty) return section;
    return section[0].toUpperCase() + section.substring(1);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  List<Map<String, dynamic>> get _visible {
    final q = _searchQuery.toLowerCase();
    return _allTeachers.where((t) {
      if (t['section'] != _currentSection) return false;
      final suspended = AuthService.isSuspended(t);
      if (_statusFilter == 'active' && suspended) return false;
      if (_statusFilter == 'suspended' && !suspended) return false;
      if (q.isEmpty) return true;
      final name = (t['full_name'] ?? '').toString().toLowerCase();
      final email = (t['email'] ?? '').toString().toLowerCase();
      final phone = (t['phone'] ?? '').toString().toLowerCase();
      final username = (t['username'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          email.contains(q) ||
          phone.contains(q) ||
          username.contains(q);
    }).toList();
  }

  int _countStatus(String section, {required bool suspended}) {
    return _allTeachers.where((t) {
      final inSection = section == 'all' || t['section'] == section;
      final isSusp = AuthService.isSuspended(t);
      return inSection && (suspended ? isSusp : !isSusp);
    }).length;
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

  void _confirmSuspend(Map<String, dynamic> t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Suspend Teacher?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'Are you sure you want to suspend this teacher? This teacher will no longer be able to log in until their account is restored.',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
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
              await _applyStatus(t, suspended: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Suspend Teacher',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
        title: Text('Teacher Suspension',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Suspend or restore teacher accounts.',
                style: GoogleFonts.poppins(
                    fontSize: 13.5, color: Colors.grey.shade600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E)),
                      dropdownColor: Colors.white,
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('All')),
                        DropdownMenuItem(
                            value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'suspended', child: Text('Suspended')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _statusFilter = v);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                              icon:
                                  const Icon(Icons.clear_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
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
                          borderSide: const BorderSide(
                              color: Color(0xFF1565C0), width: 2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_isLoading) _summaryRow(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _teacherList(),
                      _teacherList(),
                      _teacherList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow() {
    final total =
        _allTeachers.where((t) => t['section'] == _currentSection).length;
    final suspended = _countStatus(_currentSection, suspended: true);
    final active = total - suspended;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Expanded(
              child: _miniStat('Total Teachers', '$total',
                  Icons.groups_rounded, const Color(0xFF6366F1))),
          const SizedBox(width: 10),
          Expanded(
              child: _miniStat('Active Teachers', '$active',
                  Icons.check_circle_rounded, const Color(0xFF22C55E))),
          const SizedBox(width: 10),
          Expanded(
              child: _miniStat('Suspended Teachers', '$suspended',
                  Icons.block_rounded, const Color(0xFFEF4444))),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827))),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _teacherList() {
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.co_present_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No teachers found in this section.',
                style: GoogleFonts.poppins(
                    fontSize: 15, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final t = items[i];
        final suspended = AuthService.isSuspended(t);
        final name = (t['full_name'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: (suspended
                            ? Colors.red
                            : const Color(0xFF1565C0))
                        .withValues(alpha: 0.1),
                    child: Text(_initials(name),
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: suspended
                                ? Colors.red
                                : const Color(0xFF1565C0))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827))),
                        const SizedBox(height: 2),
                        Text((t['email'] ?? '').toString(),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  _statusBadge(suspended),
                ],
              ),
              const SizedBox(height: 10),
              _infoLine('Phone', (t['phone'] ?? '').toString()),
              _infoLine('Section', _prettySection((t['section'] ?? '').toString())),
              _infoLine('Username', (t['username'] ?? '').toString()),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _isWorking
                      ? null
                      : () => suspended
                          ? _confirmUnsuspend(t)
                          : _confirmSuspend(t),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: suspended
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                      suspended ? 'Unsuspend Teacher' : 'Suspend Teacher',
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  void _confirmUnsuspend(Map<String, dynamic> t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Restore Teacher Account?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'This teacher will be allowed to log in again.',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
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
              await _applyStatus(t, suspended: false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Unsuspend Teacher',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _applyStatus(Map<String, dynamic> t,
      {required bool suspended}) async {
    setState(() => _isWorking = true);
    try {
      final adminId = await _adminId();
      await _authService.setTeacherStatus(
        teacherId: t['id'].toString(),
        suspended: suspended,
        adminId: adminId,
      );
      await _fetchTeachers();
      _snack(
        suspended
            ? 'Teacher suspended. Login blocked.'
            : 'Access restored. Teacher is active again.',
        suspended ? Colors.red : Colors.green,
      );
    } catch (e) {
      _snack('Could not update status. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Widget _statusBadge(bool suspended) {
    final color =
        suspended ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(suspended ? 'Suspended' : 'Active',
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
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
}
