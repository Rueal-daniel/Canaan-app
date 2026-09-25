import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_update_service.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/notification_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/notice_rich_text.dart';

/// Admin → Management → Update Link.
///
/// Publish app updates (title, formatted description, APK URL,
/// version, optional/required). The ACTIVE update is the latest
/// published row; dashboards prompt only when its versionCode
/// exceeds the installed one. Publishing also notifies the bell.
class AdminUpdateLinkPage extends StatefulWidget {
  final String adminName;
  const AdminUpdateLinkPage({super.key, this.adminName = ''});

  @override
  State<AdminUpdateLinkPage> createState() => _AdminUpdateLinkPageState();
}

class _AdminUpdateLinkPageState extends State<AdminUpdateLinkPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _apkController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  String _html = '';
  int _composerKey = 0;
  bool _forceUpdate = false;

  bool _showForm = false;
  bool _isPublishing = false;
  bool _isLoading = true;
  String? _loadError;

  List<Map<String, dynamic>> _history = [];
  StreamSubscription? _realtimeSub;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    try {
      _realtimeSub = _client
          .from(AppUpdateService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchHistory(silent: true);
          });
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _apkController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchHistory({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await AppUpdateService.fetchHistory();
      if (mounted) {
        setState(() {
          _history = rows;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load updates. Check your connection and try again. ($e)';
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

  Future<String?> _adminId() async {
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        return session.userId;
      }
    } catch (_) {}
    return null;
  }

  bool _validApkUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.path.toLowerCase().endsWith('.apk') &&
        uri.userInfo.isEmpty;
  }

  Future<void> _publish({required bool publishNow}) async {
    if (_isPublishing) return;
    if (!_formKey.currentState!.validate()) return;
    if (noticeHtmlIsEmpty(_html)) {
      _snack('Please write the update description.', Colors.orange);
      return;
    }
    final apkUrl = _apkController.text.trim();
    if (!_validApkUrl(apkUrl)) {
      _snack(
          'APK link must be an HTTPS URL ending in .apk.', Colors.orange);
      return;
    }
    final versionName = _nameController.text.trim();
    final versionCode = int.tryParse(_codeController.text.trim());
    if (versionName.isEmpty) {
      _snack('Please enter the version name.', Colors.orange);
      return;
    }
    if (versionCode == null || versionCode <= 0) {
      _snack('Version code must be a positive whole number.', Colors.orange);
      return;
    }
    setState(() => _isPublishing = true);
    try {
      final adminId = await _adminId();
      final now = DateTime.now().toIso8601String();
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _html,
        'apk_url': apkUrl,
        'version_name': versionName,
        'version_code': versionCode,
        'force_update': _forceUpdate,
        'status': publishNow
            ? AppUpdateService.statusPublished
            : AppUpdateService.statusDraft,
        'updated_at': now,
      };
      if (publishNow) payload['published_at'] = now;
      if (adminId != null && adminId.isNotEmpty) {
        payload['created_by'] = adminId;
      }
      String updateId;
      if (_editingId != null && _editingId!.isNotEmpty) {
        // created_by is UUID — omit when the id is not a UUID.
        try {
          await _client
              .from(AppUpdateService.table)
              .update(payload)
              .eq('id', _editingId!);
        } catch (_) {
          payload.remove('created_by');
          await _client
              .from(AppUpdateService.table)
              .update(payload)
              .eq('id', _editingId!);
        }
        updateId = _editingId!;
      } else {
        Map<String, dynamic>? created;
        try {
          created = await _client
              .from(AppUpdateService.table)
              .insert(payload)
              .select('id')
              .single();
        } catch (_) {
          payload.remove('created_by');
          created = await _client
              .from(AppUpdateService.table)
              .insert(payload)
              .select('id')
              .single();
        }
        updateId = (created['id'] ?? '').toString();
      }
      if (publishNow && mounted) {
        // Bell announcement (never downloads anything by itself).
        try {
          await NotificationService.publish(
            type: NotificationService.typeAppUpdate,
            title: '🚀 New App Update Available',
            message:
                'Version $versionName is available. Tap to view and update.',
            relatedId: 'app_update:$updateId',
            destination: NotificationService.destAppUpdate,
            audience: NotificationService.audienceAll,
          );
        } catch (_) {}
      }
      _snack(
          publishNow
              ? 'Update Published Successfully ✅'
              : 'Draft saved.',
          Colors.green);
      _resetForm();
      await _fetchHistory(silent: true);
    } catch (e) {
      _snack('Could not save. Check the app_updates table exists. ($e)',
          Colors.red);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status == AppUpdateService.statusPublished) {
        payload['published_at'] = DateTime.now().toIso8601String();
      }
      await _client
          .from(AppUpdateService.table)
          .update(payload)
          .eq('id', id);
      await _fetchHistory(silent: true);
      _snack(
          status == AppUpdateService.statusPublished
              ? 'Update Published Successfully ✅'
              : 'Update unpublished.',
          Colors.green);
    } catch (e) {
      _snack('Could not update status. ($e)', Colors.red);
    }
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete this update?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('The history entry will be removed permanently.',
            style:
                GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
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
    if (confirm != true || !mounted) return;
    try {
      await _client.from(AppUpdateService.table).delete().eq('id', id);
      if (_editingId?.toString() == id) _resetForm();
      await _fetchHistory(silent: true);
      _snack('Update deleted.', Colors.green);
    } catch (e) {
      _snack('Could not delete. ($e)', Colors.red);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _apkController.clear();
    _nameController.clear();
    _codeController.clear();
    if (mounted) {
      setState(() {
        _html = '';
        _composerKey++;
        _forceUpdate = false;
        _editingId = null;
        _showForm = false;
      });
    }
  }

  void _startEdit(Map<String, dynamic> row) {
    _titleController.text = (row['title'] ?? '').toString();
    _apkController.text = (row['apk_url'] ?? '').toString();
    _nameController.text = (row['version_name'] ?? '').toString();
    _codeController.text = (row['version_code'] ?? '').toString();
    final rawId = (row['id'] ?? '').toString();
    setState(() {
      _html = (row['description'] ?? '').toString();
      _composerKey++;
      final f = row['force_update'];
      _forceUpdate =
          f == true || '${f ?? ''}'.toLowerCase() == 'true';
      _editingId = rawId.isEmpty ? null : rawId;
      _showForm = true;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
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
        title: Text(tr('nav_update_link'),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchHistory(),
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
                    label: Text('+ Create Update',
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
              Text('Update History (${_history.length})',
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
            colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
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
            child: const Icon(Icons.link_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('nav_update_link'),
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Publish a new Canaan version with its APK download link.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  InputDecoration _dec(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
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
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
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
                  child: Text(
                      isEditing ? 'Edit Update' : 'Create Update',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                TextButton.icon(
                  onPressed: _isPublishing ? null : _resetForm,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('Cancel',
                      style: GoogleFonts.poppins(fontSize: 12.5)),
                ),
              ]),
              const SizedBox(height: 14),
              _label('Update Title'),
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _dec('Update Title',
                    'Canaan App Updated — New Features Available'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 14),
              _label('Update Description'),
              NoticeComposer(
                key: ValueKey(_composerKey),
                initialHtml: _html,
                onChanged: (html) => _html = html,
              ),
              const SizedBox(height: 14),
              _label(tr('upd_apk_link')),
              TextFormField(
                controller: _apkController,
                keyboardType: TextInputType.url,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _dec('APK Download Link',
                    'https://yourwebsite.com/downloads/canaan-1.2.0.apk'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'APK link is required' : null,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('${tr('upd_version')} Name'),
                        TextFormField(
                          controller: _nameController,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: _dec('Version Name', '1.2.0'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Required'
                              : null,
                        ),
                      ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('${tr('upd_version')} Code'),
                        TextFormField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: _dec('Version Code', '4'),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) return 'Invalid';
                            return null;
                          },
                        ),
                      ]),
                ),
              ]),
              const SizedBox(height: 14),
              _label('Update Type'),
              RadioGroup<String>(
                groupValue: _forceUpdate ? 'required' : 'optional',
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _forceUpdate = v == 'required');
                },
                child: Column(children: [
                  RadioListTile<String>(
                    value: 'optional',
                    title: Text('Optional Update',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF111827))),
                    subtitle: Text('User can choose Update or Later',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey.shade600)),
                    activeColor: const Color(0xFF1565C0),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    dense: true,
                  ),
                  RadioListTile<String>(
                    value: 'required',
                    title: Text('Required Update',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF111827))),
                    subtitle: Text('User must update before continuing',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey.shade600)),
                    activeColor: const Color(0xFFEF4444),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    dense: true,
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              if (_isPublishing) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    color: Color(0xFF1565C0),
                    backgroundColor: Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Publishing update…',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isPublishing
                          ? null
                          : () => _publish(publishNow: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1565C0),
                        side:
                            const BorderSide(color: Color(0xFF1565C0)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Save Draft',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isPublishing
                          ? null
                          : () => _publish(publishNow: true),
                      icon: _isPublishing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5))
                          : const Icon(Icons.publish_rounded, size: 19),
                      label: Text(
                          isEditing ? tr('upd_update') : tr('upd_publish'),
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 14)),
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
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case AppUpdateService.statusPublished:
        return const Color(0xFF22C55E);
      case AppUpdateService.statusDraft:
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
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
            onPressed: () => _fetchHistory(),
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
    if (_history.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Text('No updates yet. Create your first one above.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13.5, color: Colors.grey.shade500)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _historyCard(_history[i]),
    );
  }

  Widget _historyCard(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString();
    final color = _statusColor(status);
    final force = row['force_update'] == true ||
        '${row['force_update'] ?? ''}'.toLowerCase() == 'true';
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text((row['title'] ?? '').toString(),
                style: GoogleFonts.poppins(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827))),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
                status.isEmpty
                    ? '—'
                    : status[0].toUpperCase() + status.substring(1),
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            'Version ${(row['version_name'] ?? '').toString()} (${(row['version_code'] ?? '').toString()})'
            '${force ? ' • Required' : ''}'
            '${(row['published_at'] ?? '').toString().isNotEmpty ? ' • Published ${(row['published_at'] ?? '').toString().split('T').first}' : ''}',
            style: GoogleFonts.poppins(
                fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _smallBtn('View', const Color(0xFF1565C0),
              () => _viewRow(row)),
          _smallBtn('Edit', const Color(0xFF7B1FA2),
              () => _startEdit(row)),
          if (status != AppUpdateService.statusPublished)
            _smallBtn('Publish', const Color(0xFF22C55E),
                () => _setStatus(row, AppUpdateService.statusPublished)),
          if (status == AppUpdateService.statusPublished)
            _smallBtn('Unpublish', const Color(0xFFF59E0B),
                () => _setStatus(row, AppUpdateService.statusUnpublished)),
          _smallBtn('Delete', const Color(0xFFEF4444),
              () => _deleteRow(row)),
        ]),
      ]),
    );
  }

  Widget _smallBtn(String label, Color color, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child: Text(label,
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12.5)),
    );
  }

  void _viewRow(Map<String, dynamic> row) {
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
              Text((row['title'] ?? '').toString(),
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 6),
              Text(
                  'Version ${(row['version_name'] ?? '').toString()} (${(row['version_code'] ?? '').toString()})',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: NoticeContentView(
                    (row['description'] ?? '').toString()),
              ),
              const SizedBox(height: 12),
              Text('APK: ${(row['apk_url'] ?? '').toString()}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade600)),
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
}
