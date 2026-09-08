import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../widgets/animations.dart';
import '../widgets/dashboard_design.dart';

/// Sidebar → Profile. Shows ALL details of the logged-in person
/// (admin / teacher / student) fetched live from Supabase.
/// The password is never read for display — it is stripped from
/// every row before rendering.
class ProfilePage extends StatefulWidget {
  /// 'admin' | 'teacher' | 'student'
  final String role;
  final String fallbackName;
  final String? photoUrl;
  const ProfilePage({
    super.key,
    required this.role,
    this.fallbackName = '',
    this.photoUrl,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _row;
  bool _isLoading = true;
  String? _error;

  static const _hiddenKeys = {
    'password',
    'id',
    'photo_url',
    'suspended_at',
    'suspended_by_admin_id',
  };

  static const _labels = {
    'full_name': 'Full Name',
    'username': 'Username',
    'role': 'Role',
    'email': 'Email',
    'phone': 'Phone',
    'age': 'Age',
    'section': 'Section',
    'status': 'Status',
    'teacher_name': 'Teacher',
    'father_name': "Father's Name",
    'father_phone': "Father's Phone",
    'mother_name': "Mother's Name",
    'mother_phone': "Mother's Phone",
    'guardian_phone': 'Guardian Phone',
    'created_at': 'Member Since',
    'updated_at': 'Last Updated',
  };

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  UserRole? get _userRole {
    switch (widget.role) {
      case 'admin':
        return UserRole.admin;
      case 'teacher':
        return UserRole.teacher;
      default:
        return UserRole.student;
    }
  }

  String get _table {
    switch (widget.role) {
      case 'admin':
        return 'admin';
      case 'teacher':
        return 'teachers';
      default:
        return 'students';
    }
  }

  List<Color> get _gradient {
    switch (widget.role) {
      case 'admin':
        return DashColors.adminGradient;
      case 'teacher':
        return DashColors.teacherGradient;
      default:
        return DashColors.studentGradient;
    }
  }

  String get _roleLabel {
    switch (widget.role) {
      case 'admin':
        return 'Canaan Administrator';
      case 'teacher':
        return 'Teacher';
      default:
        return 'Student';
    }
  }

  Future<void> _fetchProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      Map<String, dynamic>? row;
      try {
        final session = await SessionService.getSession();
        if (session != null && session.role == widget.role) {
          row = await AuthService()
              .getUserById(userId: session.userId, role: _userRole!);
        }
      } catch (_) {}
      // Fallback: match by full name.
      if (row == null && widget.fallbackName.isNotEmpty) {
        try {
          final rows = await _client
              .from(_table)
              .select('*')
              .eq('full_name', widget.fallbackName)
              .limit(1);
          final list = List<Map<String, dynamic>>.from(rows);
          if (list.isNotEmpty) row = list.first;
        } catch (_) {}
      }
      if (row == null) throw Exception('profile not found');
      row.removeWhere((k, _) => _hiddenKeys.contains(k));
      if (mounted) {
        setState(() {
          _row = row;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load profile. ($e)';
        });
      }
    }
  }

  String _prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  String _value(String key) {
    // Admins have no status column — they are always active.
    if (key == 'status' && widget.role == 'admin') return 'Active';
    final v = _row?[key];
    final s = v == null ? '' : v.toString().trim();
    if (s.isEmpty) return '—';
    if (key == 'section') return dashPrettySection(s);
    if (key == 'role') {
      return s == 'admin' ? 'Canaan Administrator' : dashPrettySection(s);
    }
    if (key == 'status') {
      return s[0].toUpperCase() + s.substring(1).toLowerCase();
    }
    if (key == 'created_at' || key == 'updated_at') return _prettyDate(s);
    return s;
  }

  bool _isEmpty(String key) {
    final v = _row?[key];
    return v == null || v.toString().trim().isEmpty;
  }


