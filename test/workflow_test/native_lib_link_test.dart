import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Util.nativeLibLinkCommand', () {
    test('uses -n so an existing applib symlink is replaced, not followed', () {
      final cmd = Util.nativeLibLinkCommand('/data/app/x/lib/arm64', '/data/files');
      expect(cmd, contains('ln -sfn '));
      expect(cmd, endsWith("'/data/files'/applib"));
    });

    test('quotes paths containing spaces and single quotes', () {
      final cmd = Util.nativeLibLinkCommand("/a b/it's/lib", '/d');
      expect(cmd, contains("'/a b/it'\\''s/lib'"));
    });

    test('is idempotent against a read-only target dir (relaunch regression)',
        () async {
      if (!Platform.isLinux) return;
      final tmp = Directory.systemTemp.createTempSync('applib_');
      addTearDown(() {
        Process.runSync('chmod', ['-R', 'u+w', tmp.path]);
        tmp.deleteSync(recursive: true);
      });
      final lib = Directory('${tmp.path}/lib_arm64')..createSync();
      final files = Directory('${tmp.path}/files')..createSync();
      Process.runSync('chmod', ['a-w', lib.path]);

      // The app runs /system/bin/ln; use the host ln for the same semantics.
      String hostCmd() => Util.nativeLibLinkCommand(lib.path, files.path)
          .replaceFirst('/system/bin/ln', 'ln');
      final first = Process.runSync('sh', ['-c', hostCmd()]);
      final second = Process.runSync('sh', ['-c', hostCmd()]);

      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(second.exitCode, 0, reason: '${second.stderr}');
    });
  });
}
