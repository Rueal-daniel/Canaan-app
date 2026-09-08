import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/leave_service.dart';
import '../../services/seen_store.dart';
import '../../widgets/animations.dart';

/// Teacher Dashboard → Quick Links → Student Applications.
///
/// Read-only. Shows ONLY applications Admin approved AND sent,
/// filtered to the teacher's own section at the query level.
/// Teachers cannot approve, reject or edit anything here.
class TeacherStudentApplicationsPage extends StatefulWidget {
  final String section;
  const TeacherStudentApplicationsPage({super.key, required this.section});

  @override
  State<TeacherStudentApplicationsPage> createState() =>
      _TeacherStudentApplicationsPageState();
}

class _TeacherStudentApplicationsPageState
    extends State<TeacherStudentApplicationsPage> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _loadError;
  StreamSubscription? _realtimeSub;

  String get _section => LeaveService.normalizeSection(widget.section);

  @override
  void initState() {
    super.initState();
    _fetchItems();
    try {
      _realtimeSub = _client
          .from(LeaveService.table)
          .stream(primaryKey: ['id'])
          .eq('section', _section)
          .listen((_) {
            if (mounted) _fetchItems(silent: true);
          });
    } catch (_) {}
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchItems({bool silent = false}) async {
    if (_section.isEmpty) {
      if (mounted) {
        setState(() {
          _items = [];
          _isLoading = false;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(LeaveService.table)
          .select('*')
          .eq('section', _section)
          .eq('sent_to_teacher', true)
          .order('sent_to_teacher_at', ascending: false);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
        SeenStore.markSeen('seen_teacher_sentapps',
            _items.map((m) => (m['id'] ?? '').toString()));
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load applications. Check your connection. ($e)';
        });
      }
    }
  }

  void _viewApplication(Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => SingleChildScrollView(
          controller: controller,
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
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Text('📨 ${(m['student_name'] ?? '').toString()}',
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _kv('Section',
                  LeaveService.prettySection(m['section']?.toString())),
              _kv('Application Date',
                  LeaveService.prettyDate(m['application_date']?.toString())),
              _kv('From Date',
                  LeaveService.prettyDate(m['from_date']?.toString())),
              _kv('Approval Status',
                  LeaveService.prettyStatus(m['status']?.toString())),
              _kv('Sent to Teacher',
                  LeaveService.prettyDate(
                      m['sent_to_teacher_at']?.toString())),
              const SizedBox(height: 12),
              Text('Description',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6B7280))),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Text((m['description'] ?? '').toString(),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        height: 1.6,
                        color: const Color(0xFF1F2937))),
              ),
              if ((m['admin_comment'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Admin Comment',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6B7280))),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E)
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text((m['admin_comment'] ?? '').toString(),
                      style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: const Color(0xFF1F2937))),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Close',
                      style:
                          GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: const Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(value.isEmpty ? '—' : value,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF111827))),
        ),
      ]),
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
        title: Text('Student Applications',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchItems(),
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Text(
                    'Approved leave applications sent for your section (${LeaveService.prettySection(_section)}).',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade600)),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF1565C0))),
                )
              else if (_loadError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18)),
                  child: Text(_loadError!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.grey.shade600)),
                )
              else if (_items.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 44, horizontal: 24),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    const Text('📨', style: TextStyle(fontSize: 44)),
                    const SizedBox(height: 12),
                    Text('No applications sent to you yet.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF374151))),
                  ]),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final m = _items[i];
                    return FadeInSlide(
                      index: 0,
                      child: GestureDetector(
                        onTap: () => _viewApplication(m),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFFF1F5F9)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                  Icons.event_note_rounded,
                                  color: Color(0xFF15803D),
                                  size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        (m['student_name'] ?? '')
                                            .toString(),
                                        style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(
                                                0xFF111827))),
                                    const SizedBox(height: 2),
                                    Text(
                                        'From: ${LeaveService.prettyDate(m['from_date']?.toString())} • ✅ Approved',
                                        style: GoogleFonts.poppins(
                                            fontSize: 12.5,
                                            color:
                                                Colors.grey.shade600)),
                                  ]),
                            ),
                            const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: Colors.grey),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
