import 'package:canaan_app/services/event_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('section normalization + multi-section parsing', () {
    expect(EventService.normalizeSection('Sub Junior'), 'sub-junior');
    expect(EventService.normalizeSection('Junior'), 'junior');
    expect(
      EventService.sectionsOf({'section': 'junior,senior'}),
      ['junior', 'senior'],
    );
    expect(
      EventService.sectionsOf({'section': 'all'}),
      [EventService.sectionAll],
    );
    expect(
      EventService.prettySections({'section': 'junior,senior'}),
      'Junior + Senior',
    );
    expect(
      EventService.sectionSlugForWrite(['senior', 'junior']),
      'junior,senior',
    );
  });

  test('student visibility: Junior+Senior quiz hidden from Sub Junior', () {
    final quiz = {
      'status': 'published',
      'audience': 'everyone',
      'section': 'junior,senior',
    };
    expect(
      EventService.visibleTo(quiz, role: 'student', section: 'junior'),
      isTrue,
    );
    expect(
      EventService.visibleTo(quiz, role: 'student', section: 'sub-junior'),
      isFalse,
    );
    // Teachers-only hidden from students; drafts hidden from everyone.
    expect(
      EventService.visibleTo(
        {'status': 'published', 'audience': 'teachers', 'section': 'all'},
        role: 'student',
        section: 'junior',
      ),
      isFalse,
    );
    expect(
      EventService.visibleTo(
        {'status': 'draft', 'audience': 'everyone', 'section': 'all'},
        role: 'student',
        section: 'junior',
      ),
      isFalse,
    );
    // Teacher sees published events; admin sees everything incl. drafts.
    expect(
      EventService.visibleTo(
        {'status': 'published', 'audience': 'students', 'section': 'junior'},
        role: 'teacher',
      ),
      isTrue,
    );
    expect(
      EventService.visibleTo(
        {'status': 'draft', 'audience': 'everyone', 'section': 'all'},
        role: 'admin',
      ),
      isTrue,
    );
  });

  test('dates: keys, pretty labels, grouping, upcoming', () {
    final e = {'event_date': '2026-09-19'};
    expect(EventService.dateKeyOf(e), '2026-09-19');
    expect(EventService.prettyDate(e), 'September 19, 2026');
    expect(EventService.monthLabel(2026, 9), 'September 2026');
    expect(EventService.daysInMonth(2026, 9), 30);
    expect(EventService.firstWeekday(2026, 9), 2); // Sept 1 2026 = Tuesday

    final grouped = EventService.groupByDate([
      {'event_date': '2026-09-19', 'start_time': '10:00 AM', 'title': 'B'},
      {'event_date': '2026-09-19', 'start_time': '09:00 AM', 'title': 'A'},
      {'event_date': '2026-09-05', 'start_time': '', 'title': 'C'},
    ]);
    expect(grouped['2026-09-19']!.first['title'], 'A');
    final up = EventService.upcoming(
      [
        {'event_date': '2020-01-01', 'start_time': '', 'title': 'old'},
        {'event_date': '2026-09-19', 'start_time': '', 'title': 'new'},
      ],
      from: DateTime(2026, 9, 1),
    );
    expect(up.length, 1);
    expect(up.first['title'], 'new');
  });
}
