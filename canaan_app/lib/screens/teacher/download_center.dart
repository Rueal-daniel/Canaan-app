import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/download_center_service.dart';
import '../../widgets/animations.dart';

/// Teacher Dashboard → Quick Links → Download Center.
///
/// Read-only, download-only: teachers see Teacher + Everyone content
/// (filtered at the query level), then download files and open them
/// with their own device apps. No inline viewer/player.
class TeacherDownloadCenterPage extends StatefulWidget {
  const TeacherDownloadCenterPage({super.key});

  @override
  State<TeacherDownloadCenterPage> createState() =>
      _TeacherDownloadCenterPageState();
}

class _TeacherDownloadCenterPageState
    extends State<TeacherDownloadCenterPage> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  Map<int, Map<String, dynamic>> _files = {};
  bool _isLoading = true;
  String? _loadError;
  bool _busyDownload = false;
  String _search = '';
  String _filter = 'all';
  StreamSubscription? _realtimeSub;

  static const _filters = [
    ('all', 'All'),
    ('document', 'Documents'),
    ('video', 'Video Tutorials'),
    ('info', 'Important Information'),
    ('other', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _fetchItems();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Realtime: newly published resources appear without manual refresh.
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

  /// Audience filtering at the query level: teachers + everyone only.
  Future<void> _fetchItems({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      List rows;
      try {
        rows = await _client
            .from(DownloadCenterService.table)
            .select('*')
            .inFilter(
                'audience',
                DownloadCenterService.visibleAudiencesFor('teacher'))
            .order('created_at', ascending: false);
      } catch (_) {
        // `audience` column not migrated yet — show everything.
        rows = await _client
            .from(DownloadCenterService.table)
            .select('*')
            .order('created_at', ascending: false);
      }
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
              'Could not load resources. Check your connection and try again. ($e)';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    return _items.where((item) {
      if (_filter != 'all' &&
          DownloadCenterService.normalizeType(item['type']?.toString()) !=
              _filter) {
        return false;
      }
      if (q.isEmpty) return true;
      final title = (item['title'] ?? '').toString().toLowerCase();
      final desc = (item['description'] ?? '').toString().toLowerCase();
      final type =
          DownloadCenterService.prettyType(item['type']?.toString())
              .toLowerCase();
      return title.contains(q) || desc.contains(q) || type.contains(q);
    }).toList();
  }

  Map<String, dynamic>? _fileOf(Map<String, dynamic> item) {
    final id = (item['id'] as num?)?.toInt();
    return id == null ? null : _files[id];
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

  /// Downloads the actual file from the download-center-files bucket.
  /// Users then watch/read it with their own device apps.
  Future<void> _downloadFile(Map<String, dynamic> item) async {
    final file = _fileOf(item);
    final path = file == null ? '' : DownloadCenterService.filePathOf(file);
    if (path.isEmpty) {
      _snack('No file attached to this resource.', Colors.orange);
      return;
    }
    if (mounted) setState(() => _busyDownload = true);
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
        _snack('⬇️ Download started. Open the file to view it.', Colors.green);
      }
    } catch (e) {
      _snack('Download failed. Check your connection. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _busyDownload = false);
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              _searchBox(),
              const SizedBox(height: 10),
              _filterChips(),
              const SizedBox(height: 16),
              Text('Latest Resources (${_visible.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _contentList(),
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
            colors: [Color(0xFFFF9F0A), Color(0xFFFFB74D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9F0A).withValues(alpha: 0.3),
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
                  Text('Important resources and tutorials shared with you.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.92))),
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
        hintText: '🔍 Search resources...',
        hintStyle:
            GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
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

  Widget _filterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in _filters)
          ChoiceChip(
            label: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            selected: _filter == value,
            onSelected: (_) => setState(() => _filter = value),
            selectedColor: const Color(0xFF1565C0),
            labelStyle: GoogleFonts.poppins(
                color: _filter == value
                    ? Colors.white
                    : const Color(0xFF374151)),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
          ),
      ],
    );
  }

  Widget _contentList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
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
    final items = _visible;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('📥', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
              _search.isNotEmpty || _filter != 'all'
                  ? 'No resources match your search.'
                  : 'No resources shared with you yet.',
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
      itemBuilder: (_, i) => _resourceCard(items[i]),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case DownloadCenterService.typeVideo:
        return const Color(0xFFEF4444);
      case DownloadCenterService.typeDocument:
        return const Color(0xFF1565C0);
      case DownloadCenterService.typeInfo:
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _typeEmoji(String type) {
    switch (type) {
      case DownloadCenterService.typeVideo:
        return '🎥';
      case DownloadCenterService.typeDocument:
        return '📚';
      case DownloadCenterService.typeInfo:
        return 'ℹ️';
      default:
        return '📦';
    }
  }

  Widget _resourceCard(Map<String, dynamic> item) {
    final type =
        DownloadCenterService.normalizeType(item['type']?.toString());
    final color = _typeColor(type);
    final file = _fileOf(item);
    final fileName =
        file == null ? '' : DownloadCenterService.fileNameOf(file);
    final hasFile = file != null && fileName.isNotEmpty;
    final desc = (item['description'] ?? '').toString().trim();
    return FadeInSlide(
      index: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_typeEmoji(type)} ${(item['title'] ?? '').toString()}',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                    '${_typeEmoji(type)} ${DownloadCenterService.prettyType(item['type']?.toString())}',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(desc,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        height: 1.6,
                        color: const Color(0xFF374151))),
              ],
              const SizedBox(height: 8),
              Text(
                  'Published: ${DownloadCenterService.prettyDate(item['created_at']?.toString())}',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade500)),
              if (hasFile) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    Icon(
                        type == DownloadCenterService.typeVideo
                            ? Icons.play_circle_fill_rounded
                            : Icons.description_rounded,
                        color: color,
                        size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fileName,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                DownloadCenterService.formatFileSize(
                                    DownloadCenterService.fileSizeOf(file)),
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey.shade500)),
                          ]),
                    ),
                  ]),
                ),
              ],
              if (hasFile) ...[
                const SizedBox(height: 14),
                if (_busyDownload)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                        color: Color(0xFF22C55E)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed:
                        _busyDownload ? null : () => _downloadFile(item),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: Text(
                        type == DownloadCenterService.typeVideo
                            ? '⬇ Download Tutorial'
                            : '⬇ Download',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 14)),
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
            ]),
      ),
    );
  }
}
