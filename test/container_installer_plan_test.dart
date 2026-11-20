import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/distros.dart';

void main() {
  group('ContainerInstaller.plan', () {
    test('is not blocked for a verified distro + stable desktop', () {
      final plan = ContainerInstaller.plan(
        distro: Distros.byId('archlinux'),
        desktop: DesktopEnvironments.byId('xfce4'),
        containerName: 'test',
      );
      expect(plan.blocked, isFalse);
      expect(plan.blockedReason, isNull);
      expect(plan.steps, isNotEmpty);
    });

    test('is blocked for an experimental desktop even on a verified distro', () {
      final plan = ContainerInstaller.plan(
        distro: Distros.byId('archlinux'),
        desktop: DesktopEnvironments.byId('niri'),
        containerName: 'test',
      );
      expect(plan.blocked, isTrue);
      expect(plan.blockedReason, isNotNull);
    });

    test('is blocked for an unverified distro even with a stable desktop', () {
      final unverified = DistroSpec(
        id: 'preview-test',
        displayName: 'Preview Test',
        description: 'An unverified preview distro.',
        packageManager: PackageManagerFamily.apt,
        rootfs: const RootfsSource.direct(
          url: 'https://example.com/preview.tar.xz',
          verified: false,
        ),
        firstBootScript: (username) => 'set -e\n',
      );
      final plan = ContainerInstaller.plan(
        distro: unverified,
        desktop: DesktopEnvironments.byId('xfce4'),
        containerName: 'test',
      );
      expect(plan.blocked, isTrue);
      expect(plan.blockedReason, isNotNull);
    });

    test('dry-run preview is always available regardless of blocked state', () {
      final unverified = DistroSpec(
        id: 'preview-test',
        displayName: 'Preview Test',
        description: 'An unverified preview distro.',
        packageManager: PackageManagerFamily.apt,
        rootfs: const RootfsSource.direct(
          url: 'https://example.com/preview.tar.xz',
          verified: false,
        ),
        firstBootScript: (username) => 'set -e\n',
      );
      final plan = ContainerInstaller.plan(
        distro: unverified,
        desktop: DesktopEnvironments.byId('cosmic'),
        containerName: 'test',
      );
      expect(plan.steps, isNotEmpty);
      for (final step in plan.steps) {
        expect(step.description, isNotEmpty);
      }
    });

    test('install step lists the exact packages the desktop resolves to', () {
      final distro = Distros.byId('archlinux');
      final desktop = DesktopEnvironments.byId('mate');
      final plan = ContainerInstaller.plan(
        distro: distro,
        desktop: desktop,
        containerName: 'test',
      );
      final installStep = plan.steps.firstWhere(
        (s) => s.description.contains('Install'),
      );
      for (final pkg in desktop.packagesFor(distro)) {
        expect(installStep.command, contains(pkg));
      }
    });
  });

  group('ContainerInstaller.install', () {
    test('throws StateError instead of running a blocked plan', () async {
      final plan = ContainerInstaller.plan(
        distro: Distros.byId('archlinux'),
        desktop: DesktopEnvironments.byId('niri'),
        containerName: 'test',
      );
      final ran = <String>[];
      await expectLater(
        ContainerInstaller.install(
          plan,
          run: (script) async {
            ran.add(script);
            return 0;
          },
          log: (_) {},
          onProgress: (_) {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(ran, isEmpty, reason: 'a blocked plan must not touch the device');
    });
  });

  group('ContainerInstaller.aptDesktopInstallScript', () {
    final script = ContainerInstaller.aptDesktopInstallScript(['xfce4', 'dbus-x11']);

    test('keeps directory symlinks so a usr-merged /lib survives extraction', () {
      expect(script, contains('tar --keep-directory-symlink'));
    });

    test('does not swallow a failed unpack', () {
      expect(script, isNot(contains('|| true; done')));
      expect(script, contains('failed=1'));
      expect(script, contains('[ "\$failed" = 0 ]'));
    });

    test('downloads the requested packages without dpkg installing them', () {
      expect(script, contains('--download-only --no-install-recommends xfce4 dbus-x11'));
      expect(script, isNot(contains('dpkg -i')));
    });

    test('fetches the SVG loader and glib tools that Recommends would have pulled in', () {
      for (final p in ContainerInstaller.aptDesktopSupportPackages) {
        expect(script, contains(p));
      }
      expect(ContainerInstaller.aptDesktopSupportPackages, contains('librsvg2-common'));
    });

    test('replays the pixbuf loader cache and icon cache triggers after unpacking', () {
      expect(script, contains('gdk-pixbuf-query-loaders'));
      expect(script, contains('--update-cache'));
      expect(script, contains('gtk-update-icon-cache'));
      expect(script.indexOf('gdk-pixbuf-query-loaders'),
          greaterThan(script.indexOf('--keep-directory-symlink')));
    });
  });
}
