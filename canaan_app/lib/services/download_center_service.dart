import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared Download Center logic for Admin / Teacher / Student.
///
/// Connects to the EXISTING Supabase tables (nothing new created):
///   `download_center` (id, title, type, description, posted_by,
///     created_at [, audience when the one-line migration below is run])
///   `download_center_files` (id, item_id, file_name, file_path,
///     file_size, mime_type, created_at)
///
/// Files live in the existing `download-center-files` storage bucket.
/// Videos are plain file attachments (e.g. MP4) — no streaming player
/// packages needed: users download the file, then watch/read it with
/// their own device apps.
///
/// Content types (canonical slugs stored in `type`):
///   document | video | info | other
/// Audience (`audience` column — optional until migrated):
///   teachers | students | everyone
class DownloadCenterService {
  static const table = 'download_center';
  static const filesTable = 'download_center_files';
  static const bucket = 'download-center-files';

  // -- content types ---------------------------------------------------
  static const typeDocument = 'document';
  static const typeVideo = 'video';
  static const typeInfo = 'info';
  static const typeOther = 'other';

  static const types = [typeDocument, typeVideo, typeInfo, typeOther];

  /// Normalises legacy/free-form values (`Video`, `VIDEO`, …) to slugs.
  static String normalizeType(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'video' ||
        s == 'video tutorial' ||
        s == 'tutorial' ||
        s == 'tutorials') {
      return typeVideo;
    }
    if (s == 'document' ||
        s == 'documents' ||
        s == 'doc' ||
        s == 'docs' ||
        s == 'pdf') {
      return typeDocument;
    }
    if (s == 'info' ||
        s == 'information' ||
        s == 'important' ||
        s == 'important information' ||
        s == 'notice' ||
        s == 'announcement') {
      return typeInfo;
    }
    return typeOther;
  }

  static String prettyType(String? raw) {
    switch (normalizeType(raw)) {
      case typeVideo:
        return 'Video Tutorial';
      case typeDocument:
        return 'Document';
      case typeInfo:
        return 'Important Information';
      default:
        return 'Other';
    }
  }

  // -- audience ----------------------------------------------------------
  static const audienceTeachers = 'teachers';
  static const audienceStudents = 'students';
  static const audienceEveryone = 'everyone';

  static String normalizeAudience(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'teachers' || s == 'teacher') return audienceTeachers;
    if (s == 'students' || s == 'student') return audienceStudents;
    return audienceEveryone;
  }

  static String prettyAudience(String? raw) {
    switch (normalizeAudience(raw)) {
      case audienceTeachers:
        return 'Teachers';
      case audienceStudents:
        return 'Students';
      default:
        return 'Everyone';
    }
  }

  /// Audiences a role may see — enforced at the query level.
  static List<String> visibleAudiencesFor(String role) {
    if (role == 'teacher') return [audienceTeachers, audienceEveryone];
    if (role == 'student') return [audienceStudents, audienceEveryone];
    return [audienceTeachers, audienceStudents, audienceEveryone];
  }

  // -- files ---------------------------------------------------------------
  static const _videoExts = {
    'mp4', 'mov', 'mkv', 'webm', 'avi', '3gp', 'm4v'
  };
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  static String _extOf(String name) {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  static String mimeFor(String fileName) {
    switch (_extOf(fileName)) {
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  static bool isVideoFile(String fileName, [String mime = '']) {
    if (mime.toLowerCase().startsWith('video/')) return true;
    return _videoExts.contains(_extOf(fileName));
  }

  static bool isPdfFile(String fileName, [String mime = '']) {
    if (mime.toLowerCase() == 'application/pdf') return true;
    return _extOf(fileName) == 'pdf';
  }

  static bool isImageFile(String fileName, [String mime = '']) {
    if (mime.toLowerCase().startsWith('image/')) return true;
    return _imageExts.contains(_extOf(fileName));
  }

  static bool isPreviewable(String fileName, [String mime = '']) =>
      isPdfFile(fileName, mime) || isImageFile(fileName, mime);

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _sanitizeFileName(String name) {
    var n = name.trim().isEmpty ? 'file' : name.trim();
    return n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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

  /// Readable file URL: signed URL first (private buckets too),
  /// public URL fallback.
  static Future<String?> resolveFileUrl(
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

  // -- resilient readers -----------------------------------------------------
  static String fileNameOf(Map<String, dynamic> fileRow) =>
      (fileRow['file_name'] ?? '').toString();

  static String filePathOf(Map<String, dynamic> fileRow) =>
      (fileRow['file_path'] ?? '').toString();

  static int fileSizeOf(Map<String, dynamic> fileRow) {
    final v = fileRow['file_size'];
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  static String mimeOf(Map<String, dynamic> fileRow) =>
      (fileRow['mime_type'] ?? '').toString();
  /// `September 5, 2026` from created_at.
  static String prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const full = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${full[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }
}
