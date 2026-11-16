import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/models.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

Iterable<String> _commandsOf(List<Map<String, dynamic>> list) =>
    list.map((c) => c['command'] as String);

void main() {
  group('ContainerInfo distro detection', () {
    test('maps distro names to package managers', () {
      const expected = {
        'Arch Linux': 'pacman',
        'Arch Linux ARM': 'pacman',
        'Fedora 40': 'dnf',
        'F39': 'dnf',
        'openSUSE Tumbleweed': 'zypper',
        'openSUSE Leap 15.6': 'zypper',
        'Ubuntu 24.04': 'apt',
        'Debian Trixie': 'apt',
        'Kali Linux': 'apt',
        'Alpine Linux': 'apk',
        'Alpine 3.21': 'apk',
        'Void Linux': 'xbps',
      };
      expected.forEach((name, pm) {
        expect(ContainerInfo.packageManagerForDistro(name), pm, reason: name);
      });
    });

    test('unknown or lookalike names fall back to pacman', () {
      expect(ContainerInfo.packageManagerForDistro('Monarch'), 'pacman');
      expect(ContainerInfo.packageManagerForDistro(''), 'pacman');
    });

    test('fromJson without a name defaults to Arch Linux ARM / pacman', () {
      final info = ContainerInfo.fromJson({});
      expect(info.name, 'Arch Linux ARM');
      expect(info.packageManager, 'pacman');
    });

    test('fromJson honours a valid stored packageManager over the name', () {
      final info = ContainerInfo.fromJson({
        'name': 'Arch Linux',
        'packageManager': 'dnf',
      });
      expect(info.packageManager, 'dnf');
    });

    test('fromJson ignores an unsupported stored packageManager', () {
      final info = ContainerInfo.fromJson({
        'name': 'Fedora 40',
        'packageManager': 'emerge',
      });
      expect(info.packageManager, 'dnf');
    });

    test('packageManager round-trips once without duplicating in extra props',
        () {
      final info = ContainerInfo.fromJson({
        'name': 'Debian Trixie',
        'packageManager': 'apt',
      });
      expect(info.additionalProps.containsKey('packageManager'), isFalse);
      expect(info.toJson()['packageManager'], 'apt');
      expect(info.getProp('packageManager'), 'apt');
      expect(info.hasProp('packageManager'), isTrue);
    });
  });

  group('D.getCommandsForPackageManager', () {
    test('returns the collection for each package manager', () {
      expect(_commandsOf(D.getCommandsForPackageManager('pacman')),
          contains('pacman -Syu --noconfirm'));
      expect(_commandsOf(D.getCommandsForPackageManager('apt')),
          contains('apt update -y && apt upgrade -y'));
      expect(_commandsOf(D.getCommandsForPackageManager('dnf')),
          contains('sudo dnf -y update'));
      expect(_commandsOf(D.getCommandsForPackageManager('zypper')).first,
          contains('zypper --non-interactive refresh'));
    });

    test('unknown package manager falls back to pacman', () {
      expect(D.getCommandsForPackageManager('emerge'),
          same(D.getCommandsForPackageManager('pacman')));
    });

    test('english flag only switches the pacman set', () {
      expect(D.getCommandsForPackageManager('pacman', english: true),
          same(D.commands4En));
      expect(D.getCommandsForPackageManager('dnf', english: true),
          same(D.getCommandsForPackageManager('dnf')));
    });

    test('pacman sets never use apt or pacman -U on a .deb', () {
      for (final list in [
        D.getCommandsForPackageManager('pacman'),
        D.commands,
        D.commands4En,
      ]) {
        for (final cmd in _commandsOf(list)) {
          expect(RegExp(r'\bapt(-get)?\b').hasMatch(cmd), isFalse, reason: cmd);
          expect(cmd.contains('pacman -U'), isFalse, reason: cmd);
          expect(cmd.contains('AppImage'), isFalse, reason: cmd);
        }
      }
    });

    test('rpm-based sets use valid flag placement and no Debian names', () {
      for (final pm in ['dnf', 'zypper']) {
        for (final cmd in _commandsOf(D.getCommandsForPackageManager(pm))) {
          expect(RegExp(r'\bapt\b').hasMatch(cmd), isFalse, reason: cmd);
          expect(cmd.contains('zypper -y'), isFalse, reason: cmd);
          expect(cmd.contains('--autoremove'), isFalse, reason: cmd);
          expect(cmd.contains('libglut3.12'), isFalse, reason: cmd);
          expect(cmd.contains('logo_900_2.png'), isFalse, reason: cmd);
        }
      }
    });

    test('deb-only apps are extracted with bsdtar rather than installed', () {
      final wps = D
          .getCommandsForPackageManager('pacman')
          .firstWhere((c) => c['name'] == '安装WPS')['command'] as String;
      expect(wps, contains("bsdtar -xOf /tmp/wps.deb 'data.tar*'"));
      expect(wps, isNot(contains('pacman')));
    });
  });
}
