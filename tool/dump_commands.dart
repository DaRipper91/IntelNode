// Dumps the quick-command lists the app ships, as JSON, so shell harnesses
// (extra/test-arch-commands.sh) can execute the exact strings users will run.
//
// Run through flutter_test because workflow.dart imports Flutter libraries:
//   flutter test tool/dump_commands.dart --dart-define=OUT=/tmp/commands.json
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  test('dump quick commands', () {
    const out = String.fromEnvironment('OUT');
    expect(out, isNotEmpty, reason: 'pass --dart-define=OUT=<file>');
    File(out).writeAsStringSync(
      jsonEncode({
        'pacman': D.getCommandsForPackageManager('pacman'),
        'pacman_en': D.getCommandsForPackageManager('pacman', english: true),
      }),
    );
  });
}
