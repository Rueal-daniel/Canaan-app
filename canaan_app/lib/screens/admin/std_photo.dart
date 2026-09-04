import 'dart:math' show min;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin → Students → Student Photo.
///
/// Lets the admin pick a photo per student, uploads it to the
/// `student-photos` storage bucket (`{student-id}/profile-photo.ext`),
/// and saves the path in the existing `students.photo_url` column —
/// the single source of truth every avatar in the app reads.
class StdPhoto extends StatefulWidget {
  const StdPhoto({super.key});

  @override
  State<StdPhoto> createState() => _StdPhotoState();
}

class _StdPhotoState extends State<StdPhoto>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  late TabController _tabController;
  final _searchController = TextEditingController();

  static const _bucket = 'student-photos';
  static const _allowedExts = {'jpg', 'jpeg', 'png', 'webp'};

  List<Map<String, dynamic>> _allStudents = [];
  String _searchQuery = '';
  bool _isLoading = true;
  String? _busyStudentId;
  int _imgTick = 0;
  final Set<String> _brokenPaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchStudents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStudents() async {
    setState(() => _isLoading = true);
    try {
      final data = await _client
          .from('students')
          .select('id, full_name, section, photo_url')
          .order('full_name');
      if (mounted) {
        setState(() {
          _allStudents = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
          _brokenPaths.clear();
          _imgTick = DateTime.now().millisecondsSinceEpoch;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _prettySection(String section) {
    if (section == 'sub-junior') return 'Sub Junior';
    if (section.isEmpty) return section;
    return section[0].toUpperCase() + section.substring(1);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  String _photoPath(Map<String, dynamic> s) =>
      (s['photo_url'] ?? '').toString().trim();

  String _publicUrl(String path) =>
      '${_client.storage.from(_bucket).getPublicUrl(path)}?t=$_imgTick';

  String _mime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Center-square crops and downsizes to a small 512px avatar JPG,
  /// so uploads stay tiny and avatars look uniform.
  Uint8List? _makeAvatar(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final side = min(decoded.width, decoded.height);
    final cropped = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = img.copyResize(cropped, width: 512, height: 512);
    return img.encodeJpg(resized, quality: 85);
  }

  List<Map<String, dynamic>> _visibleFor(String section) {
    final q = _searchQuery.toLowerCase();
    return _allStudents.where((s) {
      if (s['section'] != section) return false;
      if (q.isEmpty) return true;
      return (s['full_name'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
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

  /// Mobile (Android/iOS) → photo gallery.
  /// Web/desktop → file explorer.
  bool get _useGallery =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Step 1: pick an image file, then show preview + Upload/Cancel.
  Future<void> _pickPhoto(Map<String, dynamic> s) async {
    String ext;
    late Uint8List pickedBytes;
    try {
      if (_useGallery) {
        final XFile? image = await ImagePicker()
            .pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (image == null) return; // user canceled
        ext = image.name.split('.').last.toLowerCase();
        pickedBytes = await image.readAsBytes();
      } else {
        // pickFiles (plural): implemented on every platform incl. web.
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (files.isEmpty) return; // user canceled
        final file = files.first;
        final parts = file.name.split('.');
        ext = (parts.length > 1 ? parts.last : '').toLowerCase();
        pickedBytes = await file.readAsBytes();
      }
    } catch (e) {
      _snack('Could not open picker: $e', Colors.red);
      return;
    }

    final rawBytes = pickedBytes;
    if (!_allowedExts.contains(ext)) {
      _snack('Please choose a JPG, PNG or WEBP image.', Colors.orange);
      return;
    }
    if (rawBytes.isEmpty) {
      _snack('Could not read the selected image.', Colors.red);
      return;
    }
    // Auto-crop to a small square avatar (512px JPG).
    Uint8List bytes;
    try {
      final avatar = _makeAvatar(rawBytes);
      if (avatar == null) {
        _snack('This file is not a readable image.', Colors.red);
        return;
      }
      bytes = avatar;
    } catch (e) {
      _snack('Could not process the selected image.', Colors.red);
      return;
    }
    if (!mounted) return;
    _previewDialog(s, bytes, 'jpg');
  }

  void _previewDialog(
      Map<String, dynamic> s, Uint8List bytes, String ext) {
    final name = (s['full_name'] ?? '').toString();
    bool uploading = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Upload Photo',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fixed-size box: unbounded width here caused
              // "Cannot hit test a render box with no size".
              SizedBox(
                width: 220,
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 12),
              Text(name,
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style:
                      GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: uploading
                  ? null
                  : () async {
                      setDialogState(() => uploading = true);
                      final ok = await _uploadPhoto(s, bytes, ext);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (ok && mounted) {
                        _snack('Profile photo updated.',
                            Colors.green);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: uploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Upload Photo',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 2: upload to `student-photos/{id}/profile-photo.ext`
  /// and save the path in `students.photo_url`.
  Future<bool> _uploadPhoto(
      Map<String, dynamic> s, Uint8List bytes, String ext) async {
    final studentId = s['id'].toString();
    final oldPath = _photoPath(s);
    final newPath = '$studentId/profile-photo.$ext';
    setState(() => _busyStudentId = studentId);
    try {
      await _client.storage.from(_bucket).uploadBinary(
            newPath,
            bytes,
            fileOptions:
                FileOptions(contentType: _mime(ext), upsert: true),
          );
      // Remove the previous file when the path changed (e.g. jpg → png).
      if (oldPath.isNotEmpty && oldPath != newPath) {
        try {
          await _client.storage.from(_bucket).remove([oldPath]);
        } catch (_) {}
      }
      await _client
          .from('students')
          .update({'photo_url': newPath}).eq('id', studentId);
      await _fetchStudents();
      return true;
    } catch (e) {
      _snack(
          'Upload failed: $e (check the student-photos bucket policies)',
          Colors.red);
      return false;
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }

  void _confirmRemove(Map<String, dynamic> s) {
    final name = (s['full_name'] ?? '').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Profile Photo?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          "Are you sure you want to remove this student's profile photo?",
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _removePhoto(s, name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Remove Photo',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _removePhoto(Map<String, dynamic> s, String name) async {
    final studentId = s['id'].toString();
    final path = _photoPath(s);
    setState(() => _busyStudentId = studentId);
    try {
      await _client
          .from('students')
          .update({'photo_url': null}).eq('id', studentId);
      if (path.isNotEmpty) {
        try {
          await _client.storage.from(_bucket).remove([path]);
        } catch (_) {}
      }
      await _fetchStudents();
      _snack('Photo removed. Showing initials again.', Colors.green);
    } catch (e) {
      _snack('Could not remove photo. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
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
        title: Text('Student Photos',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Sub Junior'),
            Tab(text: 'Junior'),
            Tab(text: 'Senior'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Manage profile photos for students.',
                style: GoogleFonts.poppins(
                    fontSize: 13.5, color: Colors.grey.shade600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search student',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF1565C0)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF1565C0), width: 2)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1565C0)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _photoGrid('sub-junior'),
                      _photoGrid('junior'),
                      _photoGrid('senior'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _photoGrid(String section) {
    final items = _visibleFor(section);
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No students found in this section.',
                style: GoogleFonts.poppins(
                    fontSize: 15, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 262,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _photoCard(items[i]),
    );
  }

  Widget _photoCard(Map<String, dynamic> s) {
    final studentId = s['id'].toString();
    final name = (s['full_name'] ?? '').toString();
    final path = _photoPath(s);
    final hasPhoto = path.isNotEmpty;
    final photoBroken = _brokenPaths.contains(path);
    final showPhoto = hasPhoto && !photoBroken;
    final busy = _busyStudentId == studentId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor:
                    const Color(0xFF5C6BC0).withValues(alpha: 0.1),
                backgroundImage:
                    showPhoto ? NetworkImage(_publicUrl(path)) : null,
                onBackgroundImageError: showPhoto
                    ? (_, _) {
                        _brokenPaths.add(path);
                        if (mounted) setState(() {});
                      }
                    : null,
                child: !showPhoto
                    ? Text(_initials(name),
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF5C6BC0)))
                    : null,
              ),
              if (hasPhoto)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: busy ? null : () => _confirmRemove(s),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_prettySection((s['section'] ?? '').toString()),
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: busy ? null : () => _pickPhoto(s),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF1565C0).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                padding: EdgeInsets.zero,
              ),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(hasPhoto ? 'Change Photo' : 'Choose Photo',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
