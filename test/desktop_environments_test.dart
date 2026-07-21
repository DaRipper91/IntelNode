import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/distros.dart';

void main() {
  group('DesktopEnvironments.all', () {
    test('is non-empty and has unique ids', () {
      expect(DesktopEnvironments.all, isNotEmpty);
      final ids = DesktopEnvironments.all.map((d) => d.id).toSet();
      expect(ids.length, DesktopEnvironments.all.length);
    });

    test('includes the four stable-tier desktops', () {
      final stableIds = DesktopEnvironments.forTier(DesktopTier.stable)
          .map((d) => d.id)
          .toSet();
      expect(stableIds, containsAll(['xfce4', 'lxqt', 'mate', 'i3']));
    });

    test('includes the two experimental-tier desktops', () {
      final experimentalIds =
          DesktopEnvironments.forTier(DesktopTier.experimental)
              .map((d) => d.id)
              .toSet();
      expect(experimentalIds, containsAll(['niri', 'cosmic']));
    });

    test('stable and experimental tiers partition the manifest', () {
      final stable = DesktopEnvironments.forTier(DesktopTier.stable);
      final experimental = DesktopEnvironments.forTier(DesktopTier.experimental);
      expect(stable.length + experimental.length, DesktopEnvironments.all.length);
    });

    test('every experimental entry documents its unproven caveat', () {
      for (final de in DesktopEnvironments.forTier(DesktopTier.experimental)) {
        expect(de.experimentalCaveat, isNotNull);
        expect(de.experimentalCaveat, isNotEmpty);
      }
    });

    test('every stable entry has no experimental caveat', () {
      for (final de in DesktopEnvironments.forTier(DesktopTier.stable)) {
        expect(de.experimentalCaveat, isNull);
      }
    });

    test('byId falls back to the first entry for an unknown id', () {
      expect(DesktopEnvironments.byId('nonexistent'), same(DesktopEnvironments.all.first));
    });
  });

  group('DesktopEnvironmentSpec.packagesFor', () {
    test('resolves packages via the distro package manager family', () {
      final xfce = DesktopEnvironments.byId('xfce4');
      expect(xfce.packagesFor(Distros.byId('archlinux')), contains('xfce4'));
      expect(
        xfce.packagesFor(Distros.byId('fedora')),
        contains('@xfce-desktop-environment'),
      );
      expect(xfce.packagesFor(Distros.byId('debian')), contains('xfce4'));
    });

    test('every stable desktop declares packages for every distro', () {
      for (final de in DesktopEnvironments.forTier(DesktopTier.stable)) {
        for (final distro in Distros.all) {
          expect(
            de.packagesFor(distro),
            isNotEmpty,
            reason: '${de.id} has no packages declared for ${distro.id}',
          );
        }
      }
    });
  });
}
