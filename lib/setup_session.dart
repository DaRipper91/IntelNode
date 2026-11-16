// setup_session.dart -- a visible, interactive shell used while the system is
// first installed. Install scripts run in this PTY so their output (and any
// error) lands in a terminal the user can scroll, select, copy from and paste
// into, instead of a hidden background shell.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class SetupSession {
  SetupSession(this.dataPath) {
    pty = Pty.start(
      "/system/bin/sh",
      workingDirectory: dataPath,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );
    _output = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_onOutput);
    terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));
    terminal.onResize = (w, h, pw, ph) => pty.resize(h, w);
    // A dead shell (the user typed `exit`, or it was killed) must fail the run
    // instead of leaving the install waiting for a marker that never comes.
    pty.exitCode.then((code) {
      final pending = _pending;
      if (pending != null && !pending.isCompleted) pending.complete(-1);
    });
  }

  final String dataPath;
  final Terminal terminal = Terminal(maxLines: 20000);
  final TerminalController controller = TerminalController();
  late final Pty pty;
  late final StreamSubscription<String> _output;

  int _runs = 0;
  Completer<int>? _pending;
  String? _pendingToken;
  String _tail = "";

  /// Matches the completion marker a run prints: `@@INTELNODE-<n>@@ <code>`.
  /// The marker echoed back with the literal `$?` never matches, only the
  /// expanded exit code does.
  static int? parseExitMarker(String text, String token) {
    final m = RegExp("${RegExp.escape(token)}\\s*(\\d+)").firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!);
  }

  void _onOutput(String chunk) {
    terminal.write(chunk);
    final token = _pendingToken;
    if (token == null) return;
    // A marker can be split across chunks; keep a short tail to rejoin it.
    final text = _tail + chunk;
    final code = parseExitMarker(text, token);
    if (code != null) {
      _pendingToken = null;
      _tail = "";
      _pending?.complete(code);
    } else {
      _tail = text.length > 80 ? text.substring(text.length - 80) : text;
    }
  }

  /// Writes a line to the terminal without involving the shell.
  void log(String line) => terminal.write("$line\r\n");

  /// Runs [script] in the visible shell and returns its exit code.
  Future<int> run(String script) async {
    if (_pending != null) {
      throw StateError("A setup script is already running");
    }
    final n = ++_runs;
    final dir = Directory("$dataPath/setup")..createSync(recursive: true);
    final file = File("${dir.path}/step$n.sh")..writeAsStringSync(script);
    final token = "@@INTELNODE-$n@@";
    _pendingToken = token;
    _tail = "";
    final pending = _pending = Completer<int>();
    try {
      pty.write(
        const Utf8Encoder().convert(
          "/system/bin/sh ${file.path}; echo \"$token \$?\"\n",
        ),
      );
      return await pending.future;
    } finally {
      // Reset even when the write throws so later runs (e.g. cleanup) can go.
      _pending = null;
      _pendingToken = null;
    }
  }

  /// Currently selected text, or null when nothing is selected.
  String? get selectedText {
    final range = controller.selection;
    return range == null ? null : terminal.buffer.getText(range);
  }

  /// The whole scrollback as plain text, for pasting into a bug report.
  String get fullText => terminal.buffer.getText();

  Future<void> copySelection() async {
    final text = selectedText;
    if (text != null && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> copyAll() => Clipboard.setData(ClipboardData(text: fullText));

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) terminal.paste(text);
  }

  void dispose() {
    _output.cancel();
    pty.kill();
  }
}
