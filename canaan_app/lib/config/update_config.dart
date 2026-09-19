/// Remote update configuration for the Canaan self-update system.
///
/// Host ONE JSON file on the website (HTTPS) and point [updateConfigUrl]
/// at it. Example:
///
///   {
///     "versionName": "1.1.0",
///     "versionCode": 2,
///     "apkUrl": "https://canaan-ss.site.je/app/canaan-1.1.0.apk",
///     "updateTitle": "Canaan Update Available",
///     "updateDescription": "A new version of Canaan is available.",
///     "whatsNew": ["New feature added", "Improvements", "Bug fixes"],
///     "forceUpdate": false
///   }
///
/// Release checklist (every release):
///   1. Bump pubspec `version: <name>+<code>` (higher versionCode!).
///   2. Build a signed release APK with the SAME package ID + key.
///   3. Upload the APK to the website.
///   4. Update the JSON above (versionCode MUST match the APK).
class UpdateConfig {
  /// Hosted alongside the GitHub releases. To move it to the website,
  /// upload update.json there and change this URL (must stay HTTPS).
  static const String updateConfigUrl =
      'https://raw.githubusercontent.com/Rueal-daniel/Canaan-app/main/update.json';
}
