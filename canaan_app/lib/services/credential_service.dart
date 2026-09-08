/// Shared Change-Credentials logic.
///
/// Uses the `credential_change_requests` table:
///   id, user_id, role (teacher|student), section, full_name, email,
///   current_username, requested_username (nullable), change_type
///   (username|password|username_and_password), status
///   (pending|approved|rejected), rejection_reason (nullable),
///   requested_at, reviewed_at, reviewed_by, created_at, updated_at
///
/// Security contract (enforced in the UI layer):
///   • Passwords are NEVER stored in the request table — not current,
///     new, or confirm. Username changes store only the requested
///     username (not sensitive).
///   • Passwords are NEVER displayed — not to the user beyond their
///     own typing fields, and never to the Admin.
///   • Nothing changes until Admin approves: the app updates the
///     teachers/students row only inside the approval step (username)
///     or the post-approval set-password step (password, by the user).
class CredentialService {
  static const table = 'credential_change_requests';

  static const roleTeacher = 'teacher';
  static const roleStudent = 'student';

  static const typeUsername = 'username';
  static const typePassword = 'password';
  static const typeBoth = 'username_and_password';

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  static String userTable(String role) =>
      role == roleTeacher ? 'teachers' : 'students';

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
      case statusApproved:
        return 'Approved';
      default:
        return 'Rejected';
    }
  }

  /// Short history label: `Username Change`, `Password Change`.
  static String prettyShortType(String? type) {
    switch ((type ?? '').trim().toLowerCase()) {
      case typeUsername:
        return 'Username Change';
      case typePassword:
        return 'Password Change';
      default:
        return 'Username & Password Change';
    }
  }

  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// `Sept 8, 2026`.
  static String prettyShortDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '';
    try {
      final d = DateTime.parse(src).toLocal();
      const short = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'
      ];
      return '${short[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  /// `September 8, 2026`.
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

  /// Minimum password rule for the set-new-password step.
  static String? validateNewPassword(String value) {
    if (value.isEmpty) return 'New password is required.';
    if (value.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }
}
