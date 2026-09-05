import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canaan_app/services/notice_service.dart';
import 'package:canaan_app/widgets/notice_rich_text.dart';

void main() {
  test('audience filtering lists', () {
    expect(NoticeService.visibleAudiencesFor('teacher'),
        ['teacher', 'all']);
    expect(NoticeService.visibleAudiencesFor('student'),
        ['student', 'all']);
    expect(NoticeService.visibleAudiencesFor('admin'),
        ['all', 'teacher', 'student']);
  });

  test('plain text strips formatting', () {
    expect(
        NoticeService.plainTextOf(
            '<p>Hello <b>bold</b> world</p><ul><li>one</li></ul>'),
        contains('Hello bold world'));
    expect(noticeHtmlIsEmpty('<p>   </p>'), isTrue);
    expect(noticeHtmlIsEmpty('<p>hi</p>'), isFalse);
  });

  testWidgets('composer applies bold to selected text', (tester) async {
    String html = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoticeComposer(
          initialHtml: '',
          onChanged: (v) => html = v,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    // Select "world".
    final field =
        tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection =
        const TextSelection(baseOffset: 6, extentOffset: 11);
    await tester.pump();

    // Tap the Bold toolbar button.
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(html, contains('<b>world</b>'));
  });

  testWidgets('composer applies size + color and lists', (tester) async {
    String html = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoticeComposer(
          initialHtml: '',
          onChanged: (v) => html = v,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'line one\nline two');
    await tester.pump();

    // Select all and pick Heading 3 from the size dropdown.
    final field =
        tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection = TextSelection(
        baseOffset: 0, extentOffset: field.controller!.text.length);
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 3').last);
    await tester.pump();
    expect(html, contains('<size v="h3">'));

    // Bullet the first line only.
    field.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pump();
    await tester.tap(find.byTooltip('Bullet list'));
    await tester.pump();
    expect(html, contains('<ul>'));
    expect(html, contains('<li>'));

    // Rendered view shows the content (round-trip through the parser).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NoticeContentView(html)),
    ));
    await tester.pump();
    expect(find.byType(RichText), findsWidgets);
    expect(
        NoticeService.plainTextOf(html),
        allOf(contains('line one'), contains('line two')));
  });

  testWidgets('composer round-trips existing formatted html', (tester) async {
    const initial =
        '<p><b>Bold</b> and <font color="#B91C1C">red</font></p><ol><li>first</li></ol>';
    String html = initial;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoticeComposer(
          initialHtml: initial,
          onChanged: (v) => html = v,
        ),
      ),
    ));
    await tester.pump();

    // Edit field shows the plain content…
    final editField =
        tester.widget<TextField>(find.byType(TextField));
    expect(editField.controller!.text, 'Bold and red\n1. first');
    // …but the saved html keeps the formatting.
    expect(html, contains('<b>Bold</b>'));
    expect(html, contains('<font color="#B91C1C">red</font>'));
    expect(html, contains('<ol>'));
  });
}
