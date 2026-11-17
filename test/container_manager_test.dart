import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:da_ripped_tiny_computer/container_manager.dart';

void main() {
  group('ContainerManager.plan', () {
    test('compacts the indexes of the survivors', () {
      final p = ContainerManager.plan(
        count: 4,
        remove: {1, 2},
        current: 0,
        defaultContainer: 0,
      );
      expect(p.remove, [1, 2]);
      expect(p.survivors, [0, 3]);
      expect(p.moves, {3: 1});
      expect(p.newDefault, 0);
      expect(p.newCurrent, 0);
    });

    test('follows the default container to its new index', () {
      final p = ContainerManager.plan(
        count: 4,
        remove: {1},
        current: 0,
        defaultContainer: 3,
      );
      expect(p.moves, {2: 1, 3: 2});
      expect(p.newDefault, 2);
    });

    test('deleting the last container moves nothing', () {
      final p = ContainerManager.plan(
        count: 3,
        remove: {2},
        current: 0,
        defaultContainer: 0,
      );
      expect(p.moves, isEmpty);
      expect(p.survivors, [0, 1]);
    });

    test('refuses the running container, the default one and anything below the running one', () {
      final ok = ContainerManager.plan(count: 4, remove: {2}, current: 1, defaultContainer: 3);
      expect(ok.moves, {3: 2});
      expect(ok.newCurrent, 1, reason: 'the running folder must not move');
      for (final c in [
        (remove: {1}, current: 1, def: 2), // running
        (remove: {2}, current: 0, def: 2), // default
        (remove: {0}, current: 1, def: 2), // would shift the running folder
      ]) {
        expect(
          () => ContainerManager.plan(
            count: 3,
            remove: c.remove,
            current: c.current,
            defaultContainer: c.def,
          ),
          throwsStateError,
          reason: '$c',
        );
      }
    });

    test('refuses an empty selection and out-of-range indexes', () {
      expect(
        () => ContainerManager.plan(count: 2, remove: {}, current: 0, defaultContainer: 0),
        throwsStateError,
      );
      expect(
        () => ContainerManager.plan(count: 2, remove: {5}, current: 0, defaultContainer: 0),
        throwsStateError,
      );
    });
  });

  group('ContainerManager.entries', () {
    test('reads names and says why a container cannot be deleted', () {
      final entries = ContainerManager.entries(
        [
          jsonEncode({'name': 'Arch Linux'}),
          jsonEncode({'name': 'Fedora'}),
          'not json',
        ],
        current: 0,
        defaultContainer: 0,
      );
      expect(entries.map((e) => e.name), ['Arch Linux', 'Fedora', 'Container 2']);
      expect(entries[0].blockedReason, isNotNull);
      expect(entries[1].blockedReason, isNull);
      expect(entries[2].blockedReason, isNull);
    });
  });

  group('ContainerManager.script', () {
    // Arch rootfs directories are read-only (0555); a plain rm cannot empty them.
    test('removes the chosen folders and renumbers the rest on a real filesystem', () {
      final work = Directory.systemTemp.createTempSync('cm_');
      addTearDown(() {
        Process.runSync('chmod', ['-R', 'u+rwX', work.path]);
        work.deleteSync(recursive: true);
      });
      for (var i = 0; i < 4; i++) {
        File('${work.path}/containers/$i/id').createSync(recursive: true);
        File('${work.path}/containers/$i/id').writeAsStringSync('$i');
      }
      Directory('${work.path}/containers/1/etc/ro').createSync(recursive: true);
      File('${work.path}/containers/1/etc/ro/f').writeAsStringSync('x');
      Process.runSync('chmod', ['555', '${work.path}/containers/1/etc/ro']);
      Directory('${work.path}/containers/2_staging').createSync();

      final plan = ContainerManager.plan(
        count: 4,
        remove: {1, 2},
        current: 0,
        defaultContainer: 0,
      );
      final r = Process.runSync('sh', ['-c', ContainerManager.script(work.path, plan)]);
      expect(r.exitCode, 0, reason: '${r.stderr}');

      final names = Directory('${work.path}/containers')
          .listSync()
          .map((e) => e.path.split('/').last)
          .toList()
        ..sort();
      expect(names, ['0', '1']);
      expect(File('${work.path}/containers/0/id').readAsStringSync(), '0');
      expect(File('${work.path}/containers/1/id').readAsStringSync(), '3');
    });

    test('quotes a data path containing spaces and quotes', () {
      final work = Directory.systemTemp.createTempSync("cm it's ");
      addTearDown(() {
        Process.runSync('chmod', ['-R', 'u+rwX', work.path]);
        work.deleteSync(recursive: true);
      });
      for (var i = 0; i < 3; i++) {
        File('${work.path}/containers/$i/id').createSync(recursive: true);
        File('${work.path}/containers/$i/id').writeAsStringSync('$i');
      }
      final plan = ContainerManager.plan(count: 3, remove: {1}, current: 0, defaultContainer: 0);
      final r = Process.runSync('sh', ['-c', ContainerManager.script(work.path, plan)]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('${work.path}/containers/1/id').readAsStringSync(), '2');
    });
  });
}
