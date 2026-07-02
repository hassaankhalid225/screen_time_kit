// Basic widget test for the example app.
//
// The demo drives real native channels, so we don't assert on platform data
// here — we just verify the app builds and shows its key sections.

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_time_kit_example/main.dart';

void main() {
  testWidgets('demo app builds and renders its sections',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ScreenTimeDemoApp());
    await tester.pump();

    expect(find.text('screen_time_kit'), findsOneWidget);
    expect(find.textContaining('Permission'), findsWidgets);
  });
}
