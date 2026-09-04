import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_service.dart';

enum UserRole { admin, teacher, student }

/// Thrown when valid credentials belong to a suspended student.
class AccountSuspendedException implements Exception {
  const AccountSuspendedException();
}

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  static const suspendedStatus = 'suspended';
  static const activeStatus = 'active';

  static bool isSuspended(Map<String, dynamic>? row) {
    if (row == null) return true;
    return (row['status'] ?? '').toString().trim().toLowerCase() ==
        suspendedStatus;
  }

  String _getTableForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'admin';
      case UserRole.teacher:
        return 'teachers';
      case UserRole.student:
        return 'students';
    }
  }

  UserRole? _roleFromString(String? role) {
    switch (role) {
      case 'admin':
        return UserRole.admin;
      case 'teacher':
        return UserRole.teacher;
      case 'student':
        return UserRole.student;
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>?> login({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    final table = _getTableForRole(role);

    final response = await _client
        .from(table)
        .select()
        .eq('username', username)
        .eq('password', password)
        .maybeSingle();

    if (response == null) return null;
    // Suspended students authenticate but must never enter the dashboard.
    if (role == UserRole.student && isSuspended(response)) {
      throw const AccountSuspendedException();
    }
    return response;
  }

  /// Re-validates a persisted session against Supabase.
  ///
  /// Returns the fresh user row (without password) when the id still
  /// exists in the table belonging to [role], otherwise null.
  Future<Map<String, dynamic>?> getUserById({
    required String userId,
    required UserRole role,
  }) async {
    final table = _getTableForRole(role);

    final response = await _client
        .from(table)
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    // Never hand the password hash/value back to the UI layer.
    response.remove('password');
    return response;
  }

  /// Restores the Supabase login session, if one exists.
  ///
  /// 1. First checks Supabase's own persistent auth session
  ///    (`auth.currentSession`, restored automatically by
  ///    supabase_flutter across app restarts / "Close all").
  /// 2. Falls back to the locally persisted profile session
  ///    (Supabase row id + role only — never username/password)
  ///    and verifies it is still valid in Supabase.
  ///
  /// Throws [AccountSuspendedException] when the restored profile belongs
  /// to a suspended student (after wiping the local session).
  ///
  /// Returns the fresh user row + verified role, or null.
  Future<({Map<String, dynamic> user, UserRole role})?> restoreSession() async {
    // 1. Native Supabase Auth session (survives app close / restart).
    try {
      final supabaseSession = _client.auth.currentSession;
      final supabaseUser = _client.auth.currentUser;
      if (supabaseSession != null && supabaseUser != null) {
        final role = _roleFromString(
          supabaseUser.userMetadata?['role'] as String?,
        );
        if (role != null) {
          final profile = await getUserById(
            userId: supabaseUser.id,
            role: role,
          );
          if (profile != null) {
            await _throwIfSuspended(role, profile);
            return (user: profile, role: role);
          }
        }
        // A Supabase Auth session without a mappable app role falls
        // through to the profile-session check below.
      }
    } on AccountSuspendedException {
      rethrow;
    } catch (_) {
      // Ignore and fall through to the profile session check.
    }

    // 2. Persisted profile session (id + role only).
    try {
      final saved = await SessionService.getSession();
      if (saved == null) return null;

      final role = _roleFromString(saved.role);
      if (role == null) {
        await SessionService.clearSession();
        return null;
      }

      final profile = await getUserById(userId: saved.userId, role: role);
      if (profile == null) {
        // User was deleted/deactivated or role changed — drop session.
        await SessionService.clearSession();
        return null;
      }
      await _throwIfSuspended(role, profile);
      return (user: profile, role: role);
    } on AccountSuspendedException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Clears any session and throws [AccountSuspendedException] when the
  /// profile belongs to a suspended student.
  Future<void> _throwIfSuspended(
    UserRole role,
    Map<String, dynamic> profile,
  ) async {
    if (role == UserRole.student && isSuspended(profile)) {
      await logout();
      throw const AccountSuspendedException();
    }
  }

  /// Suspends or restores a student account.
  ///
  /// Always writes `status`; suspension timestamp + acting admin are
  /// written resiliently (kept when the migration adding those columns
  /// has been run, skipped otherwise).
  Future<void> setStudentStatus({
    required String studentId,
    required bool suspended,
    required String adminId,
  }) async {
    final payload = <String, dynamic>{
      'status': suspended ? suspendedStatus : activeStatus,
      'suspended_at': suspended ? DateTime.now().toIso8601String() : null,
      'suspended_by_admin_id': suspended
          ? (adminId.isEmpty ? null : adminId)
          : null,
    };
    try {
      await _client.from('students').update(payload).eq('id', studentId);
    } catch (_) {
      await _client
          .from('students')
          .update({'status': suspended ? suspendedStatus : activeStatus})
          .eq('id', studentId);
    }
  }

  /// Fully signs out: clears Supabase Auth state (revokes the persisted
  /// Supabase token) and wipes the local profile session so the next
  /// app start correctly lands on the Login page.
  Future<void> logout() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // No active Supabase Auth session — still clear local state below.
    }
    await SessionService.clearSession();
  }
}
