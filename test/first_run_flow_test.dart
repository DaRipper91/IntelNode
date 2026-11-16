import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/desktop_picker.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/setup_session.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  checksumTests();
  markerToleranceTests();
  busyboxScriptTests();
  extractScriptTests();
  rmrfTests();
  prootRunTests();
  group('desktop manifest kinds', () {
    test('has both desktop environments and window managers', () {
      final kinds = DesktopEnvironments.all.map((d) => d.kind).toSet();
      expect(kinds, containsAll(DesktopKind.values));
    });

    test('i3 and the new stable WMs are window managers', () {
      for (final id in ['i3', 'openbox', 'fluxbox', 'icewm']) {
        expect(DesktopEnvironments.all.firstWhere((d) => d.id == id).kind,
            DesktopKind.windowManager);
      }
    });

    test('no pacman package list uses the Debian-only dbus-x11', () {
      final arch = Distros.byId('archlinux');
      for (final d in DesktopEnvironments.all) {
        expect(d.packagesFor(arch), isNot(contains('dbus-x11')), reason: d.id);
      }
    });
  });

  group('DesktopPickerBody', () {
    testWidgets('shows labelled sections and returns the tapped entry', (tester) async {
      DesktopEnvironmentSpec? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DesktopPickerBody(onSelected: (d) => picked = d),
        ),
      ));
      expect(find.text('Desktop Environments'), findsOneWidget);
      expect(find.text('Window Managers'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-xfce4')));
      expect(picked?.id, 'xfce4');
    });

    testWidgets('experimental entries are not selectable', (tester) async {
      DesktopEnvironmentSpec? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DesktopPickerBody(onSelected: (d) => picked = d),
        ),
      ));
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('desktop-niri')), 200,
          scrollable: find.byType(Scrollable));
      await tester.tap(find.byKey(const ValueKey('desktop-niri')),
          warnIfMissed: false);
      expect(picked, isNull);
    });
  });

  group('install scripts', () {
    test('session files script writes the exec and session marker', () {
      final i3 = DesktopEnvironments.all.firstWhere((d) => d.id == 'i3');
      final script = ContainerInstaller.sessionFilesScript(i3);
      expect(script, contains('.intelnode-session'));
      expect(script, contains('exec ${i3.xinitrcExec}'));
      expect(script.trimLeft(), startsWith('set -e'));
    });

    test('arch first boot fixes pacman for proot and uses the ARM keyring', () {
      final script = Distros.byId('archlinux').firstBootScript('tiny');
      expect(script, contains('pacman-key --populate archlinuxarm'));
      expect(script, contains('DisableSandbox'));
      expect(script, contains('rm -f /etc/resolv.conf'));
      expect(script, contains('-u 1000'));
    });
  });

  group('SetupSession.parseExitMarker', () {
    test('reads the expanded exit code', () {
      expect(SetupSession.parseExitMarker('done\r\n@@INTELNODE-2@@ 0\r\n', '@@INTELNODE-2@@'), 0);
      expect(SetupSession.parseExitMarker('@@INTELNODE-2@@ 127', '@@INTELNODE-2@@'), 127);
    });

    test('ignores the echoed command and other runs', () {
      expect(SetupSession.parseExitMarker('echo "@@INTELNODE-2@@ \$?"', '@@INTELNODE-2@@'), isNull);
      expect(SetupSession.parseExitMarker('@@INTELNODE-1@@ 0', '@@INTELNODE-2@@'), isNull);
    });
  });
}

void checksumTests() {
  group('ContainerInstaller.checksumFor', () {
    const ubuntu = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa *other.tar.xz\n'
        'b68ef0444ca56ce4f00ae7e8ccfb0c553ffbc92e4a1b14ed7dd8aa18c6d68652 *root.tar.xz\n';
    test('finds the entry for a file in a SHA256SUMS listing', () {
      expect(ContainerInstaller.checksumFor(ubuntu, 'root.tar.xz'),
          'b68ef0444ca56ce4f00ae7e8ccfb0c553ffbc92e4a1b14ed7dd8aa18c6d68652');
    });
    test('accepts a single-entry md5 file', () {
      expect(ContainerInstaller.checksumFor('0123456789abcdef0123456789abcdef  ArchLinuxARM.tar.gz\n', 'ArchLinuxARM.tar.gz'),
          '0123456789abcdef0123456789abcdef');
    });
    test('returns null when the file is not listed', () {
      expect(ContainerInstaller.checksumFor(ubuntu, 'missing.tar.xz'), isNull);
    });
  });
}

void markerToleranceTests() {
  test('marker tolerates extra whitespace between token and code', () {
    expect(SetupSession.parseExitMarker('@@INTELNODE-3@@   0', '@@INTELNODE-3@@'), 0);
    expect(SetupSession.parseExitMarker('@@INTELNODE-3@@\t5', '@@INTELNODE-3@@'), 5);
  });
}

