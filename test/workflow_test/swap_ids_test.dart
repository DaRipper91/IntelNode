import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Util.swapAlarmTinyIdsCommand', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('ids_');
      Directory('${root.path}/etc').createSync();
      File('${root.path}/etc/passwd').writeAsStringSync(
        'root:x:0:0::/root:/usr/bin/bash\n'
        'alarm:x:1000:1000::/home/alarm:/bin/bash\n'
        'tiny:x:1001:1001::/home/tiny:/bin/bash\n',
      );
      File('${root.path}/etc/group').writeAsStringSync(
        'wheel:x:998:alarm,tiny\nalarm:x:1000:\ntiny:x:1001:\n',
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    ProcessResult run() => Process.runSync(
        'sh', ['-c', Util.swapAlarmTinyIdsCommand(root.path)]);

    test('makes tiny uid/gid 1000 and moves alarm to 1001', () {
      expect(run().exitCode, 0);
      final passwd = File('${root.path}/etc/passwd').readAsStringSync();
      final group = File('${root.path}/etc/group').readAsStringSync();
      expect(passwd, contains('tiny:x:1000:1000::/home/tiny'));
      expect(passwd, contains('alarm:x:1001:1001::/home/alarm'));
      expect(passwd, contains('root:x:0:0'));
      expect(group, contains('tiny:x:1000:'));
      expect(group, contains('alarm:x:1001:'));
      expect(group, contains('wheel:x:998:alarm,tiny'));
    });

    test('leaves a rootfs that already has tiny at 1000 untouched', () {
      File('${root.path}/etc/passwd').writeAsStringSync(
          'tiny:x:1000:1000::/home/tiny:/bin/bash\n');
      File('${root.path}/etc/group').writeAsStringSync('tiny:x:1000:\n');
      expect(run().exitCode, 0);
      expect(File('${root.path}/etc/passwd').readAsStringSync(),
          'tiny:x:1000:1000::/home/tiny:/bin/bash\n');
      expect(File('${root.path}/etc/group').readAsStringSync(), 'tiny:x:1000:\n');
    });
  });
}
