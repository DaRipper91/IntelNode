import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/boot_log.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> out;
  late List<String> calls;

  setUp(() {
    BootLog.reset();
    out = [];
    calls = [];
    BootLog.printer = out.add;
  });

  tearDown(() {
    BootLog.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(D.androidChannel, null);
  });

  void stubChannel(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(D.androidChannel, (call) async {
      calls.add(call.method);
      return handler(call);
    });
  }

  test('a failing start is logged and does not throw', () async {
    stubChannel((_) => throw PlatformException(code: 'denied'));

    await Workflow.startContainerForegroundService();

    expect(calls, ['startContainerService']);
    expect(out.single, contains('startContainerService failed'));
    expect(out.single, contains('denied'));
  });

  test('a failing stop is logged and does not throw', () async {
    stubChannel((_) => throw PlatformException(code: 'gone'));

    await Workflow.stopContainerForegroundService();

    expect(out.single, contains('stopContainerService failed'));
  });

  test('a missing plugin is logged too', () async {
    // No handler registered: invokeMethod throws MissingPluginException.
    await Workflow.startContainerForegroundService();

    expect(out.single, contains('MissingPluginException'));
  });

  test('success logs nothing', () async {
    stubChannel((_) => null);

    await Workflow.startContainerForegroundService();
    await Workflow.stopContainerForegroundService();

    expect(calls, ['startContainerService', 'stopContainerService']);
    expect(out, isEmpty);
  });
}
