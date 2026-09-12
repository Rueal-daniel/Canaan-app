import 'package:canaan_app/services/prayer_request_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('role normalization + pretty labels', () {
    expect(PrayerRequestService.normalizeRole('Admin'), 'admin');
    expect(PrayerRequestService.normalizeRole('TEACHER'), 'teacher');
    expect(PrayerRequestService.normalizeRole(''), 'student');
    expect(PrayerRequestService.prettyRole('admin'), 'Admin');
    expect(PrayerRequestService.prettyRole('student'), 'Student');
    expect(PrayerRequestService.isAdmin('admin'), isTrue);
    expect(PrayerRequestService.isAdmin('teacher'), isFalse);
  });

  test('delete rules: owner-own + admin-any, never anonymous', () {
    final mine = {'id': 1, 'user_id': 'u-teacher-1'};
    final others = {'id': 2, 'user_id': 'u-student-9'};
    expect(
      PrayerRequestService.canDeleteRequest(mine,
          role: 'teacher', userId: 'u-teacher-1'),
      isTrue,
    );
    expect(
      PrayerRequestService.canDeleteRequest(others,
          role: 'teacher', userId: 'u-teacher-1'),
      isFalse,
    );
    expect(
      PrayerRequestService.canDeleteRequest(others,
          role: 'admin', userId: 'u-admin-1'),
      isTrue,
    );
    // Empty identity can never owner-delete.
    expect(
      PrayerRequestService.canDeleteRequest(mine,
          role: 'teacher', userId: ''),
      isFalse,
    );
  });

  test('sorting newest/oldest + search/filter', () {
    final rows = [
      {
        'id': 1,
        'title': 'Exam help',
        'full_name': 'John Doe',
        'role': 'student',
        'created_at': '2026-09-10T10:00:00Z',
      },
      {
        'id': 2,
        'title': 'Family health',
        'full_name': 'Jane Smith',
        'role': 'teacher',
        'created_at': '2026-09-12T10:00:00Z',
      },
    ];
    final newest =
        PrayerRequestService.sorted(rows, newestFirst: true);
    expect(newest.first['id'], 2);
    final oldest =
        PrayerRequestService.sorted(rows, newestFirst: false);
    expect(oldest.first['id'], 1);
    // Search matches title or submitter name.
    expect(
      PrayerRequestService.applySearchFilter(rows, search: 'jane').length,
      1,
    );
    expect(
      PrayerRequestService.applySearchFilter(rows, search: 'exam').length,
      1,
    );
    // Role filter.
    expect(
      PrayerRequestService.applySearchFilter(rows, roleFilter: 'teacher')
          .length,
      1,
    );
    // Combined.
    expect(
      PrayerRequestService.applySearchFilter(rows,
          search: 'exam', roleFilter: 'teacher'),
      isEmpty,
    );
  });

  test('pretty date + notification deep-link parsing', () {
    expect(PrayerRequestService.prettyDate('2026-09-12T00:00:00Z'),
        'September 12, 2026');
    expect(
        PrayerRequestService.focusIdFromRelatedId('prayer:12'), 12);
    expect(
        PrayerRequestService.focusIdFromRelatedId('prayer:12:reply'),
        12);
    expect(
        PrayerRequestService.focusIdFromRelatedId('notice:5'), isNull);
    expect(PrayerRequestService.focusIdFromRelatedId(null), isNull);
  });
}
