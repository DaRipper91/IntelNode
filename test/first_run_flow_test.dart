import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/desktop_picker.dart';
import 'package:da_ripped_tiny_computer/distro_picker.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/setup_session.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  checksumTests();
  markerToleranceTests();
  busyboxScriptTests();
  extractScriptTests();
  sessionCheckTests();
  rmrfTests();
  prootRunTests();
  pickReachableTests();
  group('desktop manifest kinds', () {
    test('has both desktop environments and window managers', () {
      final kinds = DesktopEnvironments.all.map((d) => d.kind).toSet();
      expect(kinds, containsAll(DesktopKind.values));
    });

    test('i3 and the new stable WMs are window managers', () {
      for (final id in ['i3', 'openbox', 'fluxbox', 'icewm', 'awesome', 'bspwm']) {
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
      await tester.tap(find.byKey(const ValueKey('desktop-xfce4')));
      expect(picked?.id, 'xfce4');
      await tester.scrollUntilVisible(find.text('Window Managers'), 200);
      expect(find.text('Window Managers'), findsOneWidget);
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

    testWidgets('formats package manager text dynamically based on distro', (tester) async {
      final fedora = Distros.byId('fedora');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DesktopPickerBody(
            distro: fedora,
            onSelected: (_) {},
          ),
        ),
      ));
      expect(find.textContaining('You can add more later with dnf.'), findsOneWidget);
    });
  });

  group('DistroPickerBody', () {
    testWidgets('shows all distros and returns tapped verified distro', (tester) async {
      DistroSpec? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DistroPickerBody(onSelected: (d) => picked = d),
        ),
      ));
      expect(
        find.text('Select the Linux distribution to download and install for your container.'),
        findsOneWidget,
      );
      // Tap Arch Linux ARM (first verified distro)
      await tester.tap(find.byKey(const ValueKey('distro-archlinux')));
      expect(picked?.id, 'archlinux');

      // Scroll and tap Ubuntu
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('distro-ubuntu')),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.byKey(const ValueKey('distro-ubuntu')));
      expect(picked?.id, 'ubuntu');
    });

    testWidgets('verified distros are enabled and can be tapped', (tester) async {
      DistroSpec? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DistroPickerBody(onSelected: (d) => picked = d),
        ),
      ));
      // Scroll to Kali (now verified after on-device testing)
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('distro-kali')),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.textContaining('Preview, unverified source'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('distro-kali')));
      expect(picked, isNotNull);
      expect(picked!.id, 'kali');
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
      expect(script, contains('1000:1000'));
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
    late String stagingOf;

    // The 0555-directory failure only reproduces under proot on the phone (verified
    // there with the real Arch tarball: without the flag 8 files and Permission
    // denied, with it 130 files); host GNU tar extracts fine either way.
    test('passes --delay-directory-restore', () {
      final script = ContainerInstaller.extractScript('/s', '/t.tar', 'z');
      expect(script, contains('--delay-directory-restore'));
    });

    test('passes --exclude=dev/* to skip character device nodes on unprivileged filesystems', () {
      final script = ContainerInstaller.extractScript('/s', '/t.tar', 'z');
      expect(script, contains("--exclude='dev/*'"));
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

    // proot-distro tarballs (Fedora, Debian, openSUSE, Alpine, Void) put the whole
    // rootfs under one directory such as fedora-aarch64/. Left in place, proot
    // starts at an empty root and first-boot provisioning dies with exit 1.
    ProcessResult extractWrapped(String wrapper, List<String> files) {
      final work = Directory.systemTemp.createTempSync('wrap_');
      addTearDown(() {
        Process.runSync('chmod', ['-R', 'u+rwX', work.path]);
        work.deleteSync(recursive: true);
      });
      for (final f in files) {
        final path = '${work.path}/src/${wrapper.isEmpty ? '' : '$wrapper/'}$f';
        File(path).createSync(recursive: true);
        File(path).writeAsStringSync('x');
      }
      final tar = '${work.path}/rootfs.tar.gz';
      expect(Process.runSync('tar', ['-C', '${work.path}/src', '-czf', tar, '.']).exitCode, 0);
      Directory('${work.path}/bin').createSync();
      File('${work.path}/bin/proot').writeAsStringSync('#!/bin/sh\nshift\nexec "\$@"\n');
      Process.runSync('chmod', ['+x', '${work.path}/bin/proot']);
      Link('${work.path}/bin/tar').createSync(Process.runSync('which', ['tar']).stdout.toString().trim());
      stagingOf = '${work.path}/staging';
      final script = ContainerInstaller.extractScript(stagingOf, tar, 'z')
          .replaceAll(RegExp(r'export DATA_DIR=.*'), 'export DATA_DIR=${work.path}');
      return Process.runSync('sh', ['-c', script]);
    }

    test('hoists a single wrapper directory so the rootfs sits at the root', () {
      final r = extractWrapped('fedora-aarch64', ['usr/bin/sh', 'etc/os-release']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('$stagingOf/usr/bin/sh').existsSync(), isTrue);
      expect(File('$stagingOf/etc/os-release').existsSync(), isTrue);
      expect(Directory('$stagingOf/fedora-aarch64').existsSync(), isFalse);
      expect(Directory('$stagingOf.wrap').existsSync(), isFalse);
    });

    test('a flat rootfs (Arch, Ubuntu cloud image) is left exactly as extracted', () {
      final r = extractWrapped('', ['usr/bin/sh', 'etc/os-release', 'bin/ls']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('$stagingOf/usr/bin/sh').existsSync(), isTrue);
      expect(File('$stagingOf/bin/ls').existsSync(), isTrue);
    });

    test('a flat rootfs whose only entry is a real root directory is not hoisted', () {
      final r = extractWrapped('', ['usr/bin/sh']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('$stagingOf/usr/bin/sh').existsSync(), isTrue);
    });
  });
}

