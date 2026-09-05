import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/notice_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/notice_rich_text.dart';

/// Student Dashboard → Quick Links → Notice Board.
///
/// Read-only. Students receive Students + All notices (filtered at the
/// query level — never fetch-all-then-hide). Realtime delivery with
/// NEW indicators cleared via the server-side `read_by` array.
class StudentNoticeBoardPage extends StatefulWidget {
  final String studentName;
  const StudentNoticeBoardPage({
    super.key,
    this.studentName = '',
  });

  @override
  State<StudentNoticeBoardPage> createState() => _StudentNoticeBoardPageState();
}

class _StudentNoticeBoardPageState extends State<StudentNoticeBoardPage> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _notices = [];
  bool _isLoading = true;
  String? _loadError;
  String _search = '';
  String _readKey = '';
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _init();
    _subscribeRealtime();
  }

  Future<void> _init() async {
    try {
      final session = await SessionService.getSession();
      _readKey = session?.userId ?? '';
    } catch (_) {}
    _readKey = _readKey.isEmpty
        ? 'name:${widget.studentName}'
        : _readKey;
    await _fetchNotices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Realtime: new notices appear automatically, role-filtered on fetch
  /// so Students-only notices can never leak in.
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
      final before = _notices
          .map((n) => (n['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      final rows = await _client
          .from(NoticeService.table)
          .select('*')
          .inFilter('audience',
              NoticeService.visibleAudiencesFor('student'))
          .order('created_at', ascending: false);
      final items = List<Map<String, dynamic>>.from(rows);
      if (mounted) {
        final hadBefore = before.isNotEmpty;
        final fresh = items
            .map((n) => (n['id'] as num?)?.toInt())
            .whereType<int>()
            .where((id) => !before.contains(id))
            .toList();
        setState(() {
          _notices = items;
          _isLoading = false;
          _loadError = null;
        });
        if (silent && hadBefore && fresh.isNotEmpty) {
          _snack('📢 ${fresh.length == 1 ? 'New notice arrived' : '${fresh.length} new notices arrived'}',
              const Color(0xFF1565C0));
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load notices. Check your connection and try again. ($e)';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _notices;
    return _notices.where((n) {
      final title = (n['title'] ?? '').toString().toLowerCase();
      final body =
          NoticeService.plainTextOf((n['content'] ?? '').toString())
              .toLowerCase();
      return title.contains(q) || body.contains(q);
    }).toList();
  }

  int get _unreadCount => _notices
      .where((n) => NoticeService.isUnread(n, _readKey))
      .length;

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

  Future<void> _openNotice(Map<String, dynamic> notice) async {
    final id = (notice['id'] as num?)?.toInt();
    if (id != null) {
      await NoticeService.markAsRead(
          _client, id, NoticeService.readersOf(notice), _readKey);
      if (mounted) {
        setState(() {
          final i = _notices.indexWhere((n) => (n['id'] as num?)?.toInt() == id);
          if (i >= 0) {
            final updated = Map<String, dynamic>.from(_notices[i]);
            final readers = NoticeService.readersOf(updated);
            if (!readers.contains(_readKey)) {
              readers.add(_readKey);
              updated['read_by'] = readers;
              _notices[i] = updated;
            }
          }
        });
      }
    }
    if (!mounted) return;
    showNoticeDialog(
      context,
      title: (notice['title'] ?? '').toString(),
      html: (notice['content'] ?? '').toString(),
      dateTimeLabel: NoticeService.prettyDateTime(
          (notice['published_at'] ?? notice['created_at'])?.toString()),
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              _searchBox(),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text('Latest Notices (${_visible.length})',
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                if (_unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('🔴 $_unreadCount NEW',
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
              ]),
              const SizedBox(height: 12),
              _noticeList(),
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
            colors: [Color(0xFF063B2E), Color(0xFF0E9F6E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0E9F6E).withValues(alpha: 0.3),
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
                  Text('Important notices from the Admin.',
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
        hintText: '🔍 Search notices...',
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

  Widget _noticeList() {
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
    final items = _visible;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('📢', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
              _search.isNotEmpty
                  ? 'No notices match your search.'
                  : '📢 No notices yet.\nImportant notices from the Admin will appear here.',
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
      itemBuilder: (_, i) => _noticeCard(items[i]),
    );
  }

  Widget _noticeCard(Map<String, dynamic> notice) {
    final unread = NoticeService.isUnread(notice, _readKey);
    final preview = NoticeService.plainTextOf(
        (notice['content'] ?? '').toString());
    return FadeInSlide(
      index: 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: unread
                  ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                  : const Color(0xFFF1F5F9),
              width: unread ? 1.5 : 1),
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
              Row(children: [
                Expanded(
                  child: Text('📢 ${(notice['title'] ?? '').toString()}',
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827))),
                ),
                if (unread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('NEW',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(
                  'Published: ${NoticeService.prettyDate((notice['published_at'] ?? notice['created_at'])?.toString())}',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade500)),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        height: 1.6,
                        color: const Color(0xFF374151))),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => _openNotice(notice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: Text('Read Notice',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ),
            ]),
      ),
    );
  }
}
