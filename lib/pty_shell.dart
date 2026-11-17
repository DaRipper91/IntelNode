import 'package:flutter_pty/flutter_pty.dart';

/// Environment for every shell the app puts on a PTY.
///
/// Android's mksh sources /system/etc/mkshrc whenever it runs interactively,
/// and a PTY always counts as interactive. Root modules such as Termux Root
/// Modifications replace that file with `exec /system/etc/shell`, a Termux-built
/// binary that dies outside Termux with `CANNOT LINK EXECUTABLE ... libssl.so.3
/// not found`. $ENV overrides the default mkshrc, so pointing it at /dev/null
/// keeps the shell stock on every device. `sh +i` and unsetting ENV do not work.
const Map<String, String> ptyShellEnvironment = {'ENV': '/dev/null'};

/// Starts `/system/bin/sh` on a PTY without letting a patched mkshrc hijack it.
Pty startShell({String? workingDirectory, int rows = 25, int columns = 80}) =>
    Pty.start(
      "/system/bin/sh",
      environment: ptyShellEnvironment,
      workingDirectory: workingDirectory,
      rows: rows,
      columns: columns,
    );
