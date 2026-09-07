import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/main.dart';

void main() {
  testWidgets('Cadence app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const CadenceApp());
    expect(find.text('節奏'), findsOneWidget);
  });
}
