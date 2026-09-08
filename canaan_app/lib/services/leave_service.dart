/// Shared Student Leave Application logic.
///
/// Uses the `student_leave_applications` table:
///   id, student_id, student_name, student_email, section
///   (sub-junior|junior|senior), application_date, from_date,
///   description, status (pending|approved|rejected), admin_comment,
///   approved_by, approved_at, sent_to_teacher, sent_to_teacher_at,
///   teacher_id, created_at, updated_at
///
/// Flow: student submits (pending) → Admin approves/rejects with an
/// optional comment → Admin may Send to Teacher (approved only) →
/// the section's teacher sees it. Attendance is never touched.
class LeaveService {
  static const table = 'student_leave_applications';

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  static const sectionSubJunior = 'sub-junior';
  static const sectionJunior = 'junior';
  static const sectionSenior = 'senior';

  static String normalizeSection(String? section) {
    final s = (section ?? '').trim().toLowerCase();
    if (s == 'sub junior' || s == 'sub-junior' || s == 'subjunior') {
      return sectionSubJunior;
    }
    if (s == 'junior') return sectionJunior;
    if (s == 'senior') return sectionSenior;
    return s;
  }

  static String prettySection(String? section) {
    final s = normalizeSection(section);
    if (s == sectionSubJunior) return 'Sub Junior';
    if (s.isEmpty) return '—';
    return s[0].toUpperCase() + s.substring(1);
  }

  static String prettyStatus(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case statusApproved:
        return 'Approved';
      case statusRejected:
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  /// `2026-09-08` for storage.
  static String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String todayStr() {
    final now = DateTime.now();
    return dateStr(DateTime(now.year, now.month, now.day));
  }

  static const _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  /// `September 8, 2026` for display.
  static String prettyDate(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return '—';
    try {
      final d = DateTime.parse(src).toLocal();
      return '${_fullMonths[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return src.split('T').first;
    }
  }

  static String norm(String? v) => (v ?? '').trim().toLowerCase();
}