  @override
  Widget build(BuildContext context) {
    final photo = widget.photoUrl ??
        ((_row?['photo_url'] ?? '').toString().isNotEmpty &&
                widget.role == 'student'
            ? 'https://pjytoxyddfrsrkzappbb.supabase.co/storage/v1/object/public/student-photos/${_row!['photo_url']}'
            : null);
    final name = ((_row?['full_name'] ?? '').toString().isNotEmpty
            ? (_row!['full_name']).toString()
            : widget.fallbackName).trim();
    final status = _value('status');
    final isActive = status.toLowerCase() == 'active';

    return Scaffold(
      backgroundColor: DashColors.bg,
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
        title: Text('Profile',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchProfile,
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1565C0))),
                )
              : _error != null
                  ? _errorCard()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeInSlide(
                          index: 0,
                          child: _headerCard(
                              name.isEmpty ? 'Profile' : name,
                              photo,
                              status,
                              isActive),
                        ),
                        const SizedBox(height: 16),
                        ..._groups(),
                        const SizedBox(height: 8),
                      ],
                    ),
        ),
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
        Text(_error ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style:
                GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _fetchProfile,
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

  Widget _headerCard(
      String name, String? photo, String status, bool isActive) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _gradient.last.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.55), width: 2),
          ),
          child: CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            backgroundImage: photo != null && photo.isNotEmpty
                ? NetworkImage(photo)
                : null,
            onBackgroundImageError:
                photo != null && photo.isNotEmpty ? (_, _) {} : null,
            child: photo == null || photo.isEmpty
                ? Text(dashInitials(name),
                    style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white))
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(name,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _heroPill(_roleLabel),
            if (status.isNotEmpty && status != '—')
              _heroPill(status,
                  dot: isActive
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFFCA5A5)),
          ],
        ),
      ]),
    );
  }

  Widget _heroPill(String text, {Color? dot}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null) ...[
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(text,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]),
    );
  }

  /// Every field of the role's schema is shown — empty values render
  /// as a dash instead of hiding the row.
  List<Widget> _groups() {
    final Map<String, List<String>> groups;
    switch (widget.role) {
      case 'admin':
        groups = {
          'Account': ['username', 'role', 'status'],
          'Personal Details': ['full_name', 'email'],
          'Membership': ['created_at'],
        };
        break;
      case 'teacher':
        groups = {
          'Account': ['username', 'status'],
          'Personal Details': ['full_name', 'age', 'email'],
          'Contact': ['phone'],
          'School': ['section'],
          'Membership': ['created_at'],
        };
        break;
      default:
        groups = {
          'Account': ['username', 'status'],
          'Personal Details': ['full_name', 'age', 'email'],
          'Contact': ['phone'],
          'School': ['section', 'teacher_name'],
          'Family': [
            'father_name',
            'father_phone',
            'mother_name',
            'mother_phone',
            'guardian_phone'
          ],
          'Membership': ['created_at'],
        };
    }
    final widgets = <Widget>[];
    var index = 1;
    groups.forEach((title, keys) {
      final rows = <(String, String, bool)>[];
      for (final k in keys) {
        rows.add((_labels[k] ?? k, _value(k), _isEmpty(k)));
      }
      widgets.add(FadeInSlide(
        index: index++,
        child: _groupCard(title, rows),
      ));
      widgets.add(const SizedBox(height: 12));
    });
    return widgets;
  }

  Widget _groupCard(
      String title, List<(String, String, bool)> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DashColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: DashColors.ink)),
        const SizedBox(height: 12),
        for (int i = 0; i < rows.length; i++) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 130,
              child: Text(rows[i].$1,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: DashColors.muted)),
            ),
            Expanded(
              child: Text(rows[i].$2,
                  style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: rows[i].$3
                          ? FontWeight.w500
                          : FontWeight.w600,
                      color: rows[i].$3
                          ? Colors.grey.shade400
                          : DashColors.ink)),
            ),
          ]),
          if (i < rows.length - 1) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 10),
          ],
        ],
      ]),
    );
  }
}
