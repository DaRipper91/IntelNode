import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:da_ripped_tiny_computer/container_delete_dialog.dart';
import 'package:da_ripped_tiny_computer/container_manager.dart';
import 'package:da_ripped_tiny_computer/l10n/app_localizations.dart';

void main() {
  final entries = [
    const ContainerEntry(
      index: 0,
      name: 'Arch Linux',
      blockedReason: ContainerManager.runningReason,
    ),
    const ContainerEntry(index: 1, name: 'Fedora'),
    const ContainerEntry(index: 2, name: 'Debian'),
  ];

  Future<void> open(WidgetTester tester, List<ContainerEntry> list) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<Set<int>>(
              context: context,
              builder: (_) => PickContainersDialog(entries: list),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton deleteButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));

  testWidgets('lists every container and greys out the one in use with its reason', (tester) async {
    await open(tester, entries);
    expect(find.text('Arch Linux'), findsOneWidget);
    expect(find.text('Fedora'), findsOneWidget);
    expect(find.text(ContainerManager.runningReason), findsOneWidget);

    final arch = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Arch Linux'));
    expect(arch.onChanged, isNull);
  });

  testWidgets('Delete stays disabled until something is ticked, and returns the picks', (tester) async {
    Set<int>? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showDialog<Set<int>>(
              context: context,
              builder: (_) => PickContainersDialog(entries: entries),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(deleteButton(tester).onPressed, isNull);

    await tester.tap(find.text('Fedora'));
    await tester.tap(find.text('Debian'));
    await tester.pump();
    expect(deleteButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Debian')); // untick again
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(picked, {1});
  });

  testWidgets('says so when there is nothing to delete', (tester) async {
    await open(tester, const []);
    expect(find.text('There are no containers to delete.'), findsOneWidget);
  });
}
