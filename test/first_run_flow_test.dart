import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/desktop_picker.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/setup_session.dart';

void main() {
  checksumTests();
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
