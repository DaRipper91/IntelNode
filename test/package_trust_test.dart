import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

// S5: nothing in lib/ may switch off package signature checks or auto-trust a
// repository key. openSUSE gets its signing key from the rootfs (rpm --import
// plus a fingerprint check at first boot), not from a zypper flag.
void main() {
  final bypass = RegExp(r'gpg-auto-import-keys|nogpgcheck|no-gpg-checks');
  // Exact lines allowed to match, by file. Empty on purpose: nothing is allowed.
  const allowed = <String, List<String>>{};

  test('no signature-check bypass remains in lib/ outside the allow-list', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final name = f.uri.pathSegments.last;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!bypass.hasMatch(lines[i])) continue;
        if ((allowed[name] ?? const []).contains(lines[i].trim())) continue;
        offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('no zypper key auto-import remains in the distro manifest', () {
    final text = File('lib/distros.dart').readAsStringSync();
    expect('--gpg-auto-import-keys'.allMatches(text).length, 0);
  });

  group('third-party .deb installs are hash-pinned', () {
    final lists = <String>[
      'pacman',
      'apt',
      'dnf',
      'zypper',
    ];

    test('every command that unpacks a .deb verifies a SHA-256 first', () {
      var checked = 0;
      for (final pm in lists) {
        for (final c in D.getCommandsForPackageManager(pm)) {
          final cmd = c['command'] as String;
          if (!cmd.contains('.deb')) continue;
          checked++;
          expect(cmd, contains('sha256sum -c -'), reason: '$pm ${c['name']}');
          expect(
            cmd.indexOf('sha256sum -c -'),
            lessThan(cmd.contains('bsdtar -xOf')
                ? cmd.indexOf('bsdtar -xOf')
                : cmd.indexOf('apt-get install')),
            reason: '$pm ${c['name']}: verify before unpack/install',
          );
          expect(RegExp(r"echo '[0-9a-f]{64}  /tmp/").hasMatch(cmd), isTrue,
              reason: '$pm ${c['name']}: needs a 64-hex pin');
        }
      }
      expect(checked, greaterThan(0));
    });

    test('install commands built from scraped or redirected URLs are gone', () {
      for (final pm in lists) {
        for (final c in D.getCommandsForPackageManager(pm)) {
          final cmd = c['command'] as String;
          expect(cmd, isNot(contains('linuxConfig.js')), reason: '$pm ${c['name']}');
          expect(cmd, isNot(contains('redirect_url')), reason: '$pm ${c['name']}');
          expect(cmd, isNot(contains('--nogpgcheck')), reason: '$pm ${c['name']}');
          expect(cmd, isNot(contains('--no-gpg-checks')), reason: '$pm ${c['name']}');
        }
      }
    });

    // Runs the real generated shell with stub wget/bsdtar/sudo so the hash gate
    // itself is exercised: a wrong hash must stop before anything is unpacked.
    group('shell behaviour', () {
      late Directory dir;
      late String wpsCommand;
      final marker = 'unpacked';

      setUp(() {
        dir = Directory.systemTemp.createTempSync('debgate_');
        void stub(String name, String body) {
          File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
          Process.runSync('chmod', ['+x', '${dir.path}/$name']);
        }

        // wget -O <dest> : writes a fixed payload instead of downloading.
        stub('wget', r'while [ $# -gt 0 ]; do [ "$1" = "-O" ] && { printf payload > "$2"; }; shift; done');
        stub('bsdtar', 'case "\$1" in -xOf) echo data;; -xf) cat >/dev/null; touch "${dir.path}/$marker";; esac');
        stub('sudo', r'exec "$@"');
        wpsCommand = D
            .getCommandsForPackageManager('pacman')
            .firstWhere((c) => c['name'] == '安装WPS')['command'] as String;
      });
      tearDown(() => dir.deleteSync(recursive: true));

      ProcessResult run(String cmd) => Process.runSync(
            'sh',
            ['-c', cmd],
            environment: {'PATH': '${dir.path}:${Platform.environment['PATH']}'},
          );

      test('a hash mismatch stops before unpacking and removes the download', () {
        final r = run(wpsCommand);
        expect(File('${dir.path}/$marker').existsSync(), isFalse, reason: '${r.stderr}');
        expect(File('/tmp/wps.deb').existsSync(), isFalse);
      });

      test('the matching hash lets the unpack run', () {
        final payloadHash = Process.runSync(
          'sh',
          ['-c', 'printf payload | sha256sum'],
        ).stdout.toString().split(' ').first;
        final pin = RegExp(r"echo '([0-9a-f]{64})  ").firstMatch(wpsCommand)!.group(1)!;
        final r = run(wpsCommand.replaceAll(pin, payloadHash));
        expect(File('${dir.path}/$marker').existsSync(), isTrue, reason: '${r.stderr}');
        expect(File('/tmp/wps.deb').existsSync(), isFalse);
      });
    });
  });
}
