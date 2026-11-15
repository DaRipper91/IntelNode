// Dumps the proot boot command exactly as Workflow.launchCurrentContainer builds
// it (default extra mounts, no extra options), for running it by hand on a device:
//   flutter test tool/dump_boot.dart --dart-define=OUT=/path/boot.txt
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  test('dump boot command', () {
    const out = String.fromEnvironment('OUT');
    expect(out, isNotEmpty, reason: 'pass --dart-define=OUT=<file>');
    const extraMount =
        r"--mount=$DATA_DIR/tiny/font:/usr/share/fonts/tiny --mount=$DATA_DIR/tiny/extra/start-arch.sh:/usr/local/bin/start-arch.sh --mount=$DATA_DIR/tiny/extra/start-desktop:/usr/local/bin/start-desktop --mount=$DATA_DIR/tiny/extra/to_vault:/usr/local/bin/to_vault ";
    File(out).writeAsStringSync(Workflow.getBootCommand(extraMount: extraMount));
  });
}
