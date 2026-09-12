import 'gallery_save_io.dart'
    if (dart.library.js_interop) 'gallery_save_web.dart' as impl;

/// Saves ONE gallery photo to the device's Photos/Gallery
/// (⬇️ Save to Phone). Never throws — returns true only when the
/// photo actually landed where the user can find it.
///
/// Mobile/desktop go through the `gal` plugin (permission is requested
/// first); web downloads the file via the browser.
Future<bool> saveGalleryPhotoToPhone({
  required String imageUrl,
  required String fileName,
}) =>
    impl.saveGalleryPhotoToPhone(imageUrl: imageUrl, fileName: fileName);
