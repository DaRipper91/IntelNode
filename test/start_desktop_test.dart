import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  final script = File('assets/scripts/start-desktop').absolute.path;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('intelnode_desktop_');
    File('${fixture.path}/.intelnode-session')
        .writeAsStringSync('startxfce4\n');
    // Only the X11/VirGL socket prerequisites are simulated. Execute the real
    // startup script so renderer selection and session handoff stay under test.
    File('${fixture.path}/readiness.bash').writeAsStringSync(r'''
function [() {
  if [[ "$1" == '!' && "$2" == '-S' && "$3" == '/tmp/.X11-unix/X4' ]]; then
    return 1
  fi
  if [[ "$1" == '-S' && "$2" == '/tmp/virgl-0' ]]; then
    [[ "$TEST_VIRGL_SOCKET" == 1 ]]
    return $?
  fi
  builtin [ "$@"
}
''');
    final commands = {
      'dbus-launch': '#!/bin/sh\nshift\nexec "\$@"\n',
      'startxfce4': r'''#!/bin/sh
printf 'SESSION_DRIVER=%s\n' "$GALLIUM_DRIVER"
printf 'SESSION_GL_VERSION=%s\n' "$MESA_GL_VERSION_OVERRIDE"
exit "${TEST_SESSION_EXIT:-0}"
''',
      'mkdir': '#!/bin/sh\nexec /bin/mkdir "\$@"\n',
      'chmod': '#!/bin/sh\nexec /bin/chmod "\$@"\n',
      'cat': '#!/bin/sh\nexec /bin/cat "\$@"\n',
      'xset': '#!/bin/sh\nprintf "XSET: %s\\n" "\$*" >> "\$HOME/xset.log"\n',
    };
    for (final entry in commands.entries) {
      final file = File('${fixture.path}/${entry.key}');
      file.writeAsStringSync(entry.value);
      final result = Process.runSync('chmod', ['755', file.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  ProcessResult run([Map<String, String> environment = const {}]) =>
      Process.runSync(
        '/bin/bash',
        [script],
        includeParentEnvironment: false,
        environment: {
          'HOME': fixture.path,
          'PATH': fixture.path,
          'BASH_ENV': '${fixture.path}/readiness.bash',
          ...environment,
        },
      );

  test('passes the configured VirGL driver through to the session', () {
    final result = run({'GALLIUM_DRIVER': 'virpipe'});
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_DRIVER=virpipe\n'));
    expect(result.stdout, isNot(contains('Falling back')));
  });

  test('preserves an explicit software driver despite a legacy VirGL flag', () {
    final result = run({'GALLIUM_DRIVER': 'softpipe', 'VIRGL_ENABLE': '1'});
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_DRIVER=softpipe\n'));
  });

  test('does not override an explicitly configured Mesa version', () {
    final result = run({
      'GALLIUM_DRIVER': 'virpipe',
      'MESA_GL_VERSION_OVERRIDE': '3.3',
    });
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_GL_VERSION=3.3\n'));
  });

  test('retains software fallback when no renderer was configured', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_DRIVER=llvmpipe\n'));
  });

  test('retains legacy explicit VirGL enablement', () {
    final result = run({'VIRGL_ENABLE': '1'});
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_DRIVER=virpipe\n'));
  });

  test('retains legacy socket detection', () {
    final result = run({'TEST_VIRGL_SOCKET': '1'});
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_DRIVER=virpipe\n'));
  });

  test('propagates session failure through the D-Bus handoff', () {
    final result = run({'TEST_SESSION_EXIT': '7'});
    expect(result.exitCode, 7, reason: '${result.stderr}');
  });

  test('disables X11 screensaver, DPMS, and blanking via xset', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final xsetLog = File('${fixture.path}/xset.log');
    expect(xsetLog.existsSync(), isTrue);
    final logContent = xsetLog.readAsStringSync();
    expect(logContent, contains('s off'));
    expect(logContent, contains('-dpms'));
    expect(logContent, contains('s noblank'));
  });

  test('creates dummy locker executables in ~/.local/bin and masks autostart', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final xflock4 = File('${fixture.path}/.local/bin/xflock4');
    expect(xflock4.existsSync(), isTrue);
    expect(xflock4.readAsStringSync(), contains('exit 0'));

    final screensaverStub =
        File('${fixture.path}/.local/bin/xfce4-screensaver');
    expect(screensaverStub.existsSync(), isTrue);

    final autostart =
        File('${fixture.path}/.config/autostart/xfce4-screensaver.desktop');
    expect(autostart.existsSync(), isTrue);
    expect(autostart.readAsStringSync(), contains('Hidden=true'));
  });

  test('provisions XFCE power-manager, screensaver, and session no-lock XML configs', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final powerXml = File(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml',
    );
    expect(powerXml.existsSync(), isTrue);
    final powerContent = powerXml.readAsStringSync();
    expect(powerContent, contains('name="lock-screen-suspend-hibernate" type="bool" value="false"'));
    expect(powerContent, contains('name="dpms-enabled" type="bool" value="false"'));
    expect(powerContent, contains('name="presentation-mode" type="bool" value="true"'));

    final saverXml = File(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml',
    );
    expect(saverXml.existsSync(), isTrue);
    final saverContent = saverXml.readAsStringSync();
    expect(saverContent, contains('name="enabled" type="bool" value="false"'));
    expect(saverContent, contains('name="idle-activation-enabled" type="bool" value="false"'));

    final sessionXml = File(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml',
    );
    expect(sessionXml.existsSync(), isTrue);
    final sessionContent = sessionXml.readAsStringSync();
    expect(sessionContent, contains('name="LockCommand" type="string" value="/bin/true"'));
  });
}
