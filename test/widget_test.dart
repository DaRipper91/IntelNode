import 'package:flutter_test/flutter_test.dart';

import 'package:da_ripped_tiny_computer/main.dart';

void main() {
  testWidgets('App smoke test - MyApp widget builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    // Verify the app builds without crashing
    expect(find.byType(MyApp), findsOneWidget);
  });
}
