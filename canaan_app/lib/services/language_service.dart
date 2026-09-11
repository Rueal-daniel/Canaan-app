import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';

/// Global localization state for the Canaan app (proper i18n: ONE app,
/// every UI string resolved through [tr] at build time — never two
/// copies of the app).
///
/// * Default language is English; Nepali is opt-in per user.
/// * Preference is per-user (role + row id), persisted locally for
///   instant boot AND in the user's profile row (`language` column on
///   students/teachers/admin — see `supabase/language.sql`) so it roams
///   across devices. Every step is best-effort: local always wins ties.
/// * Changing the language notifies [current]; screens wrapped in
///   [LangBuilder]/ValueListenableBuilder rebuild immediately, no
///   logout required. User-generated content (names, notices, tasks…)
///   is never translated.
class LanguageService {
  static const supported = ['en', 'ne'];
  static const defaultCode = 'en';

  static const _globalKey = 'canaan_language_global';
  static String _userKey(String role, String userId) =>
      'canaan_language_${role.trim().toLowerCase()}_${userId.trim()}';

  /// Notifies on every language change — screens listen to rebuild.
  static final ValueNotifier<String> current =
      ValueNotifier<String>(defaultCode);

  static String get code => current.value;
  static bool get isNepali => code == 'ne';

  static String? _role;
  static String? _userId;

  static String _tableFor(String role) {
    switch (role.trim().toLowerCase()) {
      case 'teacher':
        return 'teachers';
      case 'admin':
        return 'admin';
      default:
        return 'students';
    }
  }

  /// Binds the service to the logged-in user and loads their saved
  /// language (per-user pref → profile row → global → English).
  static Future<void> bind({
    required String role,
    required String userId,
  }) async {
    final r = role.trim().toLowerCase();
    final u = userId.trim();
    if (r.isEmpty || u.isEmpty) return;
    _role = r;
    _userId = u;
    try {
      final prefs = await SharedPreferences.getInstance();
      var code = prefs.getString(_userKey(r, u));
      code ??= await _loadRemote(r, u);
      code ??= prefs.getString(_globalKey);
      _apply(_sanitize(code));
    } catch (_) {}
  }

  /// Switches language now + persists (per-user, global, profile row).
  static Future<void> setLang(
    String code, {
    String? role,
    String? userId,
  }) async {
    final clean = _sanitize(code);
    _apply(clean);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_globalKey, clean);
      final r = (role ?? _role ?? '').trim().toLowerCase();
      final u = (userId ?? _userId ?? '').trim();
      if (r.isNotEmpty && u.isNotEmpty) {
        await prefs.setString(_userKey(r, u), clean);
        await _saveRemote(r, u, clean);
      }
    } catch (_) {}
  }

  static void _apply(String code) {
    if (current.value != code) current.value = code;
  }

  static String _sanitize(String? code) {
    final c = (code ?? '').trim().toLowerCase();
    return supported.contains(c) ? c : defaultCode;
  }

  static Future<String?> _loadRemote(String role, String userId) async {
    try {
      final row = await Supabase.instance.client
          .from(_tableFor(role))
          .select('language')
          .eq('id', userId)
          .maybeSingle();
      final v = (row?['language'] ?? '').toString().trim().toLowerCase();
      return supported.contains(v) ? v : null;
    } catch (_) {
      // Column missing (migration not run) — local pref still works.
      return null;
    }
  }

  static Future<void> _saveRemote(
      String role, String userId, String code) async {
    try {
      await Supabase.instance.client
          .from(_tableFor(role))
          .update({'language': code}).eq('id', userId);
    } catch (_) {
      // Column missing — local pref still works.
    }
  }
}

/// Translates [key] to the current language (English fallback, then the
/// key itself — never blank, never a crash).
String tr(String key) => AppStrings.get(LanguageService.code, key);

/// Translates [key] and fills `{placeholders}` from [params].
String trp(String key, Map<String, String> params) {
  var s = tr(key);
  params.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

/// Rebuilds [builder] on every language change.
class LangBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) builder;
  const LangBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.current,
      builder: (ctx, value, child) => builder(ctx),
    );
  }
}
