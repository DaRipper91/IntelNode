import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Util.rootfsExtractCommand', () {
    test('decompresses with busybox unxz, never tar -J (no xz applet shipped)', () {
      final cmd = Util.rootfsExtractCommand();
      expect(cmd, contains('busybox unxz'));
      expect(cmd, isNot(contains(' -J')));
      expect(cmd, isNot(contains('xz -d')));
    });

    test('extracts into the staging dir and preserves permissions', () {
      final cmd = Util.rootfsExtractCommand(stagingDir: 'containers/0_staging');
      expect(cmd, contains('-C containers/0_staging'));
      expect(cmd, contains('--preserve-permissions'));
      expect(cmd, startsWith('cat xa* | '));
    });

    test('round-trips an xz tarball split into chunks', () {
      if (!Platform.isLinux) return;
      final busybox = Process.runSync('sh', ['-c', 'command -v busybox']);
      if (busybox.exitCode != 0) return; // host without busybox: nothing to run
      final xz = Process.runSync('sh', ['-c', 'busybox unxz --help 2>&1 | head -1']);
      if (!'${xz.stdout}${xz.stderr}'.toLowerCase().contains('unxz')) return;

      final tmp = Directory.systemTemp.createTempSync('rootfs_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final src = Directory('${tmp.path}/src/etc')..createSync(recursive: true);
      File('${src.path}/os-release').writeAsStringSync('ID=arch\n');
      ProcessResult run(String c) =>
          Process.runSync('sh', ['-c', c], workingDirectory: tmp.path);

      expect(run('tar -C src -cf - . | xz -c > a.tar.xz && split -b 200 a.tar.xz xa').exitCode, 0);
      expect(run('mkdir -p containers/0_staging').exitCode, 0);
      final cmd = Util.rootfsExtractCommand()
          .replaceAll(r'$DATA_DIR/bin/busybox', 'busybox')
          .replaceAll(r'$DATA_DIR/bin/tar', 'tar');
      final r = run(cmd);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('${tmp.path}/containers/0_staging/etc/os-release').readAsStringSync(), 'ID=arch\n');
    });
  });
}
