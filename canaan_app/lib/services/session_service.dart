import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistent session.
///
/// IMPORTANT: we deliberately store ONLY the Supabase row id + role.
/// Never store username, email, or password here. The full profile
/// (name, section, photo) is always re-fetched from Supabase when the
/// session is restored, which also verifies the user/role still exists.
class SessionService {
  static const _keyUserId = 'canaan_session_user_id';
  static const _keyRole = 'canaan_session_role';

  /// Persist the Supabase login session (id + role only).
  static Future<void> saveSession({
    required String userId,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyRole, role);
  }

  /// Returns `{userId, role}` or null when no session was saved.
  static Future<({String userId, String role})?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);
    final role = prefs.getString(_keyRole);
    if (userId == null || userId.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    return (userId: userId, role: role);
  }

  /// Completely clears the local authentication session.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyRole);
  }
}
