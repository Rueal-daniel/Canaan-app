import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/notice_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/notice_rich_text.dart';

/// Admin → Management → Notice Board.
///
/// Creates and publishes formatted notices to the existing
/// `notices` table with realtime delivery to teachers/students.
class AdminNoticeBoardPage extends StatefulWidget {
  final String adminName;
  const AdminNoticeBoardPage({super.key, this.adminName = ''});

  @override
  State<AdminNoticeBoardPage> createState() => _AdminNoticeBoardPageState();
}

class _AdminNoticeBoardPageState extends State<AdminNoticeBoardPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();

  String _html = '';
  int _composerKey = 0;
  String _audience = NoticeService.audienceAll;

  bool _showForm = false;
  bool _isPublishing = false;
  bool _isLoading = true;
  String? _loadError;

  List<Map<String, dynamic>> _notices = [];
  StreamSubscription? _realtimeSub;
  int? _editingId;

  @override
  void initState() {
    super.initState();
    _fetchNotices();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(NoticeService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchNotices(silent: true);
          });
    } catch (_) {}
  }

  Future<void> _fetchNotices({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(NoticeService.table)
          .select('*')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _notices = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load notices. Check your connection and try again. ($e)';
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

  Future<Map<String, String?>> _adminIdentity() async {
    var name = widget.adminName;
    String? id;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        id = session.userId;
        if (name.isEmpty) {
          final auth = AuthService();
          final profile = await auth.getUserById(
              userId: session.userId, role: UserRole.admin);
          name = (profile?['full_name'] ?? '').toString();
        }
      }
    } catch (_) {}
    return {'name': name.isEmpty ? 'Admin' : name, 'id': id};
  }

  Future<void> _publish() async {
    if (_isPublishing) return;
    if (!_formKey.currentState!.validate()) return;
    if (noticeHtmlIsEmpty(_html)) {
      _snack('Please write the notice content.', Colors.orange);
      return;
    }
    setState(() => _isPublishing = true);
    try {
      final identity = await _adminIdentity();
      final now = DateTime.now().toIso8601String();
      if (_editingId != null) {
        await _client.from(NoticeService.table).update({
          'title': _titleController.text.trim(),
          'content': _html,
          'audience': _audience,
          'updated_at': now,
        }).eq('id', _editingId!);
        _snack('✅ Notice updated successfully!', Colors.green);
      } else {
        final insert = <String, dynamic>{
          'title': _titleController.text.trim(),
          'content': _html,
          'audience': _audience,
          'status': 'published',
          'created_by': identity['name'],
          'published_at': now,
          'updated_at': now,
        };
        if ((identity['id'] ?? '').isNotEmpty) {
          insert['created_by_id'] = identity['id'];
        }
        try {
          await _client.from(NoticeService.table).insert(insert);
        } catch (_) {
          // created_by_id type may differ — retry without it.
          insert.remove('created_by_id');
          await _client.from(NoticeService.table).insert(insert);
        }
        _snack('✅ Notice published successfully!', Colors.green);
      }
      _resetForm();
      await _fetchNotices(silent: true);
    } catch (e) {
      _snack('Could not publish. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    if (mounted) {
      setState(() {
        _html = '';
        _composerKey++;
        _audience = NoticeService.audienceAll;
        _editingId = null;
        _showForm = false;
      });
    }
  }

  void _startEdit(Map<String, dynamic> notice) {
    _titleController.text = (notice['title'] ?? '').toString();
    setState(() {
      _html = (notice['content'] ?? '').toString();
      _composerKey++;
      _audience =
          NoticeService.normalizeAudience(notice['audience']?.toString());
      _editingId = (notice['id'] as num?)?.toInt();
      _showForm = true;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    _snack('Editing mode — formatting is preserved.',
        const Color(0xFF1565C0));
  }

  void _confirmDelete(Map<String, dynamic> notice) {
    final id = (notice['id'] as num?)?.toInt();
    if (id == null) return;
    final title = (notice['title'] ?? 'this notice').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Notice?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Are you sure you want to delete "$title"?',
            style:
                GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _client
                    .from(NoticeService.table)
                    .delete()
                    .eq('id', id);
                if (_editingId == id) _resetForm();
                await _fetchNotices(silent: true);
                _snack('Notice deleted.', Colors.green);
              } catch (e) {
                _snack('Could not delete. Please try again. ($e)', Colors.red);
              }
            },
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
  }

  void _viewNotice(Map<String, dynamic> notice) {
    showNoticeDialog(
      context,
      title: (notice['title'] ?? '').toString(),
      html: (notice['content'] ?? '').toString(),
      dateTimeLabel: NoticeService.prettyDateTime(
          (notice['published_at'] ?? notice['created_at'])?.toString()),
      audienceLabel:
          'Audience: ${NoticeService.prettyAudience(notice['audience']?.toString())}',
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
        title: Text('Notice Board',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchNotices(),
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              if (_showForm)
                _formCard()
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showForm = true;
                        _editingId = null;
                      });
                    },
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: Text('+ Create Notice',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text('Published Notices (${_notices.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _historyList(),
            ],
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
            colors: [Color(0xFFB45309), Color(0xFFF59E0B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
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
            child: const Icon(Icons.campaign_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notice Board',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Create and share important notices with teachers and students.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  Widget _formCard() {
    final isEditing = _editingId != null;
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(isEditing ? 'Edit Notice' : 'Create Notice',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                TextButton.icon(
                  onPressed: _isPublishing ? null : _resetForm,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label:
                      Text('Cancel', style: GoogleFonts.poppins(fontSize: 12.5)),
                ),
              ]),
              const SizedBox(height: 14),
              _fieldLabel('Title'),
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Title', 'Enter notice title'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Notice Content'),
              NoticeComposer(
                key: ValueKey(_composerKey),
                initialHtml: _html,
                onChanged: (html) => _html = html,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Send To'),
              _audienceRadios(),
              const SizedBox(height: 18),
              if (_isPublishing) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    color: Color(0xFF1565C0),
                    backgroundColor: Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Publishing notice…',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isPublishing ? null : _publish,
                  icon: _isPublishing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.campaign_rounded, size: 20),
                  label: Text(
                    isEditing ? 'Update Notice' : '📢 Publish Notice',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1565C0)
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _audienceRadios() {
    final options = [
      (NoticeService.audienceAll, 'All'),
      (NoticeService.audienceTeachers, 'Teachers'),
      (NoticeService.audienceStudents, 'Students'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: RadioGroup<String>(
        groupValue: _audience,
        onChanged: (v) {
          if (_isPublishing || v == null) return;
          setState(() => _audience = v);
        },
        child: Column(children: [
          for (final (value, label) in options)
            RadioListTile<String>(
              value: value,
              title: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF111827))),
              activeColor: const Color(0xFF1565C0),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
            ),
        ]),
      ),
    );
  }

  Widget _historyList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
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
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _fetchNotices(),
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
    if (_notices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Icon(Icons.campaign_outlined,
              size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No notices published yet.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 4),
          Text('Tap + Create Notice to share your first notice.',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade500)),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _notices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _noticeCard(_notices[i]),
    );
  }

  Widget _noticeCard(Map<String, dynamic> notice) {
    final id = (notice['id'] as num?)?.toInt();
    final isEditingThis = _editingId == id && _editingId != null;
    final preview = NoticeService.plainTextOf(
        (notice['content'] ?? '').toString());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(
                color: isEditingThis
                    ? const Color(0xFF1565C0)
                    : const Color(0xFFF59E0B),
                width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📢 ${(notice['title'] ?? '').toString()}',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(
              'Audience: ${NoticeService.prettyAudience(notice['audience']?.toString())}',
              const Color(0xFF7B1FA2)),
          _pill(
              'Published: ${NoticeService.prettyDate((notice['published_at'] ?? notice['created_at'])?.toString())}',
              Colors.grey.shade600),
        ]),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 13, height: 1.6, color: const Color(0xFF374151))),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _viewNotice(notice),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF1565C0)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text('View',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                color: Color(0xFF1565C0), size: 20),
            tooltip: 'Edit',
            onPressed: () => _startEdit(notice),
          ),
          IconButton(
            icon:
                const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(notice),
          ),
        ]),
      ]),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
