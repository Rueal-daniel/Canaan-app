import 'package:web/web.dart' as web;

/// Web implementation: triggers a normal browser download of the image
/// (there is no shared Photos gallery on web to save into).
Future<bool> saveGalleryPhotoToPhone({
  required String imageUrl,
  required String fileName,
}) async {
  final url = imageUrl.trim();
  if (url.isEmpty) return false;
  try {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName.trim().isEmpty ? 'canaan-gallery.jpg' : fileName.trim()
      ..target = '_blank';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}
