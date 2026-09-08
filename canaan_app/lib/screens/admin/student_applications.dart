import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/leave_service.dart';
import '../../widgets/animations.dart';

/// Admin → Students → Student Application.
///
/// Only applications Admin approved AND sent to teachers, grouped
/// Sub Junior → Junior → Senior.
class AdminStudentApplicationsPage extends StatefulWidget {
  const AdminStudentApplicationsPage({super.key});

  @override
  State<AdminStudentApplicationsPage> createState() =>
      _AdminStudentApplicationsPageState();
}

class _AdminStudentApplicationsPageState
    extends State<AdminStudentApplicationsPage> {
  final _client = Supabase.instance.client;

  static const _sections = ['sub-junior', 'junior', 'senior'];

  List<Map<String, dynamic>> _all = [];
  bool _isLoading = true;
  String? _loadError;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _fetchAll();
    try {
      _realtimeSub = _client
          .from(LeaveService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchAll(silent: true);
          });
    } catch (_) {}
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchAll({bool silent = false}) async {
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
          .eq('sent_to_teacher', true)
          .order('sent_to_teacher_at', ascending: false);
      if (mounted) {
        setState(() {
          _all = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load applications. Check your connection. ($e)';
        });
      }
    }
  }

  List<Map<String, dynamic>> _forSection(String section) => _all
      .where((m) =>
          LeaveService.normalizeSection(m['section']?.toString()) ==
          section)
      .toList();

  void _viewApplication(Map<String, dynamic> m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.92,
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
              Text('📨 ${(m['student_name'] ?? '').toString()} — Leave Application',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _kv('Section',
                  LeaveService.prettySection(m['section']?.toString())),
              _kv('Application Date',
                  LeaveService.prettyDate(m['application_date']?.toString())),
              _kv('From Date',
                  LeaveService.prettyDate(m['from_date']?.toString())),
              _kv('Status',
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
        title: Text('Student Application',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchAll(),
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approved & sent to teachers',
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, color: Colors.grey.shade600)),
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
              else
                for (final s in _sections) ...[
                  _sectionBlock(s),
                  const SizedBox(height: 16),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBlock(String section) {
    final items = _forSection(section);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Text(LeaveService.prettySection(section),
              style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827))),
        ),
        Text('${items.length}',
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade500)),
      ]),
      const SizedBox(height: 10),
      if (items.isEmpty)
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16)),
          child: Text('Nothing sent yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade500)),
        )
      else
        for (final m in items) ...[
          FadeInSlide(
            index: 0,
            child: GestureDetector(
              onTap: () => _viewApplication(m),
              child: Container(
                width: double.infinity,
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
                child: Row(children: [
                  const Icon(Icons.send_rounded,
                      size: 20, color: Color(0xFF22C55E)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${(m['student_name'] ?? '').toString()} — Leave Application',
                              style: GoogleFonts.poppins(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827))),
                          const SizedBox(height: 2),
                          Text(
                              'From: ${LeaveService.prettyDate(m['from_date']?.toString())}',
                              style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade600)),
                        ]),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 16, color: Colors.grey),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
    ]);
  }
}
