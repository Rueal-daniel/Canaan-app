import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/student_id_service.dart';
import '../../widgets/animations.dart';
import '../id_card_detail.dart';

/// Student ID Cards browser.
///
/// Admin (no [lockedSection]): section tabs + search + grid of every
/// student, with Generate support on the detail page.
/// Teacher ([lockedSection] set): the assigned section only, read-only —
/// no ID generation, no profile edits from here.
class StudentIdCardsPage extends StatefulWidget {
  final String? lockedSection;
  const StudentIdCardsPage({super.key, this.lockedSection});

  @override
  State<StudentIdCardsPage> createState() => _StudentIdCardsPageState();
}

class _StudentIdCardsPageState extends State<StudentIdCardsPage>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;
  final _searchController = TextEditingController();

  static const _sections = ['sub-junior', 'junior', 'senior'];

  bool get _locked =>
      widget.lockedSection != null && widget.lockedSection!.isNotEmpty;
  // Teachers never manage IDs; only the all-sections Admin view does.
  bool get _canManage => !_locked;

  List<Map<String, dynamic>> _students = [];
  String _search = '';
  bool _isLoading = true;
  String? _loadError;
  StreamSubscription? _sub;

  String get _section => _locked
      ? StudentIdService.normalizeSection(widget.lockedSection)
      : _sections[_tabController.index];

  String _prettySection(String s) {
    if (s == 'sub-junior') return 'Sub Junior';
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_locked && mounted) _fetch();
    });
    _fetch();
    try {
      _sub = _client
          .from('students')
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _fetch(silent: true);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      // select('*') keeps photo/ID working with or without the
      // student_id_number migration.
      final rows = await _client
          .from('students')
          .select('*')
          .eq('section', _section)
          .order('full_name');
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load students. ($e)';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _students;
    return _students.where((s) {
      final name = ((s['full_name'] ?? '').toString()).toLowerCase();
      final id =
          StudentIdService.idNumberOf(s).toLowerCase();
      return name.contains(q) || id.contains(q);
    }).toList();
  }

  void _openCard(Map<String, dynamic> s) {
    Navigator.push(
      context,
      SlidePageRoute(
        page: IdCardDetailPage(
          studentId: (s['id'] ?? '').toString(),
          canManage: _canManage,
        ),
      ),
    ).then((_) {
      if (mounted) _fetch(silent: true);
    });
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
              colors: [Color(0xFF0B2A5B), Color(0xFF1565C0), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Student ID Cards',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: _locked
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 13),
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
          if (_locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF6366F1)
                          .withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.group_rounded,
                        color: Color(0xFF6366F1), size: 22),
                    const SizedBox(width: 10),
                    Text('My Section: ${_prettySection(_section)}',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827))),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search Student 🔍',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF1565C0), width: 2)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : _loadError != null
                    ? _errorState()
                    : RefreshIndicator(
                        color: const Color(0xFF1565C0),
                        onRefresh: () => _fetch(),
                        child: _visible.isEmpty
                            ? _emptyState()
                            : GridView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    20, 8, 20, 24),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 260,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 262,
                                ),
                                itemCount: _visible.length,
                                itemBuilder: (_, i) =>
                                    _miniCard(_visible[i]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(_loadError ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetch(),
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
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Icon(Icons.badge_outlined,
                  size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                _search.trim().isEmpty
                    ? 'No students in ${_prettySection(_section)} yet.'
                    : 'No students match "$_search".',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniCard(Map<String, dynamic> s) {
    final name = ((s['full_name'] ?? '').toString().trim().isEmpty)
        ? 'Student'
        : (s['full_name'] ?? '').toString().trim();
    final photo =
        StudentIdService.photoUrl(s['photo_url']?.toString());
    final idNumber = StudentIdService.idNumberOf(s);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor:
                const Color(0xFF1565C0).withValues(alpha: 0.1),
            backgroundImage:
                photo.isNotEmpty ? NetworkImage(photo) : null,
            onBackgroundImageError:
                photo.isNotEmpty ? (_, _) {} : null,
            child: photo.isEmpty
                ? Text(_initials(name),
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0)))
                : null,
          ),
          const SizedBox(height: 10),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
          const SizedBox(height: 2),
          Text(_prettySection((s['section'] ?? '').toString()),
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: idNumber.isEmpty
                  ? Colors.grey.shade100
                  : const Color(0xFF0B2A5B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(idNumber.isEmpty ? 'PENDING' : idNumber,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: idNumber.isEmpty
                        ? Colors.grey.shade500
                        : Colors.white)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton(
              onPressed: () => _openCard(s),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF1565C0)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.zero,
              ),
              child: Text('View ID Card',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}
