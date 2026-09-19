import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/alert_service.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';

/// Admin Dashboard → Management → Alerts.
///
/// Create / publish urgent & important alerts with exact audience +
/// section targeting. Published alerts live EXACTLY 24 hours
/// (expires_at = published_at + 24h, fixed — no extension option).
/// Drafts never reach users. Expired rows stay for audit, marked
/// "Expired". Realtime INSERT/UPDATE/DELETE propagates to dashboards.
class AdminAlertsPage extends StatefulWidget {
  final String adminName;
  const AdminAlertsPage({super.key, this.adminName = ''});

  @override
  State<AdminAlertsPage> createState() => _AdminAlertsPageState();
}

class _AdminAlertsPageState extends State<AdminAlertsPage> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  bool _isLoading = true;
  String? _loadError;
  String _search = '';
  String _filterType = '';
  String _filterAudience = '';
  String _filterSection = '';
  String _filterStatus = '';
  String _adminId = '';
  StreamSubscription? _alertSub;

  @override
  void initState() {
    super.initState();
    _init();
    _watchRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _alertSub?.cancel();
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
      _alertSub = Supabase.instance.client
          .from(AlertService.table)
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
      final rows = await AlertService.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load alerts. Run supabase/alerts.sql once, then retry. ($e)';
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

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((a) {
      if (q.isNotEmpty) {
        final title = (a['title'] ?? '').toString().toLowerCase();
        final msg = (a['message'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !msg.contains(q)) return false;
      }
      if (_filterType.isNotEmpty &&
          AlertService.normalizeType((a['alert_type'] ?? '').toString()) !=
              _filterType) {
        return false;
      }
      if (_filterAudience.isNotEmpty &&
          AlertService.normalizeSendTo((a['send_to'] ?? '').toString()) !=
              _filterAudience) {
        return false;
      }
      if (_filterSection.isNotEmpty &&
          AlertService.normalizeTargetSection(
                  (a['section'] ?? '').toString()) !=
              _filterSection) {
        return false;
      }
      if (_filterStatus.isNotEmpty) {
        final status = (a['status'] ?? '').toString();
        if (_filterStatus == 'expired') {
          if (!(status == AlertService.statusPublished &&
              AlertService.isExpired(a))) {
            return false;
          }
        } else if (status != _filterStatus) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _openEditor({Map<String, dynamic>? alert}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlertEditorSheet(
        alert: alert,
        adminId: _adminId,
      ),
    );
    if (saved == true && mounted) {
      _snack(tr('alert_published'), const Color(0xFF0E9F6E));
      _load(silent: true);
    } else if (saved == false && mounted) {
      _load(silent: true);
    }
  }

  Future<void> _publish(Map<String, dynamic> a) async {
    final ok = await AlertService.publish((a['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack(tr('alert_published'), const Color(0xFF0E9F6E));
      _load(silent: true);
    } else {
      _snack('Could not publish. Please try again.', Colors.red);
    }
  }

  Future<void> _unpublish(Map<String, dynamic> a) async {
    final ok =
        await AlertService.unpublish((a['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Moved back to Draft.', const Color(0xFF0E9F6E));
      _load(silent: true);
    } else {
      _snack('Could not update. Please try again.', Colors.red);
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Alert?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete this alert?',
            style: GoogleFonts.poppins(fontSize: 13.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('c_cancel'),
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
            child: Text(tr('c_delete'),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok =
        await AlertService.remove((a['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Alert deleted.', const Color(0xFF0E9F6E));
      _load(silent: true);
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
        title: Text(tr('nav_alerts'),
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
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: () => _openEditor(),
                            icon: const Icon(
                                Icons.notification_add_rounded,
                                size: 22),
                            label: Text('+ ${tr('alert_create')}',
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFB45309),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _searchBox(),
                        const SizedBox(height: 10),
                        _filters(),
                        const SizedBox(height: 16),
                        Text('All Alerts (${_visible.length})',
                            style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827))),
                        const SizedBox(height: 10),
                        if (_loadError != null)
                          _errorCard()
                        else
                          _list(),
                      ]),
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
            colors: [Color(0xFF7C2D12), Color(0xFFB45309)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB45309).withValues(alpha: 0.3),
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
            child: const Text('🚨', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alert Management',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Published alerts reach users instantly and expire automatically after 24 hours.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _search = v),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: '🔍 Search title or message...',
        hintStyle: GoogleFonts.poppins(
            color: Colors.grey.shade400, fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: Color(0xFF1565C0)),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
    );
  }

  Widget _filters() {
    return Column(
      children: [
        _filterDropdown(
          value: _filterType,
          hint: 'Type: All',
          items: const {
            '': 'Type: All',
            'urgent': 'Urgent',
            'important': 'Important',
            'reminder': 'Reminder',
            'instruction': 'Instruction',
            'general': 'General',
          },
          onChanged: (v) => setState(() => _filterType = v ?? ''),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _filterDropdown(
              value: _filterAudience,
              hint: 'Audience',
              items: const {
                '': 'Audience: All',
                'teachers': 'Teachers',
                'students': 'Students',
                'both': 'Both',
              },
              onChanged: (v) =>
                  setState(() => _filterAudience = v ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _filterDropdown(
              value: _filterSection,
              hint: 'Section',
              items: const {
                '': 'Section: All',
                'sub-junior': 'Sub Junior',
                'junior': 'Junior',
                'senior': 'Senior',
                'all': 'All Sections',
              },
              onChanged: (v) =>
                  setState(() => _filterSection = v ?? ''),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _filterDropdown(
          value: _filterStatus,
          hint: 'Status',
          items: const {
            '': 'Status: All',
            'published': 'Published',
            'draft': 'Draft',
            'expired': 'Expired',
          },
          onChanged: (v) => setState(() => _filterStatus = v ?? ''),
        ),
      ],
    );
  }

  Widget _filterDropdown({
    required String value,
    required String hint,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: GoogleFonts.poppins(
              fontSize: 13, color: const Color(0xFF111827)),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
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
          child: Text(tr('c_retry'),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _list() {
    final items = _visible;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('🔕', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text('${tr('alert_no_alerts')}\n${tr('alert_caught_up')}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _card(items[i], i),
    );
  }

  Widget _card(Map<String, dynamic> a, int index) {
    final published =
        (a['status'] ?? '') == AlertService.statusPublished;
    final expired =
        published && AlertService.isExpired(a);
    final color = expired
        ? Colors.grey
        : published
            ? const Color(0xFF0E9F6E)
            : const Color(0xFFF59E0B);
    return FadeInSlide(
      index: index % 6,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text((a['title'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                      expired
                          ? '● ${tr('alert_expired')}'
                          : published
                              ? '● ${tr('alert_published_st')}'
                              : '● ${tr('alert_draft')}',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ),
              ]),
              const SizedBox(height: 4),
              Text((a['message'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(
                  '${AlertService.prettyType((a['alert_type'] ?? '').toString())} · ${AlertService.prettySendTo((a['send_to'] ?? '').toString())} · ${AlertService.prettySection((a['section'] ?? '').toString())}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade500)),
              if (published) ...[
                Text(
                    'Published: ${AlertService.prettyDateTime((a['published_at'] ?? '').toString())}  •  Expires: ${AlertService.prettyDateTime((a['expires_at'] ?? '').toString())}',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, color: Colors.grey.shade500)),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _action(tr('c_view'), Icons.visibility_rounded,
                    const Color(0xFF1565C0), () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Text((a['title'] ?? '').toString(),
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      content: SingleChildScrollView(
                        child: Text((a['message'] ?? '').toString(),
                            style: GoogleFonts.poppins(
                                fontSize: 14, height: 1.6)),
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text(tr('c_close'),
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );
                }),
                if (!published)
                  _action(tr('c_edit'), Icons.edit_rounded,
                      const Color(0xFF6D28D9),
                      () => _openEditor(alert: a)),
                if (!published)
                  _action(tr('alert_publish'),
                      Icons.send_rounded, const Color(0xFF0E9F6E),
                      () => _publish(a))
                else
                  _action('Unpublish', Icons.undo_rounded,
                      const Color(0xFFB45309),
                      () => _unpublish(a)),
                _action(tr('c_delete'), Icons.delete_rounded,
                    const Color(0xFFEF4444), () => _delete(a)),
              ]),
            ]),
      ),
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

/// Bottom sheet: create (Save Draft / Publish) or edit an alert.
class _AlertEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? alert;
  final String adminId;
  const _AlertEditorSheet({required this.adminId, this.alert});

  @override
  State<_AlertEditorSheet> createState() => _AlertEditorSheetState();
}

class _AlertEditorSheetState extends State<_AlertEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  String _type = AlertService.typeGeneral;
  String _sendTo = AlertService.toBoth;
  String _section = 'all';
  bool _isSaving = false;

  bool get _isEdit => widget.alert != null;

  @override
  void initState() {
    super.initState();
    final a = widget.alert;
    if (a != null) {
      _titleController.text = (a['title'] ?? '').toString();
      _messageController.text = (a['message'] ?? '').toString();
      _type = AlertService.normalizeType(
          (a['alert_type'] ?? '').toString());
      _sendTo = AlertService.normalizeSendTo(
          (a['send_to'] ?? '').toString());
      _section = AlertService.normalizeTargetSection(
          (a['section'] ?? '').toString());
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _save({required bool publish}) async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      if (_isEdit) {
        final ok = await AlertService.update(
          alertId: (widget.alert!['id'] ?? '').toString(),
          title: _titleController.text,
          message: _messageController.text,
          alertType: _type,
          sendTo: _sendTo,
          section: _section,
        );
        if (!mounted) return;
        if (ok) {
          Navigator.pop(context, false); // edited — no publish toast
        } else {
          _snack('Could not save. Please try again.', Colors.red);
        }
        return;
      }
      final id = await AlertService.create(
        title: _titleController.text,
        message: _messageController.text,
        alertType: _type,
        sendTo: _sendTo,
        section: _section,
        adminId: widget.adminId,
        publishNow: publish,
      );
      if (!mounted) return;
      if (id.isEmpty) {
        _snack('Could not save. Please try again.', Colors.red);
        return;
      }
      Navigator.pop(context, publish); // true → "Alert Published Successfully"
      if (!publish) {
        _snack('Draft saved.', const Color(0xFF0E9F6E));
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
        child: SingleChildScrollView(
          controller: scrollController,
          child: Form(
            key: _formKey,
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
                  const SizedBox(height: 14),
                  Text(
                      _isEdit
                          ? '${tr('c_edit')} Alert'
                          : tr('alert_create'),
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 14),
                  _label(tr('alert_title')),
                  TextFormField(
                    controller: _titleController,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: _dec('e.g. Important Reminder'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty
                            ? 'Please enter a title.'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  _label(tr('alert_message')),
                  TextFormField(
                    controller: _messageController,
                    maxLines: 5,
                    style: GoogleFonts.poppins(
                        fontSize: 14, height: 1.6),
                    decoration: _dec(
                        'e.g. Please bring your Bible and notebook this Saturday.'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty
                            ? 'Please enter a message.'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  _label(tr('alert_type')),
                  _dropdown(
                    value: _type,
                    items: const {
                      'important': '❗ Important',
                      'reminder': '🔔 Reminder',
                      'instruction': '📋 Instruction',
                      'urgent': '🚨 Urgent',
                      'general': '📢 General',
                    },
                    onChanged: (v) =>
                        setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 12),
                  _label(tr('alert_send_to')),
                  _dropdown(
                    value: _sendTo,
                    items: {
                      'teachers': '👩‍🏫 ${tr('alert_teachers')}',
                      'students': '🎒 ${tr('alert_students')}',
                      'both': '👥 ${tr('alert_both')}',
                    },
                    onChanged: (v) =>
                        setState(() => _sendTo = v ?? _sendTo),
                  ),
                  const SizedBox(height: 12),
                  _label(tr('c_section')),
                  _dropdown(
                    value: _section,
                    items: const {
                      'sub-junior': 'Sub Junior',
                      'junior': 'Junior',
                      'senior': 'Senior',
                      'all': 'All Sections',
                    },
                    onChanged: (v) =>
                        setState(() => _section = v ?? _section),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB45309)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFB45309)
                              .withValues(alpha: 0.25)),
                    ),
                    child: Text(
                        '⏱️ Published alerts are visible for exactly 24 hours, then expire automatically.',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF92400E))),
                  ),
                  const SizedBox(height: 16),
                  if (_isEdit)
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed:
                            _isSaving ? null : () => _save(publish: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5))
                            : Text(tr('c_save'),
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                      ),
                    )
                  else
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => _save(publish: false),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              side: const BorderSide(
                                  color: Color(0xFF1565C0)),
                              padding:
                                  const EdgeInsets.symmetric(
                                      vertical: 14),
                            ),
                            child: Text('Save Draft',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    color:
                                        const Color(0xFF1565C0))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isSaving
                                ? null
                                : () => _save(publish: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFB45309),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child:
                                        CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5))
                                : Text(tr('alert_publish'),
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight:
                                            FontWeight.w700)),
                          ),
                        ),
                      ),
                    ]),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  InputDecoration _dec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
          color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _dropdown({
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: GoogleFonts.poppins(
              fontSize: 14, color: const Color(0xFF111827)),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
