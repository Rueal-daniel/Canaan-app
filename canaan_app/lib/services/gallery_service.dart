import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared School / Canaan Gallery logic for Admin / Teacher / Student.
///
/// Backed by (see `supabase/gallery.sql` — run once):
///   `gallery_posts`  (id, title, description, event_description,
///     event_date, event_type, section, created_by, created_by_id,
///     created_at, updated_at)
///   `gallery_photos` (id, gallery_id → posts.id ON DELETE CASCADE,
///     photo_url, storage_path, display_order, created_at)
/// Files live in the public `gallery-photos` storage bucket at
/// `{gallery_id}/{timestamp}-{rand}-{filename}`.
///
/// Canonical values (single section per post):
///   event_type : sunday_school | activity | special_program | others
///   section    : all | sub-junior | junior | senior
///
/// Visibility:
///   Admin   → everything.
///   Teacher → every post (teachers supervise all sections).
///   Student → posts with section all OR the student's own section
///             (a Senior-only gallery is hidden from Junior students).
class GalleryService {
  static const postsTable = 'gallery_posts';
  static const photosTable = 'gallery_photos';
  static const bucket = 'gallery-photos';

  // -- event types (same vocabulary as Events & Calendar) --------------------
  static const typeSundaySchool = 'sunday_school';
  static const typeActivity = 'activity';
  static const typeSpecial = 'special_program';
  static const typeOthers = 'others';

  static String normalizeType(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'sunday school' ||
        s == 'sunday_school' ||
        s == 'sundayschool') {
      return typeSundaySchool;
    }
    if (s == 'special program' ||
        s == 'special_program' ||
        s == 'special') {
      return typeSpecial;
    }
    if (s == 'activity' || s == 'activities') return typeActivity;
    return typeOthers;
  }

  static String prettyType(String? raw) {
    switch (normalizeType(raw)) {
      case typeSundaySchool:
        return 'Sunday School';
      case typeActivity:
        return 'Activity';
      case typeSpecial:
        return 'Special Program';
      default:
        return 'Others';
    }
  }

  static IconData iconFor(String? raw) {
    switch (normalizeType(raw)) {
      case typeSundaySchool:
        return Icons.menu_book_rounded;
      case typeActivity:
        return Icons.celebration_rounded;
      case typeSpecial:
        return Icons.star_rounded;
      default:
        return Icons.photo_library_rounded;
    }
  }

  // -- sections (single value per post) -----------------------------------------
  static const sectionAll = 'all';
  static const sectionSubJunior = 'sub-junior';
  static const sectionJunior = 'junior';
  static const sectionSenior = 'senior';

  static String normalizeSection(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    // Take the first slug if a legacy multi value sneaks in.
    final first = s.split(RegExp(r'[,;|/+]')).first.trim();
    if (first == 'sub junior' ||
        first == 'sub-junior' ||
        first == 'subjunior' ||
        first == 'sub_junior') {
      return sectionSubJunior;
    }
    if (first == 'junior') return sectionJunior;
    if (first == 'senior') return sectionSenior;
    return sectionAll;
  }

  static String prettySection(String? raw) {
    switch (normalizeSection(raw)) {
      case sectionSubJunior:
        return 'Sub Junior';
      case sectionJunior:
        return 'Junior';
      case sectionSenior:
        return 'Senior';
      default:
        return 'All Sections';
    }
  }

  // -- dates -----------------------------------------------------------------------
  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// Parses `event_date` (DATE `yyyy-MM-dd`, possibly with time suffix).
  static DateTime? dateOf(Map<String, dynamic> row) {
    final raw = (row['event_date'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    } catch (_) {
      return null;
    }
  }

  /// `December 25, 2026` ('' when the post has no event date).
  static String prettyDate(Map<String, dynamic> row) {
    final d = dateOf(row);
    if (d == null) return '';
    return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String monthLabel(int year, int month) =>
      '${_fullMonths[month - 1]} $year';

  /// `yyyy-MM` key for the year/month filter ('' when dateless).
  static String monthKeyOf(Map<String, dynamic> row) {
    final d = dateOf(row);
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}';
  }

  // -- visibility ---------------------------------------------------------------------
  static bool visibleTo(
    Map<String, dynamic> row, {
    required String role,
    String? section,
  }) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return true;
    if (r == 'teacher') return true;
    if (r == 'student') {
      final post = normalizeSection(row['section']?.toString());
      if (post == sectionAll) return true;
      final mine = normalizeSection(section);
      if (mine == sectionAll) return true;
      return post == mine;
    }
    return false;
  }

  // -- photos ----------------------------------------------------------------------------
  /// Photos grouped by gallery id, ordered by display_order.
  static Map<int, List<Map<String, dynamic>>> photosByGallery(
      List<Map<String, dynamic>> photos) {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final p in photos) {
      final gid = (p['gallery_id'] as num?)?.toInt();
      if (gid == null) continue;
      out.putIfAbsent(gid, () => []).add(p);
    }
    for (final list in out.values) {
      list.sort((a, b) {
        final oa = (a['display_order'] as num?)?.toInt() ?? 0;
        final ob = (b['display_order'] as num?)?.toInt() ?? 0;
        if (oa != ob) return oa.compareTo(ob);
        return (a['id'] as num? ?? 0).compareTo(b['id'] as num? ?? 0);
      });
    }
    return out;
  }

  static int postIdOf(Map<String, dynamic> row) =>
      (row['id'] as num?)?.toInt() ?? -1;

  static int photoCountOf(
      Map<int, List<Map<String, dynamic>>> byGallery, int galleryId) =>
      byGallery[galleryId]?.length ?? 0;

  static String? coverUrlOf(
      Map<int, List<Map<String, dynamic>>> byGallery, int galleryId) {
    final list = byGallery[galleryId];
    if (list == null || list.isEmpty) return null;
    final url = (list.first['photo_url'] ?? '').toString().trim();
    return url.isEmpty ? null : url;
  }

  static String photoUrlOf(Map<String, dynamic> photo) =>
      (photo['photo_url'] ?? '').toString();

  static String storagePathOf(Map<String, dynamic> photo) =>
      (photo['storage_path'] ?? '').toString();

  // -- storage ------------------------------------------------------------------------------
  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  static String _extOf(String name) {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  static bool isImageName(String name) =>
      _imageExts.contains(_extOf(name));

  static String mimeFor(String fileName) {
    switch (_extOf(fileName)) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  static String _sanitizeFileName(String name) {
    var n = name.trim().isEmpty ? 'photo.jpg' : name.trim();
    return n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// `{gallery_id}/{timestamp}-{rand}-{filename}` inside the bucket.
  static String storagePath(int galleryId, String fileName) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (ts % 2176782336).toRadixString(36).padLeft(6, '0');
    return '$galleryId/$ts-$rand-${_sanitizeFileName(fileName)}';
  }

  static String publicUrl(SupabaseClient client, String path) =>
      client.storage.from(bucket).getPublicUrl(path);
}
