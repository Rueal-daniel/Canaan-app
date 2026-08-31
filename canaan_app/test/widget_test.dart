import 'package:flutter_test/flutter_test.dart';

import 'package:canaan_app/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CanaanApp());

    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
