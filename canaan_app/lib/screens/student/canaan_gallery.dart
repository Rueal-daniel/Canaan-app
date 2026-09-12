import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/gallery_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/gallery_viewer.dart';

/// Student Dashboard → Quick Links → Canaan Gallery.
///
/// Read-only, section-filtered: students see All-Sections galleries plus
/// their own section only (a Senior-only gallery is hidden from Junior
/// students). Realtime delivery.
class StudentCanaanGalleryPage extends StatefulWidget {
  final String studentName;
  final String? section;
  const StudentCanaanGalleryPage({
    super.key,
    this.studentName = '',
    this.section,
  });

  @override
  State<StudentCanaanGalleryPage> createState() =>
      _StudentCanaanGalleryPageState();
}

class _StudentCanaanGalleryPageState
    extends State<StudentCanaanGalleryPage> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _posts = [];
  Map<int, List<Map<String, dynamic>>> _photosByGallery = {};
  bool _isLoading = true;
  String? _loadError;
  final List<StreamSubscription> _realtimeSubs = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  void _subscribeRealtime() {
    for (final t in [
      GalleryService.postsTable,
      GalleryService.photosTable,
    ]) {
      try {
        _realtimeSubs.add(_client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
          if (mounted) _fetchAll(silent: true);
        }));
      } catch (_) {}
    }
  }

  Future<void> _fetchAll({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final before = _posts
          .map((p) => GalleryService.postIdOf(p))
          .where((id) => id >= 0)
          .toSet();
      final results = await Future.wait([
        _client
            .from(GalleryService.postsTable)
            .select('*')
            .order('created_at', ascending: false),
        _client
            .from(GalleryService.photosTable)
            .select('*')
            .order('display_order', ascending: true),
      ]);
      final posts = List<Map<String, dynamic>>.from(results[0] as List)
          .where((p) => GalleryService.visibleTo(
                p,
                role: 'student',
                section: widget.section,
              ))
          .toList();
      final photos =
          List<Map<String, dynamic>>.from(results[1] as List);
      if (mounted) {
        final hadBefore = before.isNotEmpty;
        final fresh = posts
            .where((p) => !before.contains(GalleryService.postIdOf(p)))
            .toList();
        setState(() {
          _posts = posts;
          _photosByGallery = GalleryService.photosByGallery(photos);
          _isLoading = false;
          _loadError = null;
        });
        if (silent && hadBefore && fresh.isNotEmpty) {
          _snack(
            '🖼️ ${fresh.length == 1 ? 'New gallery added' : '${fresh.length} new galleries added'}',
            const Color(0xFF0E9F6E),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load gallery. Check your connection and try again. ($e)';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF063B2E), Color(0xFF0E9F6E), Color(0xFF4ADE80)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Canaan Gallery',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchAll(),
        color: const Color(0xFF0E9F6E),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 16),
              Text('Galleries (${_posts.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _body(),
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
            child: const Icon(Icons.photo_library_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Canaan Gallery',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Event photos shared by the Admin.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.92))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF0E9F6E))),
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
            onPressed: () => _fetchAll(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E9F6E),
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
    if (_posts.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('🖼️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('🖼️ No galleries for your section yet.\nNew event photos will appear here.',
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
      itemCount: _posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final post = _posts[i];
        final photos =
            _photosByGallery[GalleryService.postIdOf(post)] ?? [];
        return FadeInSlide(
          index: 1,
          child: GalleryPostCard(
            post: post,
            photos: photos,
            accent: const Color(0xFF0E9F6E),
            onTap: () => openGalleryDetail(
              context,
              post: post,
              photos: photos,
              accent: const Color(0xFF0E9F6E),
            ),
          ),
        );
      },
    );
  }
}
