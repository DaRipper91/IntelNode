import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

// F12: to_vault must not hardcode device metadata, and the app must copy it
// (and the other guest-run scripts) with the executable bit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('to_vault device metadata', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('to_vault_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ProcessResult runToVault({String? getpropStub, Map<String, String> env = const {}}) {
      final bin = Directory('${tmp.path}/bin')..createSync();
      if (getpropStub != null) {
        final f = File('${bin.path}/getprop')..writeAsStringSync(getpropStub);
        Process.runSync('chmod', ['755', f.path]);
      }
      // A minimal PATH (stub dir + standard tools) so a real getprop never leaks in.
      return Process.runSync(
        'bash',
        ['assets/scripts/to_vault', 'Topic'],
        environment: {
          'HOME': tmp.path,
          'PATH': '${bin.path}:/usr/bin:/bin',
          ...env,
        },
        includeParentEnvironment: false,
        stdoutEncoding: systemEncoding,
      );
    }

    String note() => Directory('${tmp.path}/Vault/Raw_Intel')
        .listSync()
        .whereType<File>()
        .single
        .readAsStringSync();

    test('the script no longer carries a hardcoded device or OS', () {
      final src = File('assets/scripts/to_vault').readAsStringSync();
      expect(src, isNot(contains('Pixel_10_Pro')));
      expect(src, isNot(contains('Cinnamon_Bun')));
    });

    test('reads device and OS from getprop when available', () {
      final r = runToVault(
        getpropStub: '#!/bin/sh\ncase "\$1" in ro.product.model) echo "Test Phone 9";; '
            'ro.build.version.release) echo 99;; esac\n',
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final n = note();
      expect(n, contains('device: Test_Phone_9'));
      expect(n, contains('os: Android_99'));
    });

    test('falls back to unknown when getprop is not reachable', () {
      final r = runToVault();
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final n = note();
      expect(n, contains('device: unknown'));
      expect(n, contains('os: unknown'));
    });

    test('INTELNODE_DEVICE / INTELNODE_OS override', () {
      runToVault(env: {'INTELNODE_DEVICE': 'bench', 'INTELNODE_OS': 'lab'});
      final n = note();
      expect(n, contains('device: bench'));
      expect(n, contains('os: lab'));
    });
  });

  group('executable bit on copied assets', () {
    test('copyAsset(executable: true) sets the exec bits, default does not', () async {
      final tmp = Directory.systemTemp.createTempSync('copy_asset_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      await Util.copyAsset('assets/scripts/to_vault', '${tmp.path}/exec', executable: true);
      await Util.copyAsset('assets/scripts/to_vault', '${tmp.path}/plain');
      // mode & 0o111 via stat: FileStat.mode is the full st_mode.
      expect(File('${tmp.path}/exec').statSync().mode & 0x49, 0x49);
      expect(File('${tmp.path}/plain').statSync().mode & 0x49, 0);
    });

    test('the guest-run scripts are copied executable', () {
      final src = File('lib/workflow.dart').readAsStringSync();
      for (final name in ['start-arch.sh', 'start-desktop', 'to_vault']) {
        final i = src.indexOf('"assets/scripts/$name"');
        expect(i, greaterThan(0), reason: name);
        expect(src.substring(i, i + 160), contains('executable: true'), reason: name);
      }
      // belt and braces in the bootstrap script, next to the other chmods
      expect(src, contains('chmod -R +x tiny/extra/*'));
    });
  });
}
