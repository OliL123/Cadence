import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/main.dart';

void main() {
  testWidgets('Cadence app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const CadenceApp());
    expect(find.text('節奏'), findsOneWidget);
    // Network calls fail instantly in tests, so the weather/holiday loaders
    // sit in their short retry delays (services.dart). Unmount the app and let
    // those run out, or the test ends with timers still pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
