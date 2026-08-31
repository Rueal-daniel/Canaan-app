import 'package:supabase_flutter/supabase_flutter.dart';

enum UserRole { admin, teacher, student }

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

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

    return response;
  }
}
