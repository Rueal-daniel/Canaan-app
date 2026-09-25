import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin-controlled app update system, backed by the `app_updates`
/// table (id, title, description, apk_url, version_name,
/// version_code, force_update, status, created_by, created_at,
/// updated_at, published_at).
///
/// Status: draft | published | unpublished. The ACTIVE update is the
/// highest-versionCode published row. An update popup appears ONLY
/// when published versionCode > installed versionCode — creating or
/// editing records never triggers anything by itself.
class AppUpdate {
  final String id;
  final String title;
  final String descriptionHtml;
  final String apkUrl;
  final String versionName;
  final int versionCode;
  final bool forceUpdate;
  final String status;
  final String? publishedAt;
  final String? createdAt;

  const AppUpdate({
    required this.id,
    required this.title,
    required this.descriptionHtml,
    required this.apkUrl,
    required this.versionName,
    required this.versionCode,
    required this.forceUpdate,
    required this.status,
    this.publishedAt,
    this.createdAt,
  });

  /// Validated parse: rejects bad APK URLs (HTTPS + .apk only, no
  /// credentials), empty titles/versions, non-positive codes.
  static AppUpdate? fromRow(Map<String, dynamic> row) {
    try {
      final title = (row['title'] ?? '').toString().trim();
      final apkUrl = (row['apk_url'] ?? '').toString().trim();
      final versionName = (row['version_name'] ?? '').toString().trim();
      final versionCode = int.tryParse('${row['version_code']}');
      if (title.isEmpty || versionName.isEmpty || versionCode == null) {
        return null;
      }
      if (versionCode <= 0) return null;
      final uri = Uri.tryParse(apkUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          !uri.path.toLowerCase().endsWith('.apk') ||
          uri.userInfo.isNotEmpty) {
        return null;
      }
      final force = row['force_update'] == true ||
          '${row['force_update']}'.toLowerCase() == 'true';
      return AppUpdate(
        id: (row['id'] ?? '').toString(),
        title: title,
        descriptionHtml: (row['description'] ?? '').toString(),
        apkUrl: apkUrl,
        versionName: versionName,
        versionCode: versionCode,
        forceUpdate: force,
        status: (row['status'] ?? '').toString(),
        publishedAt: row['published_at']?.toString(),
        createdAt: row['created_at']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Download descriptor for the existing [UpdatingScreen].
  RemoteUpdate toRemote() => RemoteUpdate(
        versionName: versionName,
        versionCode: versionCode,
        apkUrl: apkUrl,
        updateTitle: title,
        updateDescription: '',
        whatsNew: const [],
        forceUpdate: forceUpdate,
      );
}

/// Validated remote APK descriptor used by the downloader/installer.
class RemoteUpdate {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String updateTitle;
  final String updateDescription;
  final List<String> whatsNew;
  final bool forceUpdate;

  const RemoteUpdate({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.updateTitle,
    required this.updateDescription,
    required this.whatsNew,
    required this.forceUpdate,
  });
}

class DownloadProgress {
  final int received;
  final int? total;
  const DownloadProgress(this.received, this.total);
  double? get fraction =>
      total == null || total! <= 0 ? null : received / total!;
}

class AppUpdateService {
  static const table = 'app_updates';
  static const _channel = MethodChannel('canaan_app/update');

  static const statusDraft = 'draft';
  static const statusPublished = 'published';
  static const statusUnpublished = 'unpublished';

  static const _kLastKnownCode = 'canaan_update_last_known_code';
  static const _kLastKnownName = 'canaan_update_last_known_name';
  static const _kSuccessShownFor = 'canaan_update_success_shown_for';
  static const _kSkippedCode = 'canaan_update_skipped_code';

  static const Duration _timeout = Duration(seconds: 10);

  static SupabaseClient get _client => Supabase.instance.client;

  // -- installed version ---------------------------------------------------------

  /// Installed Android versionCode, or null on non-Android / failure.
  static Future<int?> installedVersionCode() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('getVersionCode');
    } catch (_) {
      return null;
    }
  }

  /// Installed versionName from the Android package (never hardcoded).
  static Future<String?> installedVersionName() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;
    try {
      final name = await _channel.invokeMethod<String>('getVersionName');
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null;
    }
  }

  // -- active update -----------------------------------------------------------------

