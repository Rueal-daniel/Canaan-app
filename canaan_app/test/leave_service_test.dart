import 'package:flutter_test/flutter_test.dart';

import 'package:canaan_app/services/leave_service.dart';

void main() {
  test('sections and statuses', () {
    expect(LeaveService.normalizeSection('Sub Junior'), 'sub-junior');
    expect(LeaveService.prettySection('junior'), 'Junior');
    expect(LeaveService.prettyStatus('approved'), 'Approved');
    expect(LeaveService.prettyStatus('rejected'), 'Rejected');
    expect(LeaveService.prettyStatus('pending'), 'Pending');
  });

  test('dates', () {
    expect(LeaveService.dateStr(DateTime(2026, 9, 8)), '2026-09-08');
    expect(LeaveService.prettyDate('2026-09-08'), 'September 8, 2026');
    expect(LeaveService.prettyDate(''), '—');
  });
}
