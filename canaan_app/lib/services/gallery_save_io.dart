import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Mobile/desktop implementation: downloads the image bytes, then saves
/// them straight into the device's Photos/Gallery via `gal` — the user
/// never has to hunt for a downloaded file.
Future<bool> saveGalleryPhotoToPhone({
  required String imageUrl,
  required String fileName,
}) async {
  final url = imageUrl.trim();
  if (url.isEmpty) return false;
  try {
    // Photo/media permission first (no-op where not required).
    try {
      final granted = await Gal.requestAccess();
      if (!granted) {
        final has = await Gal.hasAccess();
        if (!has) return false;
      }
    } catch (_) {
      return false;
    }
    final bytes = await _downloadBytes(url);
    if (bytes == null || bytes.isEmpty) return false;
    await Gal.putImageBytes(bytes, name: _baseName(fileName));
    return true;
  } catch (_) {
    return false;
  }
}

Future<Uint8List?> _downloadBytes(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final chunks = <int>[];
    await for (final data in response) {
      chunks.addAll(data);
    }
    return Uint8List.fromList(chunks);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

String _baseName(String fileName) {
  var n = fileName.trim();
  if (n.isEmpty) n = 'canaan-gallery.jpg';
  n = n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (!n.contains('.')) n = '$n.jpg';
  return n;
}