  /// The active update: highest-versionCode published row, validated.
  /// Null when none exists, Supabase is unreachable, or data invalid.
  static Future<AppUpdate?> fetchActiveUpdate() async {
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .eq('status', statusPublished)
          .order('version_code', ascending: false)
          .limit(3);
      for (final r in (rows as List)) {
        final u =
            AppUpdate.fromRow(Map<String, dynamic>.from(r as Map));
        if (u != null) return u;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True ONLY when the published APK's versionCode is higher than the
  /// installed one. Record creation, edits, notices or alerts never
  /// trigger it.
  static bool shouldUpdate(int? installedCode, AppUpdate? remote) {
    if (installedCode == null || remote == null) return false;
    return remote.versionCode > installedCode;
  }

  static Future<List<Map<String, dynamic>>> fetchHistory() async {
    try {
      final rows = await _client
          .from(table)
          .select('*')
          .order('version_code', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  // -- startup state -------------------------------------------------------------------

  static Future<UpdateStartupState> checkAtStartup() async {
    int? installedCode;
    String installedName = '';
    int? prevCode;
    String? prevName;
    AppUpdate? update;
    try {
      final prefs = await SharedPreferences.getInstance();
      installedCode = await installedVersionCode();
      if (installedCode == null) {
        return const UpdateStartupState.notAndroid();
      }
      installedName = await installedVersionName() ?? 'v$installedCode';
      prevCode = prefs.getInt(_kLastKnownCode);
      prevName = prefs.getString(_kLastKnownName);
      await prefs.setInt(_kLastKnownCode, installedCode);
      await prefs.setString(_kLastKnownName, installedName);
      try {
        final remote = await fetchActiveUpdate()
            .timeout(_timeout, onTimeout: () => null);
        if (shouldUpdate(installedCode, remote)) {
          final skipped = prefs.getInt(_kSkippedCode);
          if (skipped != remote!.versionCode) update = remote;
        }
      } catch (_) {}
    } catch (_) {}
    return UpdateStartupState(
      update: update,
      installedCode: installedCode,
      installedName: installedName,
      updatedSinceLastRun:
          prevCode != null && installedCode != null && prevCode != installedCode,
      previousCode: prevCode,
      previousName: prevName,
    );
  }

  static Future<void> markSkipped(int versionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSkippedCode, versionCode);
    } catch (_) {}
  }

  static Future<bool> successAlreadyShown(String versionName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kSuccessShownFor) == versionName;
    } catch (_) {
      return true; // fail safe: don't nag
    }
  }

  static Future<void> markSuccessShown(String versionName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSuccessShownFor, versionName);
    } catch (_) {}
  }

  // -- download ----------------------------------------------------------------------------

  static Future<Directory> _updatesDir() async {
    Directory base;
    try {
      base = (await getExternalStorageDirectory()) ??
          await getTemporaryDirectory();
    } catch (_) {
      base = await getTemporaryDirectory();
    }
    final dir = Directory('${base.path}/updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String apkFileName(RemoteUpdate update) =>
      'canaan-${update.versionName}.apk'
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Downloads the REAL APK with byte-accurate progress. Throws on
  /// failure; always removes partial files. Cancel via [cancelToken].
  static Future<File> downloadApk(
    RemoteUpdate update, {
    required void Function(DownloadProgress) onProgress,
    required Completer<void> cancelToken,
  }) async {
    final uri = Uri.parse(update.apkUrl);
    final dir = await _updatesDir();
    final file = File('${dir.path}/${apkFileName(update)}');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final client = HttpClient()..connectionTimeout = _timeout;
    IOSink? sink;
    var received = 0;
    var cancelled = false;
    cancelToken.future.then((_) {
      cancelled = true;
      try {
        client.close(force: true);
      } catch (_) {}
    });
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Server returned ${res.statusCode}');
      }
      final total = res.contentLength >= 0 ? res.contentLength : null;
      sink = file.openWrite();
      await for (final chunk in res) {
        if (cancelled) throw const _CancelledException();
        sink.add(chunk);
        received += chunk.length;
        onProgress(DownloadProgress(received, total));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await verifyApk(file, expectedBytes: total);
      return file;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Rejects missing / tiny / truncated / non-APK files.
  static Future<void> verifyApk(File file, {int? expectedBytes}) async {
    if (!await file.exists()) {
      throw const FileSystemException('Downloaded file is missing');
    }
    final length = await file.length();
    if (length < 256 * 1024) {
      throw const FileSystemException('Downloaded file is too small');
    }
    if (expectedBytes != null && expectedBytes > 0 && length != expectedBytes) {
      throw const FileSystemException('Download is incomplete');
    }
    final raf = await file.open();
    try {
      final header = await raf.read(4);
      if (header.length < 4 ||
          header[0] != 0x50 ||
          header[1] != 0x4B ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        throw const FileSystemException('File is not a valid APK');
      }
    } finally {
      await raf.close();
    }
  }

  // -- install ----------------------------------------------------------------------------------

  /// Hands the verified APK to Android's system installer.
  /// Returns null on success, or a user-facing error message.
  static Future<String?> installApk(File file) async {
    if (!Platform.isAndroid) {
      return 'APK install is only available on Android.';
    }
    try {
      final res = await _channel
          .invokeMethod<String>('installApk', {'path': file.path});
      if (res == 'ok') return null;
      return 'Could not open the installer. ($res)';
    } on PlatformException catch (e) {
      if (e.code == 'BLOCKED') {
        return 'Please allow "Install unknown apps" for Canaan in system settings, then tap Install again.';
      }
      return 'Could not open the installer. (${e.message ?? e.code})';
    } catch (e) {
      return 'Could not open the installer. ($e)';
    }
  }

  static String formatMB(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}

class UpdateStartupState {
  final AppUpdate? update;
  final int? installedCode;
  final String installedName;
  final bool updatedSinceLastRun;
  final int? previousCode;
  final String? previousName;
  const UpdateStartupState({
    required this.update,
    required this.installedCode,
    required this.installedName,
    required this.updatedSinceLastRun,
    this.previousCode,
    this.previousName,
  });
  const UpdateStartupState.notAndroid()
      : update = null,
        installedCode = null,
        installedName = '',
        updatedSinceLastRun = false,
        previousCode = null,
        previousName = null;
}

class _CancelledException implements Exception {
  const _CancelledException();
  @override
  String toString() => 'Download cancelled';
}
