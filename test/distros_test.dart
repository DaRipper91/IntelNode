import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/distros.dart';

void main() {
  group('Distros.all', () {
    test('is non-empty and has unique ids', () {
      expect(Distros.all, isNotEmpty);
      final ids = Distros.all.map((d) => d.id).toSet();
      expect(ids.length, Distros.all.length);
    });

    test('includes the four baseline distros', () {
      final ids = Distros.all.map((d) => d.id).toSet();
      expect(
        ids,
        containsAll(['archlinux', 'fedora', 'debian', 'ubuntu']),
      );
    });

    test('byId falls back to the first entry for an unknown id', () {
      expect(Distros.byId('nonexistent'), same(Distros.all.first));
    });

    test('byId returns the matching entry', () {
      expect(Distros.byId('fedora').id, 'fedora');
    });
  });

  group('DistroSpec package manager command templates', () {
    test('pacman', () {
      final d = Distros.byId('archlinux');
      expect(d.installCommand(['foo', 'bar']), contains('pacman -S'));
      expect(d.installCommand(['foo', 'bar']), contains('foo bar'));
      expect(d.removeCommand(['foo']), contains('pacman -Rns'));
      expect(d.updateCommand, contains('pacman -Syu'));
    });

    test('dnf', () {
      final d = Distros.byId('fedora');
      expect(d.installCommand(['foo']), contains('dnf -y install'));
      expect(d.removeCommand(['foo']), contains('dnf -y remove'));
      expect(d.updateCommand, contains('dnf -y upgrade'));
    });

    test('apt', () {
      final d = Distros.byId('debian');
      expect(d.installCommand(['foo']), contains('apt-get -y install'));
      expect(d.removeCommand(['foo']), contains('apt-get -y purge'));
      expect(d.updateCommand, contains('apt-get update'));
    });
  });

  group('RootfsSource', () {
    test('Arch and Ubuntu are marked verified', () {
      expect(Distros.byId('archlinux').rootfs.verified, isTrue);
      expect(Distros.byId('ubuntu').rootfs.verified, isTrue);
    });

    test('Fedora and Debian are marked unverified pending device testing', () {
      expect(Distros.byId('fedora').rootfs.verified, isFalse);
      expect(Distros.byId('debian').rootfs.verified, isFalse);
    });

    test('direct source describes its literal URL', () {
      final source = Distros.byId('archlinux').rootfs;
      expect(source.describeSource, source.directUrl);
    });

    test('simplestreams source describes its resolution mechanism', () {
      final source = Distros.byId('debian').rootfs;
      expect(source.describeSource, contains('resolved at install time'));
    });
  });

  group('first-boot provisioning scripts', () {
    test('create the expected user and remove Termux profile scripts', () {
      for (final distro in Distros.all) {
        final script = distro.firstBootScript('tiny');
        expect(script, contains('useradd -m -s /bin/bash tiny'));
        expect(script, contains('sudoers.d/tiny'));
        expect(script, contains('polkit-1/rules.d'));
        expect(script, contains('termux'));
      }
    });
  });
}
