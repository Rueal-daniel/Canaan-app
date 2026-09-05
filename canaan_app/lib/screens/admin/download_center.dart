import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/download_center_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../lesson_pdf_viewer.dart';

/// Admin → Management → Download Center.
///
/// Shares resources, guides, documents and video tutorials with
/// teachers/students using the existing `download_center` +
/// `download_center_files` tables and the `download-center-files` bucket.
class AdminDownloadCenterPage extends StatefulWidget {
  final String adminName;
  const AdminDownloadCenterPage({super.key, this.adminName = ''});

  @override
  State<AdminDownloadCenterPage> createState() =>
      _AdminDownloadCenterPageState();
}

class _AdminDownloadCenterPageState extends State<AdminDownloadCenterPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  String _contentType = DownloadCenterService.typeDocument;
  String _audience = DownloadCenterService.audienceEveryone;
  PlatformFile? _pickedFile;
  Uint8List? _pickedBytes;

  bool _showForm = false;
  bool _isPicking = false;
  bool _isPublishing = false;
  bool _isLoading = true;
  String? _loadError;
  bool _audienceSupported = true;

  List<Map<String, dynamic>> _items = [];
  // item_id -> download_center_files row (one file per item).
  Map<int, Map<String, dynamic>> _files = {};
  StreamSubscription? _realtimeSub;

  int? _editingId;

  static const _typeOptions = [
    (DownloadCenterService.typeDocument, 'Document'),
    (DownloadCenterService.typeVideo, 'Video Tutorial'),
    (DownloadCenterService.typeInfo, 'Important Information'),
    (DownloadCenterService.typeOther, 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _init();
    _subscribeRealtime();
  }

  Future<void> _init() async {
    // Probe once whether the optional `audience` column exists.
    try {
      await _client
          .from(DownloadCenterService.table)
          .select('id,audience')
          .limit(1);
      _audienceSupported = true;
    } catch (_) {
      _audienceSupported = false;
    }
    await _fetchItems();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(DownloadCenterService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
            if (mounted) _fetchItems(silent: true);
          });
    } catch (_) {}
  }

  Future<void> _fetchItems({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(DownloadCenterService.table)
          .select('*')
          .order('created_at', ascending: false);
      final items = List<Map<String, dynamic>>.from(rows);
      final files = <int, Map<String, dynamic>>{};
      if (items.isNotEmpty) {
        try {
          final ids = items
              .map((p) => (p['id'] as num?)?.toInt())
              .whereType<int>()
              .toList();
          if (ids.isNotEmpty) {
            final fileRows = await _client
                .from(DownloadCenterService.filesTable)
                .select('*')
                .inFilter('item_id', ids)
                .order('created_at', ascending: false);
            for (final f in List<Map<String, dynamic>>.from(fileRows)) {
              final iid = (f['item_id'] as num?)?.toInt();
              if (iid != null) files.putIfAbsent(iid, () => f);
            }
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _items = items;
          _files = files;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load content. Check your connection and try again. ($e)';
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

  Map<String, dynamic>? _fileOf(Map<String, dynamic> item) {
    final id = (item['id'] as num?)?.toInt();
    return id == null ? null : _files[id];
  }

  // ------------------------------------------------------------------
  // File attach (PDF / documents / images / video).
  // ------------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() => _isPicking = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt',
          'jpg', 'jpeg', 'png', 'gif', 'webp',
          'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v',
        ],
      );
      if (file == null) return; // user canceled
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _snack('Could not read the selected file.', Colors.red);
        return;
      }
      if (bytes.length > 100 * 1024 * 1024) {
        _snack('File is too large. Please choose a file under 100 MB.',
            Colors.orange);
        return;
      }
      if (mounted) {
        setState(() {
          _pickedFile = file;
          _pickedBytes = bytes;
        });
      }
    } catch (e) {
      _snack('Could not open file picker. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _clearFile() {
    setState(() {
      _pickedFile = null;
      _pickedBytes = null;
    });
  }

  // ------------------------------------------------------------------
  // Publish.
  // ------------------------------------------------------------------

  Future<String> _adminName() async {
    if (widget.adminName.isNotEmpty) return widget.adminName;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        final auth = AuthService();
        final profile = await auth.getUserById(
            userId: session.userId, role: UserRole.admin);
        final name = (profile?['full_name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'Canaan Administrator';
  }

  Future<void> _publish() async {
    if (_isPublishing) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isPublishing = true);
    try {
      final postedBy = await _adminName();
      int itemId;
      if (_editingId != null) {
        itemId = _editingId!;
        final update = <String, dynamic>{
          'title': _titleController.text.trim(),
          'description': _descController.text.trim(),
          'type': _contentType,
        };
        if (_audienceSupported) update['audience'] = _audience;
        await _client
            .from(DownloadCenterService.table)
            .update(update)
            .eq('id', itemId);
      } else {
        final insert = <String, dynamic>{
          'title': _titleController.text.trim(),
          'description': _descController.text.trim(),
          'type': _contentType,
          'posted_by': postedBy,
        };
        if (_audienceSupported) {
          insert['audience'] = _audience;
        }
        try {
          final created = await _client
              .from(DownloadCenterService.table)
              .insert(insert)
              .select('id')
              .single();
          itemId = (created['id'] as num).toInt();
        } catch (e) {
          // Retry without audience if the column turned out to be missing.
          if (_audienceSupported &&
              e.toString().toLowerCase().contains('audience')) {
            _audienceSupported = false;
            insert.remove('audience');
            final created = await _client
                .from(DownloadCenterService.table)
                .insert(insert)
                .select('id')
                .single();
            itemId = (created['id'] as num).toInt();
          } else {
            rethrow;
          }
        }
      }

      if (_pickedBytes != null && _pickedFile != null) {
        final fileName = _pickedFile!.name;
        final filePath = DownloadCenterService.storagePath(fileName);
        try {
          await _client.storage
              .from(DownloadCenterService.bucket)
              .uploadBinary(
                filePath,
                _pickedBytes!,
                fileOptions: FileOptions(
                    contentType:
                        DownloadCenterService.mimeFor(fileName),
                    upsert: true),
              );
        } catch (e) {
          throw Exception(
              'Content saved but file upload failed. Check the download-center-files bucket, then Edit to attach the file. ($e)');
        }
        final filePayload = <String, dynamic>{
          'item_id': itemId,
          'file_name': fileName,
          'file_path': filePath,
          'file_size': _pickedBytes!.length,
          'mime_type': DownloadCenterService.mimeFor(fileName),
        };
        final oldFile = _files[itemId];
        if (oldFile != null && oldFile['id'] != null) {
          await _client
              .from(DownloadCenterService.filesTable)
              .update(filePayload)
              .eq('id', oldFile['id']);
          final oldPath = DownloadCenterService.filePathOf(oldFile);
          if (oldPath.isNotEmpty && oldPath != filePath) {
            try {
              await _client.storage
                  .from(DownloadCenterService.bucket)
                  .remove([oldPath]);
            } catch (_) {}
          }
        } else {
          await _client
              .from(DownloadCenterService.filesTable)
              .insert(filePayload);
        }
      }

      final wasEditing = _editingId != null;
      _snack(
        wasEditing
            ? '✅ Content updated successfully!'
            : '✅ Content published successfully!',
        Colors.green,
      );
      _resetForm();
      await _fetchItems(silent: true);
    } catch (e) {
      _snack('Could not publish. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _descController.clear();
    if (mounted) {
      setState(() {
        _contentType = DownloadCenterService.typeDocument;
        _audience = DownloadCenterService.audienceEveryone;
        _pickedFile = null;
        _pickedBytes = null;
        _editingId = null;
        _showForm = false;
      });
    }
  }

  void _startEdit(Map<String, dynamic> item) {
    _titleController.text = (item['title'] ?? '').toString();
    _descController.text = (item['description'] ?? '').toString();
    setState(() {
      _contentType =
          DownloadCenterService.normalizeType(item['type']?.toString());
      _audience = DownloadCenterService.normalizeAudience(
          item['audience']?.toString());
      _editingId = (item['id'] as num?)?.toInt();
      _pickedFile = null;
      _pickedBytes = null;
      _showForm = true;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    _snack('Editing mode — update the form, optionally replace the file.',
        const Color(0xFF1565C0));
  }

  void _confirmDelete(Map<String, dynamic> item) {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final title = (item['title'] ?? 'this content').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Content?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Are you sure you want to delete "$title"?\n\n'
            'Its attached file will also be removed from storage.',
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
              await _deleteItem(item);
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

  /// Deletes the item, its file row(s) and its storage object(s) —
  /// no orphaned files left behind.
  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = (item['id'] as num).toInt();
    try {
      List<Map<String, dynamic>> rows = [];
      final single = _files[id];
      if (single != null) {
        rows = [single];
      } else {
        try {
          final res = await _client
              .from(DownloadCenterService.filesTable)
              .select('*')
              .eq('item_id', id);
          rows = List<Map<String, dynamic>>.from(res);
        } catch (_) {}
      }
      for (final f in rows) {
        final path = DownloadCenterService.filePathOf(f);
        if (path.isNotEmpty) {
          try {
            await _client.storage
                .from(DownloadCenterService.bucket)
                .remove([path]);
          } catch (_) {}
        }
      }
      try {
        await _client
            .from(DownloadCenterService.filesTable)
            .delete()
            .eq('item_id', id);
      } catch (_) {}
      await _client.from(DownloadCenterService.table).delete().eq('id', id);
      if (_editingId == id) _resetForm();
      await _fetchItems(silent: true);
      _snack('Content deleted.', Colors.green);
    } catch (e) {
      _snack('Could not delete. Please try again. ($e)', Colors.red);
    }
  }

  Future<void> _viewItem(Map<String, dynamic> item) async {
    final file = _fileOf(item);
    final path = file == null ? '' : DownloadCenterService.filePathOf(file);
    final mime = file == null ? '' : DownloadCenterService.mimeOf(file);
    final name = file == null ? '' : DownloadCenterService.fileNameOf(file);
    if (path.isEmpty) {
      _showDetailSheet(item);
      return;
    }
    if (DownloadCenterService.isPdfFile(name, mime)) {
      final url = await DownloadCenterService.resolveFileUrl(_client, path);
      if (url == null || url.isEmpty || !mounted) {
        _snack('Could not open file. Missing in storage.', Colors.red);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LessonPdfViewerScreen(
            title: (item['title'] ?? 'Download Center').toString(),
            pdfUrl: url,
            fileName: name,
          ),
        ),
      );
      return;
    }
    if (DownloadCenterService.isImageFile(name, mime)) {
      final url = await DownloadCenterService.resolveFileUrl(_client, path);
      if (url == null || url.isEmpty || !mounted) {
        _snack('Could not open image. Missing in storage.', Colors.red);
        return;
      }
      _showImageDialog((item['title'] ?? '').toString(), url);
      return;
    }
    _showDetailSheet(item);
  }

  void _showImageDialog(String title, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.network(url,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, progress) =>
                          progress == null
                              ? child
                              : const Padding(
                                  padding: EdgeInsets.all(32),
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF1565C0)),
                                ),
                      errorBuilder: (_, _, _) => Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Could not load image.',
                                style: GoogleFonts.poppins(
                                    color: Colors.grey.shade600)),
                          )),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailSheet(Map<String, dynamic> item) {
    final file = _fileOf(item);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
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
              const SizedBox(height: 18),
              Text('📥 ${(item['title'] ?? '').toString()}',
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _pill(
                    DownloadCenterService.prettyType(item['type']?.toString()),
                    const Color(0xFF1565C0)),
                _pill(
                    DownloadCenterService.prettyAudience(
                        item['audience']?.toString()),
                    const Color(0xFF7B1FA2)),
                _pill(
                    DownloadCenterService.prettyDate(
                        item['created_at']?.toString()),
                    Colors.grey.shade600),
              ]),
              if ((item['description'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text((item['description'] ?? '').toString(),
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        height: 1.6,
                        color: const Color(0xFF374151))),
              ],
              if (file != null) ...[
                const SizedBox(height: 14),
                Row(children: [
                  const Icon(Icons.attach_file_rounded,
                      size: 18, color: Color(0xFF1565C0)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '${DownloadCenterService.fileNameOf(file)} • ${DownloadCenterService.formatFileSize(DownloadCenterService.fileSizeOf(file))}',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: const Color(0xFF374151))),
                  ),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _downloadFile(item);
                    },
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text('⬇ Download',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFile(Map<String, dynamic> item) async {
    final file = _fileOf(item);
    final path = file == null ? '' : DownloadCenterService.filePathOf(file);
    if (path.isEmpty) {
      _snack('No file attached to this content.', Colors.orange);
      return;
    }
    try {
      try {
        final bytes = await _client.storage
            .from(DownloadCenterService.bucket)
            .download(path);
        if (bytes.isEmpty) throw Exception('empty file');
      } catch (e) {
        _snack('Download failed — file not found in storage. ($e)', Colors.red);
        return;
      }
      final url = await DownloadCenterService.resolveFileUrl(_client, path);
      if (url == null || url.isEmpty) {
        _snack('Download failed — could not resolve file URL.', Colors.red);
        return;
      }
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) {
        _snack('Could not start download.', Colors.red);
      } else {
        _snack('⬇️ Download started.', Colors.green);
      }
    } catch (e) {
      _snack('Download failed. ($e)', Colors.red);
    }
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
        title: Text('Download Center',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchItems(),
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
              if (!_audienceSupported) _audienceHint(),
              if (_showForm) ...[
                _formCard(),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showForm = true;
                        _editingId = null;
                      });
                      _scrollController.animateTo(0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut);
                    },
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: Text('+ Add Content',
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
              ],
              const SizedBox(height: 20),
              Text('Published Content (${_items.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _contentList(),
              const SizedBox(height: 12),
              if (kIsWeb)
                Text(
                  'Files are stored in the download-center-files bucket and linked from download_center_files.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.download_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Download Center',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    'Share important resources, guides, documents, and video tutorials with teachers and students.',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audienceHint() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Audience targeting (Teachers / Students / Everyone) needs one extra column on download_center. Until then everything is shared with everyone.',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: const Color(0xFF92400E)),
            ),
          ),
        ],
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
                  child: Text(isEditing ? 'Edit Content' : 'Add New Content',
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
                    'Title', 'How to Use the New Attendance System'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Description / About'),
              TextFormField(
                controller: _descController,
                maxLines: 5,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration('Description',
                    'Explain what this content is about...'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Description is required'
                    : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Content Type'),
              DropdownButtonFormField<String>(
                initialValue: _contentType,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: const Color(0xFF111827)),
                decoration:
                    _inputDecoration('Content Type', 'Select content type'),
                items: [
                  for (final (value, label) in _typeOptions)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: _isPublishing
                    ? null
                    : (v) => setState(() => _contentType = v!),
              ),
              const SizedBox(height: 14),
              _fieldLabel('📎 Attach File'),
              _filePickerBox(isEditing),
              const SizedBox(height: 6),
              Text(
                'PDF, documents, images or video files. For video tutorials, attach the video file (MP4).',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade500),
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
                Text('Uploading file and publishing…',
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
                      : const Icon(Icons.upload_rounded, size: 20),
                  label: Text(
                    isEditing ? 'Update Content' : '📤 Publish',
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
      (DownloadCenterService.audienceTeachers, 'Teachers'),
      (DownloadCenterService.audienceStudents, 'Students'),
      (DownloadCenterService.audienceEveryone, 'Everyone'),
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
        child: Column(
          children: [
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
          ],
        ),
      ),
    );
  }

  Widget _filePickerBox(bool isEditing) {
    final hasFile = _pickedFile != null && _pickedBytes != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasFile ? const Color(0xFF22C55E) : Colors.grey.shade300,
          width: hasFile ? 2 : 1.5,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.attach_file_rounded,
              size: 36, color: Color(0xFF1565C0)),
          const SizedBox(height: 8),
          Text('Choose Resource File',
              style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (!hasFile)
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _isPicking || _isPublishing ? null : _pickFile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isPicking
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Choose File',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.description_rounded,
                    color: Color(0xFF1565C0), size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_pickedFile!.name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        Text(
                            DownloadCenterService.formatFileSize(
                                _pickedBytes!.length),
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                ),
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF22C55E), size: 22),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isPicking || _isPublishing ? null : _pickFile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    side: const BorderSide(color: Color(0xFF1565C0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Replace',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isPicking || _isPublishing ? null : _clearFile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Remove',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ]),
          ],
          if (isEditing && !hasFile) ...[
            const SizedBox(height: 8),
            Text('Keeping the current file. Pick a file above to replace it.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey.shade500)),
          ],
        ],
      ),
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

  Widget _contentList() {
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
            onPressed: () => _fetchItems(),
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
    if (_items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Icon(Icons.cloud_download_outlined,
              size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No content published yet.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 4),
          Text('Tap + Add Content to share your first resource.',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade500)),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _contentCard(_items[i]),
    );
  }

  Widget _contentCard(Map<String, dynamic> item) {
    final file = _fileOf(item);
    final fileName =
        file == null ? '' : DownloadCenterService.fileNameOf(file);
    final mime = file == null ? '' : DownloadCenterService.mimeOf(file);
    final isVideo = file != null &&
        (DownloadCenterService.isVideoFile(fileName, mime) ||
            DownloadCenterService.normalizeType(item['type']?.toString()) ==
                DownloadCenterService.typeVideo &&
                fileName.isEmpty);
    final id = (item['id'] as num?)?.toInt();
    final isEditingThis = _editingId == id && _editingId != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(
                color: isEditingThis
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF22C55E),
                width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📥 ${(item['title'] ?? '').toString()}',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(
              'Type: ${DownloadCenterService.prettyType(item['type']?.toString())}',
              const Color(0xFF1565C0)),
          _pill(
              'Audience: ${DownloadCenterService.prettyAudience(item['audience']?.toString())}',
              const Color(0xFF7B1FA2)),
          _pill(
              'Published: ${DownloadCenterService.prettyDate(item['created_at']?.toString())}',
              Colors.grey.shade600),
        ]),
        if (fileName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.attach_file_rounded,
                size: 16, color: Color(0xFF1565C0)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('📄 $fileName',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: const Color(0xFF374151))),
            ),
          ]),
        ],
        if (isVideo) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.play_circle_fill_rounded,
                size: 16, color: Color(0xFFEF4444)),
            const SizedBox(width: 6),
            Text('🎥 Tutorial Available',
                style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151))),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _viewItem(item),
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
            onPressed: () => _startEdit(item),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(item),
          ),
        ]),
      ]),
    );
  }
}
