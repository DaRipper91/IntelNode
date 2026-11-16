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
printf 'SESSION_LP_NUM_THREADS=%s\n' "$LP_NUM_THREADS"
printf 'SESSION_MESA_NO_ERROR=%s\n' "$MESA_NO_ERROR"
exit "${TEST_SESSION_EXIT:-0}"
''',
      'mkdir': '#!/bin/sh\nexec /bin/mkdir "\$@"\n',
      'chmod': '#!/bin/sh\nexec /bin/chmod "\$@"\n',
      'cat': '#!/bin/sh\nexec /bin/cat "\$@"\n',
      'sed': '#!/bin/sh\nexec /bin/sed "\$@"\n',
      'grep': '#!/bin/sh\nexec /bin/grep "\$@"\n',
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

  test('tunes Mesa LLVMpipe multi-threading and disables error checks on software fallback', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('SESSION_LP_NUM_THREADS=4\n'));
    expect(result.stdout, contains('SESSION_MESA_NO_ERROR=1\n'));
  });

  test('creates pm-is-supported stub to avoid process execution errors', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final pmStub = File('${fixture.path}/.local/bin/pm-is-supported');
    expect(pmStub.existsSync(), isTrue);
    expect(pmStub.readAsStringSync(), contains('exit 1'));
  });

  test('provisions XFCE window manager and UI performance tuning configs', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final xfwm4Xml = File(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml',
    );
    expect(xfwm4Xml.existsSync(), isTrue);
    final xfwm4Content = xfwm4Xml.readAsStringSync();
    expect(xfwm4Content, contains('name="use_compositing" type="bool" value="false"'));
    expect(xfwm4Content, contains('name="vblank_mode" type="string" value="off"'));
    expect(xfwm4Content, contains('name="box_move" type="bool" value="true"'));
    expect(xfwm4Content, contains('name="box_resize" type="bool" value="true"'));
    expect(xfwm4Content, contains('name="show_dock_shadow" type="bool" value="false"'));

    final xsettingsXml = File(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml',
    );
    expect(xsettingsXml.existsSync(), isTrue);
    final xsettingsContent = xsettingsXml.readAsStringSync();
    expect(xsettingsContent, contains('name="EnableAnimations" type="bool" value="false"'));
    expect(xsettingsContent, contains('name="CursorBlink" type="bool" value="false"'));

    final thunarXml = File(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml',
    );
    expect(thunarXml.existsSync(), isTrue);
    final thunarContent = thunarXml.readAsStringSync();
    expect(thunarContent, contains('name="misc-thumbnail-mode" type="string" value="THUNAR_THUMBNAIL_MODE_NEVER"'));

    final gtk3Settings = File('${fixture.path}/.config/gtk-3.0/settings.ini');
    expect(gtk3Settings.existsSync(), isTrue);
    final gtk3Content = gtk3Settings.readAsStringSync();
    expect(gtk3Content, contains('gtk-enable-animations = false'));
    expect(gtk3Content, contains('gtk-cursor-blink = false'));

    final gtk2Settings = File('${fixture.path}/.gtkrc-2.0');
    expect(gtk2Settings.existsSync(), isTrue);
    final gtk2Content = gtk2Settings.readAsStringSync();
    expect(gtk2Content, contains('gtk-enable-animations = 0'));
    expect(gtk2Content, contains('gtk-cursor-blink = 0'));
  });

  test('upgrades existing xfwm4 and thunar XML configs with performance properties', () {
    // Pre-create existing xfwm4.xml and thunar.xml as would be produced by default package install
    final xfceConfDir = Directory(
      '${fixture.path}/.config/xfce4/xfconf/xfce-perchannel-xml',
    );
    xfceConfDir.createSync(recursive: true);

    File('${xfceConfDir.path}/xfwm4.xml').writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="true"/>
    <property name="vblank_mode" type="string" value="auto"/>
    <property name="show_dock_shadow" type="bool" value="true"/>
    <property name="box_move" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="false"/>
  </property>
</channel>''');

    File('${xfceConfDir.path}/thunar.xml').writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<channel name="thunar" version="1.0">
  <property name="misc-thumbnail-mode" type="string" value="THUNAR_THUMBNAIL_MODE_ALWAYS"/>
