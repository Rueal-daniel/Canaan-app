import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Lesson Plan logic for Admin + Teacher.
///
/// Connects to the EXISTING Supabase tables (no new tables):
///   `lesson_plans` (id, title, summary_en, summary_np, subject,
///     grade, status, created_by, created_by_name, created_at,
///     updated_at, published_at)
///   `lesson_plan_files` (id, lesson_id, file_name, file_path,
///     file_size, mime_type, created_at)
///
/// PDFs live in the existing `lesson-files` storage bucket.
///
/// Column mapping notes:
///   • Section selector  <-> `grade` (sub-junior / junior / senior)
///   • Summary (Nepali)  <-> `summary_np`
///   • About text        <-> `subject` (the only free text column;
///     existing rows hold 'Sunday School' there)
///   • Publish           -> `status` = 'published', `published_at` = now
///   • "Upcoming Saturday" is display logic (see [upcomingSaturday]);
///     the prominent plan is the newest published plan for the section.
class LessonPlanService {
  static const table = 'lesson_plans';
  static const filesTable = 'lesson_plan_files';
  static const bucket = 'lesson-files';

  static const sectionSubJunior = 'sub-junior';
  static const sectionJunior = 'junior';
  static const sectionSenior = 'senior';

  static const sections = [
    sectionSubJunior,
    sectionJunior,
    sectionSenior,
  ];

  static const statusPublished = 'published';

  /// Next Saturday after [from] (or now). If today IS Saturday,
  /// the *next* Saturday (+7 days) is returned — never today.
  static DateTime upcomingSaturday([DateTime? from]) {
    final base = from ?? DateTime.now();
    final dateOnly = DateTime(base.year, base.month, base.day);
    var daysUntilSaturday = DateTime.saturday - dateOnly.weekday;
    if (daysUntilSaturday <= 0) daysUntilSaturday += 7;
    return dateOnly.add(Duration(days: daysUntilSaturday));
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// `Saturday, September 12, 2026`.
  static String prettyLessonDate(DateTime d) =>
      'Saturday, ${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// `Aug 21, 2026` for a stored timestamp.
  static String prettyDateTime(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      return '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  static String prettySection(String? grade) {
    final s = (grade ?? '').trim().toLowerCase();
    if (s == 'sub-junior' || s == 'sub junior' || s == 'subjunior') {
      return 'Sub Junior';
    }
    if (s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Normalises UI labels (`Sub Junior`) to DB values (`sub-junior`).
  static String normalizeSection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s == 'sub junior' || s == 'sub-junior' || s == 'subjunior') {
      return sectionSubJunior;
    }
    if (s == 'junior') return sectionJunior;
    if (s == 'senior') return sectionSenior;
    return s;
  }

  static bool isPdfName(String name) =>
      name.trim().toLowerCase().endsWith('.pdf');

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _sanitizeFileName(String name) {
    var n = name.trim().isEmpty ? 'lesson.pdf' : name.trim();
    n = n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!n.toLowerCase().endsWith('.pdf')) n = '$n.pdf';
    return n;
  }

  /// Flat storage path mirroring the existing rows:
  /// `{timestampMs}-{rand6}-{filename}` at the bucket root.
  static String storagePath(String fileName) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (ts % 2176782336).toRadixString(36).padLeft(6, '0');
    return '$ts-$rand-${_sanitizeFileName(fileName)}';
  }

  static String publicUrl(SupabaseClient client, String path) =>
      client.storage.from(bucket).getPublicUrl(path);

  /// Readable PDF URL for a stored path: signed URL first (works for
  /// private buckets too), public URL fallback.
  static Future<String?> resolvePdfUrl(
      SupabaseClient client, String path) async {
    try {
      return await client.storage.from(bucket).createSignedUrl(path, 3600);
    } catch (_) {
      try {
        return publicUrl(client, path);
      } catch (_) {
        return null;
      }
    }
  }

  // ------------------------------------------------------------------
  // Resilient column readers.
  // ------------------------------------------------------------------

  /// About text lives in `subject` (only free text column available).
  static String aboutOf(Map<String, dynamic> row) =>
      ((row['about'] ?? row['subject'] ?? '').toString());

  static String summaryEnOf(Map<String, dynamic> row) {
    for (final k in ['summary_en', 'summary_english', 'summaryEn']) {
      final v = (row[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String summaryNeOf(Map<String, dynamic> row) {
    for (final k in ['summary_np', 'summary_ne', 'summary_nepali', 'summaryNe']) {
      final v = (row[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Newest-first publish date for display: published_at, else created_at.
  static String publishDateOf(Map<String, dynamic> row) =>
      ((row['published_at'] ?? row['created_at'] ?? '').toString());

  static String fileNameOf(Map<String, dynamic> fileRow) =>
      (fileRow['file_name'] ?? fileRow['filename'] ?? '').toString();

  static String filePathOf(Map<String, dynamic> fileRow) =>
      (fileRow['file_path'] ?? fileRow['filepath'] ?? '').toString();

  static int fileSizeOf(Map<String, dynamic> fileRow) {
    final v = fileRow['file_size'] ?? fileRow['filesize'];
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }
}