void busyboxScriptTests() {
  group('busybox scripts', () {
    // G.dataPath is a late field that can be assigned once per process.
    late Directory dir;
    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('bb_');
      G.dataPath = dir.path;
    });
    tearDownAll(() => dir.deleteSync(recursive: true));
    setUp(() {
      for (final e in dir.listSync()) {
        e.deleteSync(recursive: true);
      }
      Directory('${dir.path}/bin').createSync();
    });

    // Fake busybox that, like the real dynamic one, refuses to start without
    // LD_LIBRARY_PATH pointing at $DATA_DIR/lib.
    void fakeBusybox() {
      File('${dir.path}/bin/busybox').writeAsStringSync(
        '#!/bin/sh\n[ "\$LD_LIBRARY_PATH" = "${dir.path}/lib" ] || '
        '{ echo "CANNOT LINK EXECUTABLE" >&2; exit 1; }\n"\$@"\n',
      );
      Process.runSync('chmod', ['+x', '${dir.path}/bin/busybox']);
    }

    int run(String script) => Process.runSync('sh', ['-c', script]).exitCode;

    test('checksum script exports LD_LIBRARY_PATH so busybox can start', () {
      fakeBusybox();
      final f = File('${dir.path}/t.tar')..writeAsStringSync('hello');
      final sum = Process.runSync('md5sum', [f.path]).stdout.toString().split(' ').first;
      expect(run(ContainerInstaller.checksumScript(sum, f.path, 'md5sum')), 0);
    });

    test('mismatch is exit 3, a broken tool is exit 2 (download kept)', () {
      final f = File('${dir.path}/t.tar')..writeAsStringSync('hello');
      File('${dir.path}/bin/busybox').writeAsStringSync('#!/bin/sh\nexit 1\n');
      Process.runSync('chmod', ['+x', '${dir.path}/bin/busybox']);
      expect(run(ContainerInstaller.checksumScript('0' * 32, f.path, 'md5sum')), 2);
      fakeBusybox();
      expect(run(ContainerInstaller.checksumScript('0' * 32, f.path, 'md5sum')), 3);
    });

    test('finalize script can run busybox and swaps staging into place', () {
      fakeBusybox();
      Directory('${dir.path}/containers/0_staging').createSync(recursive: true);
      File('${dir.path}/containers/0_staging/marker').writeAsStringSync('x');
      final tar = File('${dir.path}/t.tar')..writeAsStringSync('x');
      expect(
        run(ContainerInstaller.finalizeScript(
          '${dir.path}/containers/0_staging',
          '${dir.path}/containers/0',
          tar.path,
        )),
        0,
      );
      expect(File('${dir.path}/containers/0/marker').existsSync(), isTrue);
      expect(tar.existsSync(), isFalse);
    });
  });
}

void extractScriptTests() {
  group('extractScript', () {
    // The 0555-directory failure only reproduces under proot on the phone (verified
    // there with the real Arch tarball: without the flag 8 files and Permission
    // denied, with it 130 files); host GNU tar extracts fine either way.
    test('passes --delay-directory-restore', () {
      final script = ContainerInstaller.extractScript('/s', '/t.tar', 'z');
      expect(script, contains('--delay-directory-restore'));
    });

    test('script runs end to end against a fake proot and extracts read-only dirs', () {
      final work = Directory.systemTemp.createTempSync('ex_');
      addTearDown(() {
        Process.runSync('chmod', ['-R', 'u+rwX', work.path]);
        work.deleteSync(recursive: true);
      });
      final src = Directory('${work.path}/src/etc/cadir')..createSync(recursive: true);
      File('${src.path}/a.pem').writeAsStringSync('x');
      Link('${src.path}/hash.0').createSync('a.pem');
      Process.runSync('chmod', ['555', src.path]); // read-only, like Arch's cadir
      final tar = '${work.path}/rootfs.tar.gz';
      expect(Process.runSync('tar', ['-C', '${work.path}/src', '-czf', tar, '.']).exitCode, 0);
      Process.runSync('chmod', ['-R', 'u+rwX', '${work.path}/src']);

      // Fake proot (drops --link2symlink) and the host tar, in the layout the script expects.
      Directory('${work.path}/bin').createSync();
      File('${work.path}/bin/proot').writeAsStringSync('#!/bin/sh\nshift\nexec "\$@"\n');
      Process.runSync('chmod', ['+x', '${work.path}/bin/proot']);
      Link('${work.path}/bin/tar').createSync(Process.runSync('which', ['tar']).stdout.toString().trim());
      final staging = '${work.path}/staging';
      final script = ContainerInstaller.extractScript(staging, tar, 'z')
          .replaceAll(RegExp(r'export DATA_DIR=.*'), 'export DATA_DIR=${work.path}');
      final r = Process.runSync('sh', ['-c', script]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('$staging/etc/cadir/a.pem').existsSync(), isTrue);
      expect(Link('$staging/etc/cadir/hash.0').existsSync(), isTrue);
    });
  });
}

void rmrfTests() {
  test('rmrf removes a tree containing read-only directories as a normal user', () {
    final work = Directory.systemTemp.createTempSync('rm_');
    addTearDown(() {
      Process.runSync('chmod', ['-R', 'u+rwX', work.path]);
      if (work.existsSync()) work.deleteSync(recursive: true);
    });
    final ro = Directory('${work.path}/t/etc/cadir')..createSync(recursive: true);
    File('${ro.path}/a.pem').writeAsStringSync('x');
    Process.runSync('chmod', ['555', ro.path]);
    expect(Process.runSync('sh', ['-c', ContainerInstaller.rmrf('${work.path}/t')]).exitCode, 0);
    expect(Directory('${work.path}/t').existsSync(), isFalse);
  });
}

void prootRunTests() {
  test('every proot script kills gpg-agent/dirmngr on exit so proot can return', () {
    final script = ContainerInstaller.prootRun(rootfs: '/r', script: 'echo hi');
    expect(script, contains('pkill -x gpg-agent'));
    expect(script, contains('pkill -x dirmngr'));
    expect(script, contains("trap "));
    expect(script, contains('set +e;'), reason: 'set -e would otherwise leak into the trap and change the exit status');
  });

  test('user setup deletes the old uid-1000 user without relying on userdel -r', () {
    final script = Distros.byId('archlinux').firstBootScript('tiny');
    expect(script, isNot(contains('userdel -r "')));
    expect(script, contains('getent passwd 1000 >/dev/null'));
    expect(script, contains('groupadd -g 1000 tiny'));
    expect(script, contains('useradd -m -s /bin/bash -u 1000 -g 1000'));
  });
}
