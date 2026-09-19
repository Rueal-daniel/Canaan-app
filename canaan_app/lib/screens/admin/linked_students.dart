import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/linked_student_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';

/// Admin → Students → Linked Students.
///
/// Admin-only family linking: search students (name / Student ID /
/// username), select several, save them as one linked group. Students can
/// never create links themselves — the link becomes active only after the
/// Admin saves it here.
class LinkedStudentsPage extends StatefulWidget {
  const LinkedStudentsPage({super.key});

  @override
  State<LinkedStudentsPage> createState() => _LinkedStudentsPageState();
}

class _LinkedStudentsPageState extends State<LinkedStudentsPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _groups = [];
  final Map<String, List<Map<String, dynamic>>> _membersByGroup = {};
  bool _isLoading = true;
  String? _loadError;
  String _adminId = '';
  StreamSubscription? _groupSub;
  StreamSubscription? _memberSub;

  @override
  void initState() {
    super.initState();
    _init();
    _watchRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _groupSub?.cancel();
    _memberSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        _adminId = session.userId;
      }
    } catch (_) {}
    await _load();
  }

  void _watchRealtime() {
    try {
      _groupSub = Supabase.instance.client
          .from(LinkedStudentService.groupsTable)
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _load(silent: true);
      });
    } catch (_) {}
    try {
      _memberSub = Supabase.instance.client
          .from(LinkedStudentService.membersTable)
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _load(silent: true);
      });
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final groups = await LinkedStudentService.fetchGroups();
      final members = <String, List<Map<String, dynamic>>>{};
      for (final g in groups) {
        final gid = (g['id'] ?? '').toString();
        if (gid.isEmpty) continue;
        members[gid] = await LinkedStudentService.fetchGroupMembers(gid);
      }
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _membersByGroup
          ..clear()
          ..addAll(members);
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load linked groups. Run supabase/student_links.sql once, then retry. ($e)';
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

  Future<void> _openEditor({Map<String, dynamic>? group}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupEditorSheet(
        group: group,
        adminId: _adminId,
        initialMembers: group == null
            ? const []
            : List<Map<String, dynamic>>.from(
                _membersByGroup[(group['id'] ?? '').toString()] ?? const []),
      ),
    );
    if (changed == true && mounted) _load(silent: true);
  }

  Future<void> _confirmDelete(Map<String, dynamic> group) async {
    final name = (group['group_name'] ?? 'Family Group').toString();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Linked Group?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'Remove "$name" and unlink its students? Student accounts are kept — only the link is deleted.',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await LinkedStudentService.deleteGroup(
        (group['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Linked group deleted.', const Color(0xFF0E9F6E));
      _load(silent: true);
    } else {
      _snack('Could not delete. Please try again.', Colors.red);
    }
  }

  Future<void> _removeMember(
      Map<String, dynamic> group, Map<String, dynamic> student) async {
    final ok = await LinkedStudentService.removeMember(
      groupId: (group['id'] ?? '').toString(),
      studentId: (student['id'] ?? '').toString(),
    );
    if (!mounted) return;
    if (ok) {
      _snack('Student removed from group.', const Color(0xFF0E9F6E));
      _load(silent: true);
    } else {
      _snack('Could not remove. Please try again.', Colors.red);
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
        title: Text('Linked Students',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LangBuilder(
        builder: (_) => RefreshIndicator(
          onRefresh: () => _load(),
          color: const Color(0xFF1565C0),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF1565C0)))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _headerCard(),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.group_add_rounded, size: 22),
                          label: Text('+ Add New Linked Group',
                              style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E9F6E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_loadError != null) _errorCard(),
                      if (_loadError == null)
                        Text('Linked Student Groups (${_groups.length})',
                            style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827))),
                      const SizedBox(height: 12),
                      if (_loadError == null) _groupList(),
                    ],
                  ),
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
            child: const Icon(Icons.family_restroom_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Linked Students',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Link siblings into one family group so they can switch dashboards without logging out.',
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
        const Icon(Icons.storage_rounded,
            size: 48, color: Color(0xFFF59E0B)),
        const SizedBox(height: 12),
        Text(_loadError ?? '',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => _load(),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child:
              Text('Retry', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _groupList() {
    if (_groups.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Icon(Icons.group_outlined,
              size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No linked groups yet.',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 6),
          Text('Tap "Add New Linked Group" to link siblings together.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade500)),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _groupCard(_groups[i], i),
    );
  }

  Widget _groupCard(Map<String, dynamic> group, int index) {
    final gid = (group['id'] ?? '').toString();
    final members = _membersByGroup[gid] ?? const [];
    return FadeInSlide(
      index: index,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E9F6E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.family_restroom_rounded,
                    color: Color(0xFF0E9F6E), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((group['group_name'] ?? 'Family Group').toString(),
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827))),
                      Text('${members.length} student${members.length == 1 ? '' : 's'}',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Colors.grey.shade500)),
                    ]),
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded,
                    color: Color(0xFF1565C0), size: 20),
                tooltip: 'Edit',
                onPressed: () => _openEditor(group: group),
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded,
                    color: Color(0xFFEF4444), size: 20),
                tooltip: 'Delete group',
                onPressed: () => _confirmDelete(group),
              ),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (members.isEmpty)
              Text('No students in this group yet.',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade500)),
            for (final m in members) _memberTile(group, m),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(
      Map<String, dynamic> group, Map<String, dynamic> student) {
    final photo = LinkedStudentService.photoUrlOf(student);
    final suspended =
        (student['status'] ?? '').toString().trim().toLowerCase() ==
            'suspended';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor:
              const Color(0xFF1565C0).withValues(alpha: 0.1),
          backgroundImage:
              photo.isNotEmpty ? NetworkImage(photo) : null,
          onBackgroundImageError:
              photo.isNotEmpty ? (_, _) {} : null,
          child: photo.isEmpty
              ? Text(
                  LinkedStudentService.initialsOf(
                      (student['full_name'] ?? '').toString()),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1565C0)),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((student['full_name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(
                        LinkedStudentService.prettySection(
                            (student['section'] ?? '').toString()),
                        const Color(0xFF1565C0)),
                    if (((student['student_id_number'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty))
                      _chip(
                          (student['student_id_number'] ?? '').toString(),
                          const Color(0xFF6B7280)),
                    if (suspended)
                      _chip('Suspended', const Color(0xFFEF4444)),
                  ],
                ),
              ]),
        ),
        IconButton(
          icon: const Icon(Icons.person_remove_rounded,
              color: Color(0xFFEF4444), size: 20),
          tooltip: 'Remove student',
          onPressed: () => _removeMember(group, student),
        ),
      ]),
    );
  }

  Widget _chip(String text, Color color) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

