import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/certificate_service.dart';
import '../../services/leaderboard_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/certificate_view.dart';

/// Admin → Students → Certificates.
///
/// Issues achievement certificates for REAL Rank 1/2/3 leaderboard
/// finishes (Attendance / Memory Verse, per section). Eligibility is
/// re-verified against the LIVE leaderboard at save time, so a Rank 5
/// student can never receive a "1st Position" certificate.
///
/// Drafts are Admin-only; only Published certificates (with a student
/// notification) become visible to students/teachers. Published rows are
/// snapshots — later leaderboard changes never mutate them.
class AdminCertificatesPage extends StatefulWidget {
  const AdminCertificatesPage({super.key});

  @override
  State<AdminCertificatesPage> createState() => _AdminCertificatesPageState();
}

class _AdminCertificatesPageState extends State<AdminCertificatesPage> {
  String _section = 'junior';
  bool _memory = false;

  List<LeaderboardEntry> _top = [];
  bool _loadingTop = true;
  List<Map<String, dynamic>> _all = [];
  bool _loadingAll = true;
  String? _loadError;
  String _adminId = '';
  StreamSubscription? _certSub;

  @override
  void initState() {
    super.initState();
    _init();
    _watchRealtime();
  }

  @override
  void dispose() {
    _certSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        _adminId = session.userId;
      }
    } catch (_) {}
    await Future.wait([_loadTop(), _loadAll()]);
  }

  void _watchRealtime() {
    try {
      _certSub = Supabase.instance.client
          .from(CertificateService.table)
          .stream(primaryKey: ['id']).listen((_) {
        if (mounted) _loadAll(silent: true);
      });
    } catch (_) {}
  }

  Future<void> _loadTop() async {
    if (mounted) setState(() => _loadingTop = true);
    try {
      final entries = await LeaderboardService.compute(
        section: _section,
        memory: _memory,
      );
      if (!mounted) return;
      setState(() {
        _top = entries.where((e) => e.rank >= 1 && e.rank <= 3).toList();
        _loadingTop = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTop = false);
    }
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loadingAll = true;
        _loadError = null;
      });
    }
    try {
      final rows = await CertificateService.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loadingAll = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loadingAll = false;
          _loadError =
              'Could not load certificates. Run supabase/certificates.sql once, then retry. ($e)';
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

  bool _hasCert(String studentId, int position) {
    final cat = _memory
        ? CertificateService.categoryMemoryVerse
        : CertificateService.categoryAttendance;
    return _all.any((c) =>
        (c['student_id'] ?? '').toString() == studentId &&
        (c['category'] ?? '').toString() == cat &&
        ((c['position'] as num?)?.toInt() ?? 0) == position &&
        CertificateService.normalizeSection(
                (c['section'] ?? '').toString()) ==
            CertificateService.normalizeSection(_section));
  }

  Future<void> _generate(LeaderboardEntry e) async {
    final preview = <String, dynamic>{
      'student_name': e.fullName,
      'position': e.rank,
      'category': _memory
          ? CertificateService.categoryMemoryVerse
          : CertificateService.categoryAttendance,
      'section': e.section,
      'certificate_date': CertificateService.todayStr(),
    };
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CertificateView(certificate: preview),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E9F6E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text('Generate',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (confirm != true) return;
    final id = await CertificateService.createDraft(
      studentId: e.studentId,
      studentName: e.fullName,
      section: e.section.isEmpty ? _section : e.section,
      category: _memory
          ? CertificateService.categoryMemoryVerse
          : CertificateService.categoryAttendance,
      position: e.rank,
      percentage: e.percent ?? 0,
      adminId: _adminId,
    );
    if (!mounted) return;
    if (id.isEmpty) {
      _snack(
          'Not eligible — the live leaderboard no longer ranks this student at that position.',
          Colors.red);
    } else {
      _snack('Certificate saved as Draft. Publish it to notify the student.',
          const Color(0xFF0E9F6E));
      _loadAll(silent: true);
    }
  }

  Future<void> _edit(Map<String, dynamic> cert) async {
    var position = (cert['position'] as num?)?.toInt() ?? 1;
    final dateController = TextEditingController(
        text: (cert['certificate_date'] ?? '').toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Draft',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                'Position is re-verified against the live leaderboard on save.',
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: position.clamp(1, 3),
              items: const [1, 2, 3]
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                            CertificateService.positionLabel(p)),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setSheet(() => position = v ?? position),
              decoration: InputDecoration(
                labelText: 'Position',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dateController,
              decoration: InputDecoration(
                labelText: 'Certificate date (yyyy-MM-dd)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style:
                      GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Save',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    dateController.dispose();
    if (saved != true) return;
    final ok = await CertificateService.updateDraft(
      certificateId: (cert['id'] ?? '').toString(),
      position: position,
      certificateDate: dateController.text,
    );
    if (!mounted) return;
    if (ok) {
      _snack('Draft updated.', const Color(0xFF0E9F6E));
      _loadAll(silent: true);
    } else {
      _snack(
          'Could not save — position no longer matches the live leaderboard.',
          Colors.red);
    }
  }

  Future<void> _publish(Map<String, dynamic> cert) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Publish Certificate?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
            'The student will be notified and the certificate becomes visible on their dashboard. It is then locked as a historical record.',
            style: GoogleFonts.poppins(fontSize: 13.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E9F6E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Publish',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await CertificateService.publish(
        (cert['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Published — student notified.', const Color(0xFF0E9F6E));
      _loadAll(silent: true);
    } else {
      _snack('Could not publish. Please try again.', Colors.red);
    }
  }

  Future<void> _unpublish(Map<String, dynamic> cert) async {
    final ok = await CertificateService.unpublish(
        (cert['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Moved back to Draft (hidden from student).',
          const Color(0xFF0E9F6E));
      _loadAll(silent: true);
    } else {
      _snack('Could not update. Please try again.', Colors.red);
    }
  }

  Future<void> _delete(Map<String, dynamic> cert) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Certificate?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
            'This permanently removes the certificate record.',
            style: GoogleFonts.poppins(fontSize: 13.5)),
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
    final ok =
        await CertificateService.delete((cert['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Certificate deleted.', const Color(0xFF0E9F6E));
      _loadAll(silent: true);
    } else {
      _snack('Could not delete. Please try again.', Colors.red);
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
        title: Text('Certificates',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadTop();
          await _loadAll();
        },
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerCard(),
                const SizedBox(height: 14),
                _categoryToggle(),
                const SizedBox(height: 12),
                _sectionChips(),
                const SizedBox(height: 16),
                Text('Eligible — Rank 1–3 · ${_scopeName()}',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 4),
                Text('Verified against the live leaderboard at generation time.',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500)),
                const SizedBox(height: 10),
                _eligibleSection(),
                const SizedBox(height: 20),
                Text('All Certificates (${_all.length})',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                const SizedBox(height: 10),
                _allSection(),
              ]),
        ),
      ),
    );
  }

  String _scopeName() =>
      '${LeaderboardService.prettySection(_section)} · ${_memory ? 'Memory Verse' : 'Attendance'}';

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
            child: const Icon(Icons.workspace_premium_rounded,
                color: Color(0xFFFFD971), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Achievement Certificates',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Issue certificates for real Rank 1–3 leaderboard finishes. Only published certificates reach students.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _categoryToggle() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF6)),
      ),
      child: Row(children: [
        Expanded(child: _catButton(false, 'Attendance')),
        Expanded(child: _catButton(true, 'Memory Verse')),
      ]),
    );
  }

  Widget _catButton(bool value, String label) {
    final selected = _memory == value;
    return GestureDetector(
      onTap: () {
        if (_memory == value) return;
        setState(() => _memory = value);
        _loadTop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [
                  Color(0xFF0B2A5B),
                  Color(0xFF1565C0),
                ])
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : const Color(0xFF64748B))),
        ),
      ),
    );
  }

  Widget _sectionChips() {
    const options = [
      ('sub-junior', 'Sub Junior'),
      ('junior', 'Junior'),
      ('senior', 'Senior'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          GestureDetector(
            onTap: () {
              if (_section == value) return;
              setState(() => _section = value);
              _loadTop();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: _section == value
                    ? const LinearGradient(colors: [
                        Color(0xFF063B2E),
                        Color(0xFF0E9F6E),
                      ])
                    : null,
                color:
                    _section == value ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _section == value
                        ? Colors.transparent
                        : const Color(0xFFE2E8F0)),
              ),
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _section == value
                          ? Colors.white
                          : const Color(0xFF475569))),
            ),
          ),
      ],
    );
  }

  Widget _eligibleSection() {
    if (_loadingTop) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }
    if (_top.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Text(
            'No ranked students in this section yet.\nCertificates unlock once teachers record attendance/recitations.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13.5, color: Colors.grey.shade500)),
      );
    }
    return Column(
      children: [for (final e in _top) _eligibleCard(e)],
    );
  }

  Widget _eligibleCard(LeaderboardEntry e) {
    final exists = _hasCert(e.studentId, e.rank);
    final medal = e.rank == 1
        ? '🥇'
        : e.rank == 2
            ? '🥈'
            : '🥉';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Text(medal, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        CircleAvatar(
          radius: 20,
          backgroundColor:
              const Color(0xFF1565C0).withValues(alpha: 0.1),
          backgroundImage:
              e.photoUrl.isNotEmpty ? NetworkImage(e.photoUrl) : null,
          onBackgroundImageError:
              e.photoUrl.isNotEmpty ? (_, _) {} : null,
          child: e.photoUrl.isEmpty
              ? Text(LeaderboardService.initialsOf(e.fullName),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1565C0)))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827))),
                Text(
                    'Rank ${e.rank} · ${LeaderboardService.pctLabel(e.percent ?? 0)}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500)),
              ]),
        ),
        ElevatedButton(
          onPressed: exists ? null : () => _generate(e),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0E9F6E),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade200,
            disabledForegroundColor: Colors.grey.shade500,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
          ),
          child: Text(exists ? 'Issued' : 'Generate',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _allSection() {
    if (_loadingAll) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }
    if (_loadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Icon(Icons.storage_rounded,
              size: 48, color: Color(0xFFF59E0B)),
          const SizedBox(height: 12),
          Text(_loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _loadAll(),
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
    if (_all.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Text('No certificates issued yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13.5, color: Colors.grey.shade500)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _all.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _certCard(_all[i]),
    );
  }

  Widget _certCard(Map<String, dynamic> c) {
    final published =
        (c['status'] ?? '') == CertificateService.statusPublished;
    final position = (c['position'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
              color: published
                  ? const Color(0xFF0E9F6E)
                  : const Color(0xFFF59E0B),
              width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text((c['student_name'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827))),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (published
                      ? const Color(0xFF0E9F6E)
                      : const Color(0xFFF59E0B))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(published ? '● Published' : '● Draft',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: published
                        ? const Color(0xFF0E9F6E)
                        : const Color(0xFFB45309))),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            '${CertificateService.categoryLabel((c['category'] ?? '').toString())} · ${CertificateService.positionLabel(position)} · ${CertificateService.prettySection((c['section'] ?? '').toString())}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade600)),
        Text(
            'Date: ${CertificateService.prettyDate((c['certificate_date'] ?? '').toString())}',
            style: GoogleFonts.poppins(
                fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _action('View', Icons.visibility_rounded,
              const Color(0xFF1565C0), () {
            showCertificatePreview(context, c);
          }),
          if (!published) ...[
            _action('Edit', Icons.edit_rounded,
                const Color(0xFF6D28D9), () => _edit(c)),
            _action('Publish', Icons.send_rounded,
                const Color(0xFF0E9F6E), () => _publish(c)),
          ] else
            _action('Unpublish', Icons.undo_rounded,
                const Color(0xFFB45309), () => _unpublish(c)),
          _action('Delete', Icons.delete_rounded,
              const Color(0xFFEF4444), () => _delete(c)),
        ]),
      ]),
    );
  }

  Widget _action(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ]),
      ),
    );
  }
}
