import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Workflow.xkbRoot', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('xkb_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('uses the real xkeyboard-config dir when X11/xkb is an absolute dangling link', () {
      Directory('${root.path}/usr/share/xkeyboard-config-2').createSync(recursive: true);
      Link('${root.path}/usr/share/X11/xkb')
        ..createSync('/usr/share/xkeyboard-config-2', recursive: true);
      expect(Workflow.xkbRoot(root.path), '${root.path}/usr/share/xkeyboard-config-2');
    });

    test('falls back to usr/share/X11/xkb (Debian layout)', () {
      Directory('${root.path}/usr/share/X11/xkb').createSync(recursive: true);
      expect(Workflow.xkbRoot(root.path), '${root.path}/usr/share/X11/xkb');
    });
  });
}
