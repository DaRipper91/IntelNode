import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:da_ripped_tiny_computer/pty_shell.dart';

void main() {
  group('pty shell environment', () {
    test('points ENV at /dev/null so a patched mkshrc is never sourced', () {
      expect(ptyShellEnvironment['ENV'], '/dev/null');
    });

    test('no source file starts a bare sh PTY behind startShell()', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('pty_shell.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final window = lines.skip(i).take(2).join(' ');
          if (lines[i].contains('Pty.start(') &&
              window.contains('/system/bin/sh')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
