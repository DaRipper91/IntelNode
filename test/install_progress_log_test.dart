import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:da_ripped_tiny_computer/container_setup_page.dart';

void main() {
  Widget host(ValueNotifier<List<String>> lines) => MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 200, child: InstallProgressLog(lines: lines)),
        ),
      );

  ScrollPosition positionOf(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  double offsetOf(WidgetTester tester) => positionOf(tester).pixels;

  double maxOf(WidgetTester tester) => positionOf(tester).maxScrollExtent;

  testWidgets('follows the newest line as progress is appended', (tester) async {
    final lines = ValueNotifier<List<String>>([]);
    await tester.pumpWidget(host(lines));

    for (var i = 0; i < 60; i++) {
      lines.value = [...lines.value, 'line $i'];
      await tester.pump();
    }
    await tester.pump();

    expect(maxOf(tester), greaterThan(0), reason: 'the log must overflow the box');
    expect(offsetOf(tester), maxOf(tester));
    expect(find.text('line 59'), findsOneWidget);
  });

  testWidgets('keeps only the most recent lines so a long download cannot grow forever', (tester) async {
    final lines = ValueNotifier<List<String>>([]);
    await tester.pumpWidget(host(lines));

    lines.value = [for (var i = 0; i < 2000; i++) 'line $i'];
    await tester.pump();
    await tester.pump();

    expect(find.text('line 0'), findsNothing);
    expect(find.text('line 1999', skipOffstage: false), findsOneWidget);
  });
}
