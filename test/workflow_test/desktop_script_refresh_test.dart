import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final requested = <String>[];
  const asset = 'assets/scripts/start-desktop';
  const content = '#!/bin/bash\n# current managed desktop script\n';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('desktop_refresh_');
    requested.clear();
    rootBundle.evict(asset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List(
        message.offsetInBytes,
        message.lengthInBytes,
      ));
      requested.add(path);
      if (path != asset) return null;
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    rootBundle.evict(asset);
    dir.deleteSync(recursive: true);
  });

  test(
      'replaces a stale managed script without touching adjacent or user files',
      () async {
    final extra = Directory('${dir.path}/tiny/extra')
      ..createSync(recursive: true);
    final desktop = File('${extra.path}/start-desktop')
      ..writeAsStringSync('stale');
    final arch = File('${extra.path}/start-arch.sh')
      ..writeAsStringSync('custom arch');
    final user =
        File('${dir.path}/containers/0/home/tiny/.config/xfce4/custom.xml');
    user.parent.createSync(recursive: true);
    user.writeAsStringSync('user config');

    await Workflow.refreshDesktopStartupScript(dir.path);

    expect(desktop.readAsStringSync(), content);
    expect(arch.readAsStringSync(), 'custom arch');
    expect(user.readAsStringSync(), 'user config');
    expect(requested, [asset]);
  });

  test('creates the managed script directory when needed', () async {
    await Workflow.refreshDesktopStartupScript(dir.path);

    expect(File('${dir.path}/tiny/extra/start-desktop').readAsStringSync(),
        content);
  });

  test('propagates an asset-copy failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => null);

    await expectLater(
      Workflow.refreshDesktopStartupScript(dir.path),
      throwsA(isA<FlutterError>()),
    );
    expect(File('${dir.path}/tiny/extra/start-desktop').existsSync(), isFalse);
  });
}
