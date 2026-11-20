import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/models.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

// F5: containers added after first run must carry their own package manager and
// quick commands, and the reset action must restore that manager's list.
void main() {
  InstallPlan planFor(String distroId) => ContainerInstaller.plan(
        distro: Distros.byId(distroId),
        desktop: DesktopEnvironments.byId('xfce'),
        containerName: 'test',
      );

  group('ContainerInstaller.containerInfoFor', () {
    const expected = {
      'fedora': 'dnf',
      'debian': 'apt',
      'alpine': 'apk',
      'archlinux': 'pacman',
    };
    expected.forEach((distroId, pm) {
      test('$distroId is registered as $pm with that manager\'s commands', () {
        final info = ContainerInstaller.containerInfoFor(planFor(distroId));
        expect(info.packageManager, pm);
        expect(info.commands, isNotEmpty);
        expect(info.commands, D.getCommandsForPackageManager(pm, english: true));
        // survives the JSON round trip that _registerContainer persists
        final back = ContainerInfo.fromJson(
          jsonDecode(jsonEncode(info.toJson())) as Map<String, dynamic>,
        );
        expect(back.packageManager, pm);
        expect(back.commands, isNotEmpty);
      });
    });

    test('english flag selects the pacman language set', () {
      final zh = ContainerInstaller.containerInfoFor(planFor('archlinux'), english: false);
      expect(zh.commands, D.getCommandsForPackageManager('pacman'));
    });
  });

  group('D.defaultCommandsFor (reset action)', () {
    test('non-pacman managers never get pacman commands', () {
      for (final pm in ['dnf', 'apt', 'zypper', 'apk', 'xbps']) {
        for (final english in [true, false]) {
          final list = D.defaultCommandsFor(pm, english: english);
          expect(list, isNotEmpty, reason: pm);
          expect(
            list.any((c) => (c['command'] as String).contains('pacman')),
            isFalse,
            reason: pm,
          );
        }
      }
    });

    test('pacman keeps its original defaults', () {
      expect(D.defaultCommandsFor('pacman', english: true), D.commands4En);
      expect(D.defaultCommandsFor('pacman', english: false), D.commands);
    });
  });
}
