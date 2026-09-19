import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/update_config.dart';

/// Remote update descriptor (validated before use).
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

  /// Returns null when the payload is missing/invalid anything.
  static RemoteUpdate? parse(dynamic json) {
    try {
      if (json is! Map) return null;
      final versionName = (json['versionName'] ?? '').toString().trim();
      final versionCode = int.tryParse('${json['versionCode']}');
      final apkUrl = (json['apkUrl'] ?? '').toString().trim();
      if (versionName.isEmpty || versionCode == null || versionCode <= 0) {
        return null;
      }
      final uri = Uri.tryParse(apkUrl);
      // HTTPS only, must point at an .apk file. No credentials in URLs.
      if (uri == null ||
          uri.scheme != 'https' ||
          !uri.path.toLowerCase().endsWith('.apk') ||
          (uri.userInfo.isNotEmpty)) {
        return null;
      }
      final whatsNew = <String>[];
      final rawList = json['whatsNew'];
      if (rawList is List) {
        for (final e in rawList) {
          final s = e.toString().trim();
          if (s.isNotEmpty) whatsNew.add(s);
        }
      }
      return RemoteUpdate(
        versionName: versionName,
        versionCode: versionCode,
        apkUrl: apkUrl,
        updateTitle: (json['updateTitle'] ?? 'Canaan Update Available')
            .toString()
            .trim(),
        updateDescription:
            (json['updateDescription'] ?? 'A new version of Canaan is available.')
                .toString()
                .trim(),
        whatsNew: whatsNew,
        forceUpdate: json['forceUpdate'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Result of a startup update check.
class UpdateCheckResult {
  final RemoteUpdate? update;
  final int installedCode;
  final String installedName;
  final bool updatedSinceLastRun;
  final int? previousCode;
  final String? previousName;
  const UpdateCheckResult({
    required this.update,
    required this.installedCode,
    required this.installedName,
    required this.updatedSinceLastRun,
    this.previousCode,
    this.previousName,
  });
}

class DownloadProgress {
  final int received;
  final int? total;
  const DownloadProgress(this.received, this.total);
  double? get fraction =>
      total == null || total! <= 0 ? null : received / total!;
}

/// Self-update engine: version check, real APK download with byte
/// progress, file validation, and handoff to the Android installer.
/// No new packages — HttpClient, path_provider and SharedPreferences
/// only (plus one tiny native channel for version/install).
class AppUpdateService {
  static const _channel = MethodChannel('canaan_app/update');

  static const _kLastKnownCode = 'canaan_update_last_known_code';
  static const _kLastKnownName = 'canaan_update_last_known_name';
  static const _kSuccessShownFor = 'canaan_update_success_shown_for';
  static const _kSkippedCode = 'canaan_update_skipped_code';

  static const Duration _configTimeout = Duration(seconds: 8);

  // -- installed version -------------------------------------------------------

  /// Installed Android versionCode, or null on non-Android / failure.
  static Future<int?> installedVersionCode() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;
    try {
      final code = await _channel.invokeMethod<int>('getVersionCode');
      return code;
    } catch (_) {
      return null;
    }
  }

  /// Installed versionName from the Android package (never hardcoded,
  /// so it always matches pubspec `version: <name>+<code>`).
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

  // -- remote config --------------------------------------------------------------

  static Future<RemoteUpdate?> fetchRemoteUpdate() async {
    final configUri = Uri.tryParse(UpdateConfig.updateConfigUrl);
    if (configUri == null || configUri.scheme != 'https') return null;
    final client = HttpClient()
      ..connectionTimeout = _configTimeout;
    try {
      final req = await client
          .getUrl(configUri)
          .timeout(_configTimeout);
      final res = await req.close().timeout(_configTimeout);
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_configTimeout);
      if (body.trim().isEmpty || body.length > 100 * 1024) return null;
      return RemoteUpdate.parse(jsonDecode(body));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// True ONLY when the released APK's versionCode is higher than the
  /// installed one. Website/database/message changes never trigger it.
  static bool shouldUpdate(int? installedCode, RemoteUpdate? remote) {
    if (installedCode == null || remote == null) return false;
    return remote.versionCode > installedCode;
  }

  // -- startup check -----------------------------------------------------------------

  /// Runs once at startup. Never throws; null-safe offline behaviour
  /// is "proceed to the app".
  static Future<UpdateCheckResult?> checkAtStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final installedCode = await installedVersionCode();
      if (installedCode == null) return null; // not Android: no updates

      final installedName =
          await installedVersionName() ?? 'v$installedCode';
      final prevCode = prefs.getInt(_kLastKnownCode);
      final prevName = prefs.getString(_kLastKnownName);
      final updated =
          prevCode != null && prevCode != installedCode;

      // Remember this version for next launch BEFORE any navigation.
      await prefs.setInt(_kLastKnownCode, installedCode);
      await prefs.setString(_kLastKnownName, installedName);

      RemoteUpdate? update;
      try {
        final remote = await fetchRemoteUpdate();
        if (shouldUpdate(installedCode, remote)) {
          final skipped = prefs.getInt(_kSkippedCode);
          // "Later" skips prompting again for the same version this device
          // already dismissed — a newer versionCode still prompts.
          if (skipped != remote!.versionCode) update = remote;
        }
      } catch (_) {}

      return UpdateCheckResult(
        update: update,
        installedCode: installedCode,
        installedName: installedName,
        updatedSinceLastRun: updated,
        previousCode: prevCode,
        previousName: prevName,
      );
    } catch (_) {
      return null;
    }
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

  // -- download --------------------------------------------------------------------------

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

    final client = HttpClient()..connectionTimeout = _configTimeout;
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
      final total =
          res.contentLength >= 0 ? res.contentLength : null;
      sink = file.openWrite();
      await for (final chunk in res) {
        if (cancelled) throw _CancelledException();
        sink.add(chunk);
        received += chunk.length;
        onProgress(DownloadProgress(received, total));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // Validate: real, complete, actually-an-APK file.
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
    // APKs are ZIPs: must start with the PK magic header.
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

  // -- install --------------------------------------------------------------------------------

  /// Hands the verified APK to Android's system installer.
  /// Returns null on success, or a user-facing error message.
  static Future<String?> installApk(File file) async {
    if (!Platform.isAndroid) return 'APK install is only available on Android.';
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

class _CancelledException implements Exception {
  const _CancelledException();
  @override
  String toString() => 'Download cancelled';
}