void sessionCheckTests() {
  group('sessionCheckScript', () {
    // --skip-broken can drop packages silently, so a desktop install is only
    // trusted once its session command is really in the rootfs.
    int run(String script) => Process.runSync('sh', ['-c', script]).exitCode;

    test('passes when the session command exists', () {
      expect(run(ContainerInstaller.sessionCheckScript('sh')), 0);
    });

    test('fails when the session command is missing', () {
      expect(run(ContainerInstaller.sessionCheckScript('no-such-session-cmd')), isNot(0));
    });

    test('checks only the command word of an exec line', () {
      expect(ContainerInstaller.sessionCheckScript('dbus-launch --exit-with-session i3'), contains("'dbus-launch'"));
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
    expect(script, contains('-w /'), reason: 'proot must set initial working dir to guest root to avoid chdir warning');
  });

  test('user setup creates uid/gid 1000 directly in /etc files without shadow locking', () {
    final script = Distros.byId('archlinux').firstBootScript('tiny');
    expect(script, isNot(contains('userdel -r "')));
    expect(script, isNot(contains('useradd')));
    expect(script, isNot(contains('groupadd')));
    expect(script, contains('/etc/passwd'));
    expect(script, contains('/etc/group'));
    expect(script, contains("x:1000:1000:"));
  });

  test('void first boot switches from repo-default to Fastly CDN', () {
    final script = Distros.byId('void').firstBootScript('tiny');
    expect(script, contains('repo-fastly.voidlinux.org'));
    expect(script, contains('/etc/xbps.d'));
    expect(script, contains('xbps-install -uy xbps'));
  });
}

void pickReachableTests() {
  group('ContainerInstaller.pickReachable', () {
    http.Client client(Map<String, int?> status) => MockClient((req) async {
          final code = status[req.url.host];
          if (code == null) throw const SocketException('unreachable');
          return http.Response('', code);
        });

    test('skips an unreachable mirror and picks the next that answers', () async {
      final url = await ContainerInstaller.pickReachable(
        ['https://a.test/x', 'https://b.test/x', 'https://c.test/x'],
        client: client({'a.test': null, 'b.test': 200, 'c.test': 200}),
      );
      expect(url, 'https://b.test/x');
    });

    test('skips a mirror that answers with an error', () async {
      final url = await ContainerInstaller.pickReachable(
        ['https://a.test/x', 'https://b.test/x'],
        client: client({'a.test': 503, 'b.test': 200}),
      );
      expect(url, 'https://b.test/x');
    });

    test('returns the first URL when none answer', () async {
      final url = await ContainerInstaller.pickReachable(
        ['https://a.test/x', 'https://b.test/x'],
        client: client({'a.test': null, 'b.test': null}),
      );
      expect(url, 'https://a.test/x');
    });
  });

  test('the Arch source lists fallback mirrors for the same file', () async {
    final c = await Distros.byId('archlinux').rootfs.candidates();
    expect(c.length, greaterThan(1));
    expect(c.toSet().length, c.length);
    expect(c.every((u) => u.endsWith('/os/ArchLinuxARM-aarch64-latest.tar.gz')), isTrue);
  });

  test('the Arch source avoids hosts whose TLS certificate or DNS is broken', () async {
    final c = await Distros.byId('archlinux').rootfs.candidates();
    final hosts = c.map((u) => Uri.parse(u).host).toSet();
    expect(hosts, isNot(contains('os.archlinuxarm.org')));
    expect(hosts, isNot(contains('mirror.archlinuxarm.org')));
    expect(hosts, isNot(contains('us.mirror.archlinuxarm.org')));
  });
}
