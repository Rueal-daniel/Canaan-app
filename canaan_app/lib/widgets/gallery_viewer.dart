import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/gallery_save.dart';
import '../services/gallery_service.dart';
import 'animations.dart';

/// Shared Canaan Gallery UI: post cards, the photo-grid detail page and
/// the full-screen photo viewer with ⬇️ Save to Phone.
///
/// Read-only for Teacher/Student (Admin has its own management page).
/// Save to Phone stores the single selected photo — never the whole
/// gallery at once.

// -- post card ---------------------------------------------------------------------

/// Cover-photo card used on the Teacher/Student gallery lists.
class GalleryPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final List<Map<String, dynamic>> photos;
  final VoidCallback onTap;
  final Color accent;

  const GalleryPostCard({
    super.key,
    required this.post,
    required this.photos,
    required this.onTap,
    this.accent = const Color(0xFF1565C0),
  });

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] ?? 'Gallery').toString();
    final date = GalleryService.prettyDate(post);
    final cover = photos.isEmpty
        ? null
        : GalleryService.photoUrlOf(photos.first);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: cover == null || cover.isEmpty
                    ? Container(
                        color: const Color(0xFFF1F5F9),
                        child: const Center(
                          child: Text('🖼️',
                              style: TextStyle(fontSize: 48)),
                        ),
                      )
                    : Image.network(
                        cover,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    color: const Color(0xFFF1F5F9),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded,
                                size: 44, color: Colors.grey),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🖼️ $title',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (date.isNotEmpty)
                    Text(
                      '📅 $date',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${GalleryService.prettyType(post['event_type']?.toString())}'
                    ' · 🖼️ ${photos.length} Photo${photos.length == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'View Gallery →',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- detail page ---------------------------------------------------------------------

void openGalleryDetail(
  BuildContext context, {
  required Map<String, dynamic> post,
  required List<Map<String, dynamic>> photos,
  Color accent = const Color(0xFF1565C0),
}) {
  Navigator.push(
    context,
    SlidePageRoute(
      page: GalleryDetailPage(post: post, photos: photos, accent: accent),
    ),
  );
}

/// Title + descriptions + photo grid. Tapping a photo opens the
/// full-screen viewer.
class GalleryDetailPage extends StatelessWidget {
  final Map<String, dynamic> post;
  final List<Map<String, dynamic>> photos;
  final Color accent;

  const GalleryDetailPage({
    super.key,
    required this.post,
    required this.photos,
    this.accent = const Color(0xFF1565C0),
  });

  @override
  Widget build(BuildContext context) {
    final title = (post['title'] ?? 'Gallery').toString();
    final description = (post['description'] ?? '').toString().trim();
    final eventDesc = (post['event_description'] ?? '').toString().trim();
    final date = GalleryService.prettyDate(post);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.65)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (date.isNotEmpty)
                  _pill('📅 $date', accent),
                _pill(
                  GalleryService.prettyType(
                      post['event_type']?.toString()),
                  const Color(0xFF6D28D9),
                ),
                _pill(
                  GalleryService.prettySection(
                      post['section']?.toString()),
                  const Color(0xFF7B1FA2),
                ),
                _pill(
                  '🖼️ ${photos.length} Photo${photos.length == 1 ? '' : 's'}',
                  Colors.grey.shade600,
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  height: 1.6,
                  color: const Color(0xFF374151),
                ),
              ),
            ],
            if (eventDesc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Text(
                  eventDesc,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.65,
                    color: const Color(0xFF374151),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (photos.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Text('🖼️', style: TextStyle(fontSize: 44)),
                    const SizedBox(height: 8),
                    Text(
                      'No photos in this gallery yet.',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: photos.length,
                itemBuilder: (_, i) {
                  final url =
                      GalleryService.photoUrlOf(photos[i]);
                  return GestureDetector(
                    onTap: () => openPhotoViewer(
                      context,
                      photos: photos,
                      initialIndex: i,
                      accent: accent,
                      galleryTitle: title,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    color: const Color(0xFFE2E8F0),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFE2E8F0),
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
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
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// -- full-screen photo viewer ------------------------------------------------------------

void openPhotoViewer(
  BuildContext context, {
  required List<Map<String, dynamic>> photos,
  int initialIndex = 0,
  Color accent = const Color(0xFF1565C0),
  String galleryTitle = '',
}) {
  if (photos.isEmpty) return;
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.94),
    builder: (_) => _PhotoViewerDialog(
      photos: photos,
      initialIndex: initialIndex.clamp(0, photos.length - 1),
      accent: accent,
      galleryTitle: galleryTitle,
    ),
  );
}

class _PhotoViewerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final Color accent;
  final String galleryTitle;

  const _PhotoViewerDialog({
    required this.photos,
    required this.initialIndex,
    required this.accent,
    required this.galleryTitle,
  });

  @override
  State<_PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<_PhotoViewerDialog> {
  late final PageController _controller;
  late int _index;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fileNameFor(int index) {
    final path = GalleryService.storagePathOf(widget.photos[index]);
    if (path.isNotEmpty) {
      final base = path.split('/').last;
      if (base.isNotEmpty) return base;
    }
    final safeTitle = widget.galleryTitle
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${safeTitle.isEmpty ? 'canaan-gallery' : safeTitle}-${index + 1}.jpg';
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    setState(() => _saving = true);
    final url = GalleryService.photoUrlOf(widget.photos[_index]);
    final ok = await saveGalleryPhotoToPhone(
      imageUrl: url,
      fileName: _fileNameFor(_index),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Photo Saved Successfully' : 'Could not save. Please try again.',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Photo ${_index + 1} of $total',
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        GalleryService.photoUrlOf(widget.photos[i]),
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.white),
                                  ),
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_rounded,
                              size: 64, color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ),
                if (total > 1) ...[
                  Positioned(
                    left: 4,
                    child: _navBtn(
                      Icons.chevron_left_rounded,
                      _index > 0
                          ? () => _controller.previousPage(
                                duration:
                                    const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              )
                          : null,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    child: _navBtn(
                      Icons.chevron_right_rounded,
                      _index < total - 1
                          ? () => _controller.nextPage(
                                duration:
                                    const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveCurrent,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.download_rounded, size: 22),
                  label: Text(
                    _saving ? 'Saving…' : '⬇️ Save to Phone',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        widget.accent.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.25 : 0.9,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white24,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
