import 'package:canaan_app/services/gallery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('section + type normalization', () {
    expect(GalleryService.normalizeSection('Sub Junior'), 'sub-junior');
    expect(GalleryService.normalizeSection('Senior'), 'senior');
    expect(GalleryService.normalizeSection(''), 'all');
    expect(GalleryService.prettySection('junior'), 'Junior');
    expect(GalleryService.normalizeType('Special Program'), 'special_program');
    expect(GalleryService.prettyType('activity'), 'Activity');
  });

  test('student visibility: Senior-only hidden from Junior', () {
    final seniorOnly = {'section': 'senior'};
    expect(
      GalleryService.visibleTo(seniorOnly,
          role: 'student', section: 'junior'),
      isFalse,
    );
    expect(
      GalleryService.visibleTo(seniorOnly,
          role: 'student', section: 'senior'),
      isTrue,
    );
    expect(
      GalleryService.visibleTo({'section': 'all'},
          role: 'student', section: 'sub-junior'),
      isTrue,
    );
    // Teachers see every section; admin sees everything.
    expect(
      GalleryService.visibleTo(seniorOnly, role: 'teacher'),
      isTrue,
    );
    expect(
      GalleryService.visibleTo(seniorOnly, role: 'admin'),
      isTrue,
    );
  });

  test('dates, month keys, photo grouping + cover', () {
    expect(GalleryService.prettyDate({'event_date': '2026-12-25'}),
        'December 25, 2026');
    expect(GalleryService.prettyDate({'event_date': null}), '');
    expect(GalleryService.monthKeyOf({'event_date': '2026-12-25'}),
        '2026-12');
    final byGallery = GalleryService.photosByGallery([
      {'id': 2, 'gallery_id': 7, 'photo_url': 'b', 'display_order': 1},
      {'id': 1, 'gallery_id': 7, 'photo_url': 'a', 'display_order': 0},
      {'id': 3, 'gallery_id': 9, 'photo_url': 'c', 'display_order': 0},
    ]);
    expect(byGallery[7]!.first['photo_url'], 'a');
    expect(GalleryService.photoCountOf(byGallery, 7), 2);
    expect(GalleryService.coverUrlOf(byGallery, 7), 'a');
    expect(GalleryService.coverUrlOf(byGallery, 999), isNull);
  });
}
