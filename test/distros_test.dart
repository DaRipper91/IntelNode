import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/distros.dart';

void main() {
  group('Distros.all', () {
    test('is non-empty and has unique ids', () {
      expect(Distros.all, isNotEmpty);
      final ids = Distros.all.map((d) => d.id).toSet();
      expect(ids.length, Distros.all.length);
    });

    test('includes the baseline and extended distros', () {
      final ids = Distros.all.map((d) => d.id).toSet();
      expect(
        ids,
        containsAll([
          'archlinux',
          'fedora',
          'debian',
          'ubuntu',
          'opensuse',
          'alpine',
          'void',
          'kali',
        ]),
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
      // Fedora rootfs images ship excludepkgs=*selinux*; a desktop group that pulls
      // in policycoreutils/anaconda would otherwise abort the whole transaction.
      expect(d.installCommand(['foo']), contains('--skip-broken'));
      expect(d.installCommand(['foo']), contains('install_weak_deps=False'));
      expect(d.removeCommand(['foo']), contains('dnf -y remove'));
      // A full dnf upgrade in proot pulls in packages the container cannot
      // service; refresh metadata only.
      expect(d.updateCommand, contains('dnf -y makecache'));
      expect(d.updateCommand, isNot(contains('upgrade')));
    });

    test('apt', () {
      final d = Distros.byId('debian');
      // Dpkg backup hardlinks fail under proot, so overwrite/confold are forced
      // and recommended packages are skipped.
      expect(d.installCommand(['foo']), contains('apt-get -y'));
      expect(d.installCommand(['foo']), contains('--force-overwrite'));
      expect(d.installCommand(['foo']), contains('--force-confold'));
      expect(d.installCommand(['foo']), contains('--no-install-recommends'));
      expect(d.installCommand(['foo']), contains('foo'));
      expect(d.removeCommand(['foo']), contains('apt-get -y purge'));
      expect(d.updateCommand, contains('apt-get update'));
      expect(d.updateCommand, isNot(contains('upgrade')));
    });

    test('zypper', () {
      final d = Distros.byId('opensuse');
      expect(d.installCommand(['foo']), contains('zypper --non-interactive --gpg-auto-import-keys'));
      expect(d.installCommand(['foo']), contains('--allow-unsigned-rpm'));
      expect(d.installCommand(['foo']), contains('install foo'));
      expect(d.removeCommand(['foo']), contains('zypper --non-interactive remove'));
      expect(d.updateCommand, contains('zypper --non-interactive --gpg-auto-import-keys refresh'));
      expect(d.updateCommand, isNot(contains('update')));
    });

    test('apk', () {
      final d = Distros.byId('alpine');
      expect(d.installCommand(['foo']), contains('apk add --no-cache'));
      expect(d.removeCommand(['foo']), contains('apk del'));
      expect(d.updateCommand, contains('apk update'));
    });

    test('xbps', () {
      final d = Distros.byId('void');
      expect(d.installCommand(['foo']), contains('xbps-install -y'));
      expect(d.removeCommand(['foo']), contains('xbps-remove -Ry'));
      // Only xbps itself is updated; a full -Syu upgrade breaks in proot.
      expect(d.updateCommand, contains('xbps-install -Su xbps'));
      expect(d.updateCommand, isNot(contains('-Syu')));
    });
  });

  group('RootfsSource', () {
    test('main distros are marked verified for on-device installation', () {
      expect(Distros.byId('archlinux').rootfs.verified, isTrue);
      expect(Distros.byId('ubuntu').rootfs.verified, isTrue);
      expect(Distros.byId('debian').rootfs.verified, isTrue);
      expect(Distros.byId('fedora').rootfs.verified, isTrue);
      expect(Distros.byId('opensuse').rootfs.verified, isTrue);
      expect(Distros.byId('alpine').rootfs.verified, isTrue);
      expect(Distros.byId('void').rootfs.verified, isTrue);
    });

    test('kali is now verified after on-device testing', () {
      expect(Distros.byId('kali').rootfs.verified, isTrue);
    });

    test('direct source describes its literal URL', () {
      final source = Distros.byId('archlinux').rootfs;
      expect(source.describeSource, source.directUrl);
    });

    test('simplestreams source describes its resolution mechanism', () {
      final source = Distros.byId('kali').rootfs;
      expect(source.describeSource, contains('resolved at install time'));
    });
  });

  group('first-boot provisioning scripts', () {
    test('create the expected user and remove Termux profile scripts', () {
      for (final distro in Distros.all) {
        final script = distro.firstBootScript('tiny');
        expect(script, contains('/etc/passwd'),
            reason: '${distro.id} does not edit /etc/passwd directly');
        expect(script, contains('/etc/group'),
            reason: '${distro.id} does not edit /etc/group directly');
        expect(script, isNot(contains('useradd')),
            reason: '${distro.id} uses useradd which locks under proot');
        expect(script, isNot(contains('groupadd')),
            reason: '${distro.id} uses groupadd which locks under proot');
        expect(script, contains('sudoers.d/tiny'));
        expect(script, contains('polkit-1/rules.d'));
        expect(script, contains('termux'));
        expect(script, contains('mkdir -p /etc/sudoers.d'));
      }
    });

    test('fedora avoids proot-unsafe glibc/systemd upgrades', () {
      final script = Distros.byId('fedora').firstBootScript('tiny');
      final commands = script
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      // The English locale pack pins to the newest version, dragging glibc and
      // systemd into the transaction; proot cannot unpack their hardlinks.
      expect(commands, isNot(contains('glibc-langpack-en')));
      expect(commands, isNot(contains('dnf -y install')));
      expect(commands, contains('dnf makecache'));
      expect(commands, contains("printf 'LANG=C.UTF-8\\n' > /etc/locale.conf"));
    });

    test('debian/ubuntu avoid locales package to prevent proot libc6 upgrades', () {
      for (final id in ['debian', 'ubuntu']) {
        final script = Distros.byId(id).firstBootScript('tiny');
        final commands = script
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('#'))
            .join('\n');
        // Installing locales drags libc6/libc-bin upgrades; dpkg under proot
        // cannot create dpkg backup links and the upgrade aborts.
        expect(commands, isNot(contains('locales')),
            reason: '$id installs locales which pulls a libc6 upgrade');
        expect(commands, contains('LANG=C.UTF-8'),
            reason: '$id does not set C.UTF-8 locale directly');
      }
    });

    test('shadow utilities are not used under proot (no lock/race failures)', () {
      for (final distro in Distros.all) {
        final script = distro.firstBootScript('tiny');
        expect(script, isNot(contains('groupadd')),
            reason: '${distro.id} uses groupadd which locks under proot');
        expect(script, isNot(contains('useradd')),
            reason: '${distro.id} uses useradd which locks under proot');
        expect(script, isNot(contains('/etc/group.lock')),
            reason: '${distro.id} still references shadow lock files');
        expect(script, contains('/etc/passwd'),
            reason: '${distro.id} does not edit /etc/passwd directly');
        expect(script, contains('/etc/group'),
            reason: '${distro.id} does not edit /etc/group directly');
      }
    });

    test('void does not self-upgrade xbps under proot', () {
      final script = Distros.byId('void').firstBootScript('tiny');
      final commands = script
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      // xbps self-update under proot corrupts libxbps.so.6; Void skips xbps
      // entirely and edits /etc files directly.
      expect(commands, isNot(contains('xbps-install')),
          reason: 'void uses xbps-install which corrupts libxbps.so.6 under proot');
      expect(commands, contains('/etc/passwd'),
          reason: 'void does not edit /etc/passwd directly');
    });
  });
}