</channel>''');

    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final xfwm4Content = File('${xfceConfDir.path}/xfwm4.xml').readAsStringSync();
    expect(xfwm4Content, contains('name="use_compositing" type="bool" value="false"'));
    expect(xfwm4Content, contains('name="vblank_mode" type="string" value="off"'));
    expect(xfwm4Content, contains('name="show_dock_shadow" type="bool" value="false"'));
    expect(xfwm4Content, contains('name="box_move" type="bool" value="true"'));
    expect(xfwm4Content, contains('name="box_resize" type="bool" value="true"'));

    final thunarContent = File('${xfceConfDir.path}/thunar.xml').readAsStringSync();
    expect(thunarContent, contains('name="misc-thumbnail-mode" type="string" value="THUNAR_THUMBNAIL_MODE_NEVER"'));
  });

  test('installs intelnode-ime helper and configures mobile IME accessibility environment', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final imeHelper = File('${fixture.path}/.local/bin/intelnode-ime');
    expect(imeHelper.existsSync(), isTrue);
    final imeContent = imeHelper.readAsStringSync();
    expect(imeContent, contains('/dev/tcp/127.0.0.1/4720'));
    expect(imeContent, contains('ACTION_KEYBOARD'));

    // Check that start-desktop exports GTK_MODULES and accessibility variables
    final scriptContent = File(script).readAsStringSync();
    expect(scriptContent, contains('export GTK_MODULES='));
    expect(scriptContent, contains('gail:atk-bridge'));
    expect(scriptContent, contains('export QT_ACCESSIBILITY=1'));
    expect(scriptContent, contains('export NO_AT_BRIDGE=0'));
  });

  test('provisions Openbox no-sync configuration for rc.xml and lxqt-rc.xml', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final obRc = File('${fixture.path}/.config/openbox/rc.xml');
    expect(obRc.existsSync(), isTrue);
    expect(obRc.readAsStringSync(), contains('<sync>no</sync>'));
    expect(obRc.readAsStringSync(), contains('<application class="*" type="normal">'));
    expect(obRc.readAsStringSync(), contains('<maximized>true</maximized>'));

    final lxqtRc = File('${fixture.path}/.config/openbox/lxqt-rc.xml');
    expect(lxqtRc.existsSync(), isTrue);
    expect(lxqtRc.readAsStringSync(), contains('<sync>no</sync>'));
    expect(lxqtRc.readAsStringSync(), contains('<application class="*" type="normal">'));
    expect(lxqtRc.readAsStringSync(), contains('<maximized>true</maximized>'));
  });

  test('masks LXQt power management and screensaver stubs and autostart', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final pmStub = File('${fixture.path}/.local/bin/lxqt-powermanagement');
    expect(pmStub.existsSync(), isTrue);
    expect(pmStub.readAsStringSync(), contains('exit 0'));

    final ssStub = File('${fixture.path}/.local/bin/lxqt-screensaver');
    expect(ssStub.existsSync(), isTrue);
    expect(ssStub.readAsStringSync(), contains('exit 0'));

    final pmAutostart = File('${fixture.path}/.config/autostart/lxqt-powermanagement.desktop');
    expect(pmAutostart.existsSync(), isTrue);
    expect(pmAutostart.readAsStringSync(), contains('Hidden=true'));

    final ssAutostart = File('${fixture.path}/.config/autostart/lxqt-screensaver.desktop');
    expect(ssAutostart.existsSync(), isTrue);
    expect(ssAutostart.readAsStringSync(), contains('Hidden=true'));
  });

  test('provisions LXQt session.conf, lxqt.conf, and panel.conf', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final sessionConf = File('${fixture.path}/.config/lxqt/session.conf');
    expect(sessionConf.existsSync(), isTrue);
    expect(sessionConf.readAsStringSync(), contains('window_manager=openbox'));

    final panelConf = File('${fixture.path}/.config/lxqt/panel.conf');
    expect(panelConf.existsSync(), isTrue);
    expect(panelConf.readAsStringSync(), contains('position=Bottom'));
    expect(panelConf.readAsStringSync(), contains('panelSize=38'));

    final lxqtConf = File('${fixture.path}/.config/lxqt/lxqt.conf');
    expect(lxqtConf.existsSync(), isTrue);
    expect(lxqtConf.readAsStringSync(), contains('theme=frost'));
  });
}
