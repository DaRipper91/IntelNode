import 'dart:io';

import 'package:flutter/foundation.dart';

/// Mirrors the boot and X-server stages into logcat, and optionally a file.
///
/// The container terminal ([TermPty]) writes only to the on-screen xterm, so a
/// failed boot leaves almost nothing in logcat. Everything here is prefixed
/// `IntelNode`: `adb logcat -d | grep IntelNode`, or read the mirrored file with
/// `run-as` on a debuggable build.
class BootLog {
  BootLog._();

  static const _defaultMaxLineLength = 300;
  static const _defaultMaxLines = 3000;
  static const _defaultMaxFileBytes = 512 * 1024;

  /// Receives every finished line. debugPrint reaches logcat as I/flutter;
  /// tests replace it.
  static void Function(String line) printer = _logcat;

  static int maxLineLength = _defaultMaxLineLength;

  /// Streamed lines stop after this many (one notice is printed). Events are
  /// never counted, so lifecycle messages always get through.
  static int maxLines = _defaultMaxLines;

  /// When the mirrored file passes this size it is moved to `<path>.1`.
  static int maxFileBytes = _defaultMaxFileBytes;

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, StringBuffer> _pending = {};
  static int _emitted = 0;
  static bool _capNoticeSent = false;
  static File? _file;
  static int _fileBytes = 0;

  // CSI sequences (colours, cursor moves) and OSC sequences (window titles).
  static final RegExp _ansi = RegExp(
    r'\x1B\[[0-9;?]*[ -/]*[@-~]|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)',
  );
  static final RegExp _control = RegExp(r'[\x00-\x08\x0B-\x1F\x7F]');

  static void _logcat(String line) => debugPrint(line);

  /// Mirrors streamed terminal output. [chunk] may end mid-line; the remainder
  /// is held per [tag] until its newline arrives (or [flush] is called).
  static void feed(String tag, String chunk) {
    final text = (_pending[tag]?.toString() ?? '') + chunk;
    final lastNewline = text.lastIndexOf('\n');
    var remainder = text;
    if (lastNewline >= 0) {
      remainder = text.substring(lastNewline + 1);
      for (final raw in text.substring(0, lastNewline).split('\n')) {
        _emitLine(tag, raw);
      }
    }
    // A stream that never sends a newline must not grow the buffer forever.
    if (remainder.length > maxLineLength * 4) {
      _emitLine(tag, remainder);
      remainder = '';
    }
    _pending[tag] = StringBuffer(remainder);
  }

  /// Emits whatever is left unterminated for [tag] (for example at process exit).
  static void flush(String tag) {
    final remainder = _pending.remove(tag)?.toString() ?? '';
    if (remainder.isNotEmpty) _emitLine(tag, remainder);
  }

  /// A lifecycle message: launch, exit code, timeout. Never rate-limited.
  static void event(String message) => _out('IntelNode ${_stamp()} $message');

  /// Also appends everything to [path]. A write failure is reported once and
  /// disables the file; logging to [printer] carries on.
  static void attachFile(String path) {
    final file = File(path);
    try {
      _fileBytes = file.existsSync() ? file.lengthSync() : 0;
    } on FileSystemException {
      _fileBytes = 0;
    }
    _file = file;
  }

  @visibleForTesting
  static void reset() {
    _pending.clear();
    _emitted = 0;
    _capNoticeSent = false;
    _file = null;
    _fileBytes = 0;
    printer = _logcat;
    maxLineLength = _defaultMaxLineLength;
    maxLines = _defaultMaxLines;
    maxFileBytes = _defaultMaxFileBytes;
    _clock
      ..reset()
      ..start();
  }

  static void _emitLine(String tag, String raw) {
    // Tools redraw progress with \r; keep only the final state of the line.
    var line = raw.replaceAll(_ansi, '').split('\r').lastWhere(
          (segment) => segment.trim().isNotEmpty,
          orElse: () => '',
        );
    line = line.replaceAll(_control, '').trimRight();
    if (line.trim().isEmpty) return;
    if (line.length > maxLineLength) {
      line = '${line.substring(0, maxLineLength)}...';
    }
    if (_emitted >= maxLines) {
      if (!_capNoticeSent) {
        _capNoticeSent = true;
        event(
            'log capped at $maxLines lines (output continues in the terminal)');
      }
      return;
    }
    _emitted++;
    _out('IntelNode ${_stamp()} [$tag] $line');
  }

  static String _stamp() =>
      '+${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';

  static void _out(String line) {
    printer(line);
    _toFile(line);
  }

  static void _toFile(String line) {
    final file = _file;
    if (file == null) return;
    try {
      if (_fileBytes > maxFileBytes) {
        file.renameSync('${file.path}.1');
        _fileBytes = 0;
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append);
      _fileBytes += line.length + 1;
    } on FileSystemException catch (e) {
      _file = null;
      printer('IntelNode ${_stamp()} boot log file disabled: ${e.message}');
    }
  }
}
