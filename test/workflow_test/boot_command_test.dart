import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/fake_proc.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Workflow.getBootCommand', () {
    final cmd = Workflow.getBootCommand();

    test('does not bind another app\'s /tmp over the container /tmp', () {
      expect(cmd, isNot(contains('com.termux')));
      expect(cmd, isNot(contains(':/tmp ')));
    });

    test('mounts cap_last_cap from /dev/null and every fake /proc entry', () {
      expect(cmd, contains('--mount=/dev/null:/proc/sys/kernel/cap_last_cap'));
      for (final name in FakeProc.names) {
        expect(cmd, contains('--mount=\$DATA_DIR/fakeproc/$name:/proc/$name '),
            reason: name);
      }
    });

    test('keeps the container tmp as /dev/shm so the X socket dir is shared', () {
      expect(cmd, contains('--mount=\$CONTAINER_DIR/tmp:/dev/shm '));
    });
  });

  group('FakeProc.writeTo', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('fakeproc_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('creates every mount source as the right kind of entry', () {
      FakeProc.writeTo(tmp.path);
      for (final name in FakeProc.names) {
        final path = '${tmp.path}/fakeproc/$name';
        if (FakeProc.directories.contains(name)) {
          expect(Directory(path).existsSync(), isTrue, reason: name);
        } else {
          expect(File(path).existsSync(), isTrue, reason: name);
        }
      }
    });

    test('is idempotent and refreshes content on rewrite', () {
      FakeProc.writeTo(tmp.path);
      File('${tmp.path}/fakeproc/loadavg').writeAsStringSync('stale');
      FakeProc.writeTo(tmp.path);
      expect(File('${tmp.path}/fakeproc/loadavg').readAsStringSync(),
          FakeProc.contents['loadavg']);
    });

    test('every entry with content is also a mounted name', () {
      for (final key in FakeProc.contents.keys) {
        expect(FakeProc.names, contains(key));
      }
    });
  });

  test('disables the glycin sandbox (bubblewrap cannot run under proot)', () {
    expect(Workflow.getBootCommand(), contains('GLYCIN_DISABLE_SANDBOX=1'));
  });
}
