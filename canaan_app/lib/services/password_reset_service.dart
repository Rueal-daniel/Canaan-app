/// Shared password-reset logic.
///
/// Uses the `password_reset_requests` table:
///   id, full_name, role (student|teacher), request_type
///   (username|password|both), status
///   (pending|link_sent|completed|rejected), user_id,
///   token_expires_at (approval window), attempts, processed_by,
///   processed_at, completed_at, created_at, updated_at
///
/// Flow: the person submits a request → Admin approves → the person
/// checks their approval on the Reset page and is taken straight
/// into the recovery chatbot (no codes, no SMS). Approvals stay
/// valid for 30 minutes and name checks lock after 5 wrong attempts.
///
/// Security notes (same pattern as the rest of the app):
///   • Passwords are never read or displayed anywhere — the password
///     column is never selected, logged, or sent.
class PasswordResetService {
  static const table = 'password_reset_requests';

  static const roleStudent = 'student';
  static const roleTeacher = 'teacher';

  static const typeUsername = 'username';
  static const typePassword = 'password';
  static const typeBoth = 'both';

  static const statusPending = 'pending';
  static const statusLinkSent = 'link_sent';
  static const statusCompleted = 'completed';
  static const statusRejected = 'rejected';

  /// Approvals stay valid for 30 minutes after Admin approval.
  static const tokenValidityMinutes = 30;

  /// Name checks lock after this many wrong attempts.
  static const maxAttempts = 5;

  static DateTime expiryFromNow() =>
      DateTime.now().add(const Duration(minutes: tokenValidityMinutes));

  static bool isExpired(Map<String, dynamic> row) {
    final raw = (row['token_expires_at'] ?? '').toString();
    if (raw.isEmpty) return true;
    try {
      return DateTime.parse(raw).isBefore(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  static bool isLocked(Map<String, dynamic> row) {
    final a = row['attempts'];
    final n = a is num ? a.toInt() : int.tryParse('$a') ?? 0;
    return n >= maxAttempts;
  }

  static String prettyRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    if (r == roleTeacher) return 'Teacher';
    return 'Student';
  }

  static String prettyType(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case typeUsername:
        return 'Username';
      case typePassword:
        return 'Password';
      default:
        return 'Username & Password';
    }
  }

  static String prettyStatus(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case statusPending:
        return 'Pending';
      case statusLinkSent:
        return 'Link Sent';
      case statusCompleted:
        return 'Completed';
      default:
        return 'Rejected';
    }
  }

  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// `September 6, 2026`.
  static String prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  static String norm(String? v) => (v ?? '').trim().toLowerCase();
}
