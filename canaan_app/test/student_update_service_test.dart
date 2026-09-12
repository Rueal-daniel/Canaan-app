import 'package:canaan_app/services/student_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combine/split behaviour_detail round-trips', () {
    const did = 'Joined the Bible lesson and memory verse game.';
    const learned = 'Learned John 3:16 and what it means.';
    const behaviour = 'Respectful, cooperative, listened well.';
    final packed = StudentUpdateService.combineDetail(
      didToday: did,
      learned: learned,
      behaviour: behaviour,
    );
    final parts = StudentUpdateService.splitDetail(packed);
    expect(parts.$1, did);
    expect(parts.$2, learned);
    expect(parts.$3, behaviour);
    // Legacy plain text falls back to the behaviour slot.
    final legacy = StudentUpdateService.splitDetail('Just a note.');
    expect(legacy.$3, 'Just a note.');
    expect(StudentUpdateService.splitDetail(''), ('', '', ''));
  });

  test('percentage validation 0–100', () {
    expect(StudentUpdateService.validatePercentage('85'), isNull);
    expect(StudentUpdateService.validatePercentage('0'), isNull);
    expect(StudentUpdateService.validatePercentage('100'), isNull);
    expect(
        StudentUpdateService.validatePercentage(''), isNotNull);
    expect(
        StudentUpdateService.validatePercentage('abc'), isNotNull);
    expect(
        StudentUpdateService.validatePercentage('101'), isNotNull);
    expect(
        StudentUpdateService.validatePercentage('-1'), isNotNull);
  });

  test('stars label + clamping', () {
    expect(StudentUpdateService.starsLabel(4), '⭐⭐⭐⭐☆ (4/5)');
    expect(StudentUpdateService.starsLabel(5), '⭐⭐⭐⭐⭐ (5/5)');
    expect(StudentUpdateService.ratingOf({'saturday_rating': 9}), 5);
    expect(StudentUpdateService.percentageOf({'total_percentage': 250}), 100);
  });

  test('pretty dates include the weekday', () {
    expect(
      StudentUpdateService.prettyDate(
          {'created_at': '2026-09-12T10:00:00Z'}),
      'Saturday, September 12, 2026',
    );
    expect(
      StudentUpdateService.prettyShortDate(
          {'created_at': '2026-09-12T10:00:00Z'}),
      'September 12, 2026',
    );
    expect(
      StudentUpdateService.monthKeyOf(
          {'created_at': '2026-09-12T10:00:00Z'}),
      '2026-09',
    );
  });
}
