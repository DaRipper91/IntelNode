import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Mirrors the boot and X-server stages into logcat, and optionally a file.
///
/// The container terminal ([TermPty]) writes only to the on-screen xterm, so a
/// failed boot leaves almost nothing in logcat. Everything here is prefixed
/// `IntelNode`: `adb logcat -d | grep IntelNode`, or read the mirrored file with
/// `run-as` on a debuggable build.
///
/// Logging never changes what the caller does. The hooks sit inside the boot
/// path (for example inside Util.execute's try block), so every public method
/// absorbs its own failures; the first one is reported once through a
/// last-resort debugPrint.
///
/// Logcat lines go through [debugPrint], which throttles output into an
/// unbounded queue: they can lag, and the last lines may be lost if the process
/// dies mid-boot (unverified on a device). The mirrored file is written
/// synchronously and is the reliable record.
class BootLog {
  BootLog._();

  static const _defaultMaxLineLength = 300;
  static const _defaultMaxLines = 3000;
  static const _defaultMaxFileBytes = 512 * 1024;

  /// Receives every finished line. debugPrint reaches logcat as I/flutter;
  /// tests replace it.
  static void Function(String line) printer = _logcat;

  static int maxLineLength = _defaultMaxLineLength;

  /// Streamed lines stop after this many per session (one notice is printed).
  /// Events are never counted, so lifecycle messages always get through.
  static int maxLines = _defaultMaxLines;

  /// When the mirrored file passes this size it is moved to `<path>.1`.
  static int maxFileBytes = _defaultMaxFileBytes;

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, StringBuffer> _pending = {};
  static int _emitted = 0;
  static bool _capNoticeSent = false;
  static File? _file;
  static int _fileBytes = 0;
  static int _loggerFailures = 0;
  static bool _failureReported = false;

  // CSI (colours, cursor moves), OSC (window titles, also when unterminated),
  // charset selects such as ESC ( B, and the bare two-character escapes.
  static final RegExp _ansi = RegExp(
    r'\x1B\[[0-9;?]*[ -/]*[@-~]'
    r'|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\|$)'
    r'|\x1B[()*+][0-9A-Za-z]'
    r'|\x1B[78=>cDEHMNO]',
  );
  static final RegExp _control = RegExp(r'[\x00-\x08\x0B-\x1F\x7F]');

  static void _logcat(String line) => debugPrint(line);

  /// How many times the printer or the file mirror failed (they are absorbed).
  @visibleForTesting
  static int get loggerFailures => _loggerFailures;

  /// Mirrors streamed terminal output. [chunk] may end mid-line; the remainder
  /// is held per [tag] until its newline arrives (or [flush] is called).
  static void feed(String tag, String chunk) => _safe(() {
        final text = (_pending[tag]?.toString() ?? '') + chunk;
        final lastNewline = text.lastIndexOf('\n');
        final complete =
            lastNewline >= 0 ? text.substring(0, lastNewline) : null;
        var remainder =
            lastNewline >= 0 ? text.substring(lastNewline + 1) : text;
        // A stream that never sends a newline must not grow the buffer forever.
        var overflow = '';
        if (remainder.length > maxLineLength * 4) {
          overflow = remainder;
          remainder = '';
        }
        // Keep the buffer consistent before emitting anything.
        _pending[tag] = StringBuffer(remainder);
        if (complete != null) {
          for (final raw in complete.split('\n')) {
            _emitLine(tag, raw);
          }
        }
        if (overflow.isNotEmpty) {
          _emitLine(tag, overflow, dropped: overflow.length - maxLineLength);
        }
      });

  /// Emits whatever is left unterminated for [tag] (for example at process exit).
  static void flush(String tag) => _safe(() {
        final remainder = _pending.remove(tag)?.toString() ?? '';
        if (remainder.isNotEmpty) _emitLine(tag, remainder);
      });

  /// A lifecycle message: launch, exit code, timeout. Never rate-limited.
  static void event(String message) =>
      _safe(() => _out('IntelNode ${_stamp()} $message'));

  /// Also appends everything to [path] and starts a new line budget, so a later
  /// boot is not silenced by a long earlier one. A write failure is reported
  /// once and disables the file; logging to [printer] carries on.
  static void attachFile(String path) => _safe(() {
        final file = File(path);
        try {
          _fileBytes = file.existsSync() ? file.lengthSync() : 0;
        } on FileSystemException {
          _fileBytes = 0;
        }
        _file = file;
        _emitted = 0;
        _capNoticeSent = false;
      });

  @visibleForTesting
  static void reset() {
    _pending.clear();
    _emitted = 0;
    _capNoticeSent = false;
    _file = null;
    _fileBytes = 0;
    _loggerFailures = 0;
    _failureReported = false;
    printer = _logcat;
    maxLineLength = _defaultMaxLineLength;
    maxLines = _defaultMaxLines;
    maxFileBytes = _defaultMaxFileBytes;
    _clock
      ..reset()
      ..start();
  }

  static void _emitLine(String tag, String raw, {int dropped = 0}) {
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
    if (dropped > 0) line = '$line [+$dropped chars dropped]';
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

  // The printer and the file fail independently: one must never skip the other.
  static void _out(String line) {
    _safe(() => printer(line));
    _safe(() => _toFile(line));
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
      _fileBytes += utf8.encode(line).length + 1;
    } on FileSystemException catch (e) {
      _file = null;
      final os = e.osError?.message;
      _safe(() => printer('IntelNode ${_stamp()} boot log file disabled '
          '(${file.path}): ${e.message}${os == null ? '' : ' [$os]'}'));
    }
  }

  // Absorbs any failure, counts it, and reports the first one without going
  // back through [printer] (which may be what failed).
  static void _safe(void Function() body) {
    try {
      body();
    } catch (error) {
      _loggerFailures++;
      if (_failureReported) return;
      _failureReported = true;
      try {
        debugPrint(
            'IntelNode: logging failure absorbed (reported once): $error');
      } catch (_) {
        // Nothing left to report to.
      }
    }
  }
}