/// Bottom sheet: create or edit one linked group.
///
/// Search (name / Student ID / username) → tick students → Save. The link
/// becomes active only after Save completes.
class _GroupEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? group;
  final String adminId;
  final List<Map<String, dynamic>> initialMembers;
  const _GroupEditorSheet({
    required this.adminId,
    this.group,
    this.initialMembers = const [],
  });

  @override
  State<_GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends State<_GroupEditorSheet> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _results = [];
  final Map<String, Map<String, dynamic>> _selected = {};
  bool _isSearching = false;
  bool _isSaving = false;

  bool get _isEdit => widget.group != null;

  @override
  void initState() {
    super.initState();
    _nameController.text =
        (widget.group?['group_name'] ?? '').toString();
    for (final m in widget.initialMembers) {
      final id = (m['id'] ?? '').toString();
      if (id.isNotEmpty) _selected[id] = Map<String, dynamic>.from(m);
    }
    _search('');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String query) async {
    setState(() => _isSearching = true);
    final rows = await LinkedStudentService.searchStudents(query);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _isSearching = false;
    });
  }

  void _toggle(Map<String, dynamic> student) {
    final id = (student['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = Map<String, dynamic>.from(student);
      }
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Select at least 2 students to link.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      bool ok;
      if (_isEdit) {
        final gid = (widget.group!['id'] ?? '').toString();
        final renamed = await LinkedStudentService.renameGroup(
            groupId: gid, groupName: _nameController.text);
        final members = await LinkedStudentService.setGroupMembers(
            groupId: gid, studentIds: _selected.keys.toList());
        ok = renamed && members;
      } else {
        final gid = await LinkedStudentService.createGroup(
          groupName: _nameController.text,
          studentIds: _selected.keys.toList(),
          adminId: widget.adminId,
        );
        ok = gid.isNotEmpty;
      }
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isEdit
                    ? 'Linked group updated.'
                    : 'Linked group created. Switching is now active.',
                style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF0E9F6E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save. Please try again.',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF0F4F8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(
                    _isEdit
                        ? 'Edit Linked Group'
                        : 'Create Linked Group',
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E9F6E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_selected.length} selected',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0E9F6E))),
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Group name (e.g. Sharma Family)',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.group_rounded,
                    color: Color(0xFF0E9F6E)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF0E9F6E), width: 2)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search name, Student ID or username...',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
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
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selected.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s =
                        _selected.values.elementAt(i);
                    return Container(
                      padding: const EdgeInsets.only(
                          left: 10, right: 6, top: 6, bottom: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E9F6E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                ((s['full_name'] ?? '') as String)
                                            .trim()
                                            .isEmpty
                                    ? (s['username'] ?? '').toString()
                                    : (s['full_name'] ?? '').toString(),
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _toggle(s),
                              child: const Icon(
                                  Icons.cancel_rounded,
                                  size: 18,
                                  color: Colors.white),
                            ),
                          ]),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1565C0)))
                  : _results.isEmpty
                      ? Center(
                          child: Text('No students found.',
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade500)),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _results.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _resultTile(_results[i]),
                        ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E9F6E),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF0E9F6E)
                          .withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        _isEdit
                            ? 'Save Changes'
                            : 'Create Link (${_selected.length})',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(Map<String, dynamic> student) {
    final id = (student['id'] ?? '').toString();
    final checked = _selected.containsKey(id);
    final photo = LinkedStudentService.photoUrlOf(student);
    return GestureDetector(
      onTap: () => _toggle(student),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked
              ? const Color(0xFF0E9F6E).withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: checked
                  ? const Color(0xFF0E9F6E)
                  : Colors.grey.shade200,
              width: checked ? 1.5 : 1),
        ),
        child: Row(children: [
          Checkbox(
            value: checked,
            onChanged: (_) => _toggle(student),
            activeColor: const Color(0xFF0E9F6E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6)),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1565C0)
                .withValues(alpha: 0.1),
            backgroundImage:
                photo.isNotEmpty ? NetworkImage(photo) : null,
            onBackgroundImageError:
                photo.isNotEmpty ? (_, _) {} : null,
            child: photo.isEmpty
                ? Text(
                    LinkedStudentService.initialsOf(
                        (student['full_name'] ?? '').toString()),
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0)),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((student['full_name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 2),
                  Text(
                      '@${(student['username'] ?? '').toString()}'
                      '${((student['student_id_number'] ?? '').toString().trim().isNotEmpty) ? '  •  ${(student['student_id_number'] ?? '').toString()}' : ''}'
                      '  •  ${LinkedStudentService.prettySection((student['section'] ?? '').toString())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: Colors.grey.shade500)),
                ]),
          ),
        ]),
      ),
    );
  }
}
