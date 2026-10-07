// Every Career tab must lay out at phone width without overflowing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/career_page.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  testWidgets('phone width: all tabs and the form fit', (tester) async {
    tester.view.physicalSize = const Size(375, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.applications = [];
    store.trackEvents = [];
    store.loadCareerStarter();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
    for (final tab in ['Applications 5', 'Events 7', 'Overview', 'Goals & metrics', 'Schedule']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Applications 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('New application'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
