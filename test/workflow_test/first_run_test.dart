import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Workflow.firstRunScript', () {
    test('wraps the commands and writes the completion marker last', () {
      final script = Workflow.firstRunScript('echo one\necho two');
      expect(script, startsWith('#!/bin/bash\n'));
      expect(script, contains('echo one\necho two'));
      expect(script.trimRight(), endsWith('touch "\$HOME/.intelnode-first-run"'));
    });

    test('is valid bash and creates the marker when run', () {
      final home = Directory.systemTemp.createTempSync('fr_');
      addTearDown(() => home.deleteSync(recursive: true));
      final script = File('${home.path}/first-run.sh')
        ..writeAsStringSync(Workflow.firstRunScript('true'));
      final r = Process.runSync('bash', [script.path],
          environment: {'HOME': home.path});
      expect(r.exitCode, 0);
      expect(File('${home.path}/.intelnode-first-run').existsSync(), isTrue);
    });
  });

  test('start-arch.sh runs first-run.sh once, before the desktop', () {
    final sh = File('assets/scripts/start-arch.sh').readAsStringSync();
    final firstRun = sh.indexOf('first-run.sh');
    expect(firstRun, greaterThan(0));
    expect(sh, contains('.intelnode-first-run'));
    expect(firstRun, lessThan(sh.indexOf('start-desktop')));
  });
}
