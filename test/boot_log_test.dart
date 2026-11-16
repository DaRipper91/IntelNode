import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/boot_log.dart';

void main() {
  late List<String> out;

  setUp(() {
    BootLog.reset();
    out = [];
    BootLog.printer = out.add;
  });

  tearDown(BootLog.reset);

  group('BootLog.feed', () {
    test('emits one tagged line per complete line', () {
      BootLog.feed('term', 'first\nsecond\n');
      expect(out, [
        matches(r'^IntelNode \+\d+\.\ds \[term\] first$'),
        matches(r'^IntelNode \+\d+\.\ds \[term\] second$'),
      ]);
    });

    test('buffers a partial line until its newline arrives', () {
      BootLog.feed('term', 'par');
      expect(out, isEmpty);
      BootLog.feed('term', 'tial\nnext');
      expect(out, hasLength(1));
      expect(out.single, endsWith('[term] partial'));
    });

    test('keeps separate buffers per tag', () {
      BootLog.feed('a', 'one');
      BootLog.feed('b', 'two\n');
      BootLog.feed('a', '-more\n');
      expect(out.map((l) => l.split('] ').last), ['two', 'one-more']);
    });

    test('strips ANSI escapes and carriage returns', () {
      BootLog.feed('term', '\x1B[1;32mok\x1B[0m\r\n\x1B]0;title\x07done\r\n');
      expect(out.map((l) => l.split('] ').last), ['ok', 'done']);
    });

    test('drops blank lines', () {
      BootLog.feed('term', '\n\r\n   \nreal\n');
      expect(out, hasLength(1));
      expect(out.single, endsWith('real'));
    });

    test('truncates very long lines', () {
      BootLog.maxLineLength = 20;
      BootLog.feed('term', '${'x' * 50}\n');
      final text = out.single.split('] ').last;
      expect(text.length, lessThanOrEqualTo(23));
      expect(text, endsWith('...'));
    });

    test('flushes an unterminated remainder on demand', () {
      BootLog.feed('term', 'no newline at exit');
      expect(out, isEmpty);
      BootLog.flush('term');
      expect(out.single, endsWith('no newline at exit'));
      BootLog.flush('term');
      expect(out, hasLength(1),
          reason: 'flushing twice must not repeat the line');
    });

    test(
        'does not let an endless unterminated stream grow the buffer without bound',
        () {
      BootLog.maxLineLength = 10;
      BootLog.feed('term', 'y' * 100000);
      expect(out, isNotEmpty,
          reason: 'an oversized pending line is flushed instead of held');
    });
  });

  group('BootLog flood protection', () {
    test('caps streamed lines with a single notice but never drops events', () {
      BootLog.maxLines = 3;
      BootLog.feed('term', 'l1\nl2\nl3\nl4\nl5\n');
      expect(out.where((l) => l.contains('[term]')), hasLength(3));
      expect(out.where((l) => l.contains('log capped')), hasLength(1));
      BootLog.event('terminal pty exited with code 1');
      expect(out.last, endsWith('terminal pty exited with code 1'));
    });
  });

  group('BootLog.event', () {
    test('prefixes with the tag and elapsed seconds', () {
      BootLog.event('launching X server');
      expect(out.single, matches(r'^IntelNode \+\d+\.\ds launching X server$'));
    });
  });

  group('BootLog file mirror', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bootlog_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('appends emitted lines and events to the attached file', () {
      final path = '${dir.path}/boot.log';
      BootLog.attachFile(path);
      BootLog.feed('term', 'hello\n');
      BootLog.event('done');
      final text = File(path).readAsStringSync();
      expect(text, contains('[term] hello'));
      expect(text, contains('done'));
    });

    test('rotates to <path>.1 once the size cap is exceeded', () {
      final path = '${dir.path}/boot.log';
      BootLog.maxFileBytes = 200;
      BootLog.attachFile(path);
      for (var i = 0; i < 20; i++) {
        BootLog.event('event number $i with some padding text');
      }
      expect(File('$path.1').existsSync(), isTrue);
      expect(File(path).lengthSync(), lessThan(400));
    });

    test(
        'an unwritable path never throws, is reported once, and logging continues',
        () {
      BootLog.attachFile('${dir.path}/missing-dir/nested/boot.log');
      expect(() => BootLog.event('still works'), returnsNormally);
      BootLog.event('and again');
      expect(
          out.where((l) => l.contains('boot log file disabled')), hasLength(1));
      expect(out.where((l) => l.endsWith('still works')), hasLength(1));
      expect(out.last, endsWith('and again'));
    });
  });

  group('BootLog failure isolation', () {
    setUp(() => BootLog.printer = (_) => throw StateError('printer failed'));

    test('event, feed and flush never throw when the printer throws', () {
      expect(() => BootLog.event('x'), returnsNormally);
      expect(() => BootLog.feed('t', 'line\n'), returnsNormally);
      BootLog.feed('t', 'pending');
      expect(() => BootLog.flush('t'), returnsNormally);
      expect(BootLog.loggerFailures, greaterThan(0));
    });

    test('mirrors the Util.execute shape: the real exit code survives', () {
      int execute() {
        try {
          const code = 137;
          BootLog.event('shell finished with exit code $code');
          return code;
        } catch (_) {
          return -1;
        }
      }

      expect(execute(), 137);
    });

    test('a failure part-way through a chunk does not re-emit earlier lines',
        () {
      var calls = 0;
      final got = <String>[];
      BootLog.printer = (line) {
        calls++;
        if (calls == 2) throw StateError('second line fails');
        got.add(line);
      };
      BootLog.feed('t', 'one\ntwo\nthree\nrest');
      BootLog.feed('t', '\n');
      final texts = got.map((l) => l.split('] ').last).toList();
      expect(texts.where((t) => t == 'one'), hasLength(1));
      expect(texts, containsAll(['three', 'rest']));
    });

    test('a throwing printer still reaches the attached file', () {
      final dir = Directory.systemTemp.createTempSync('bootlog_iso_');
      addTearDown(() => dir.deleteSync(recursive: true));
      BootLog.attachFile('${dir.path}/boot.log');
      BootLog.event('survives');
      expect(File('${dir.path}/boot.log').readAsStringSync(),
          contains('survives'));
    });

    test('a throwing printer inside the file-disabled notice does not throw',
        () {
      final dir = Directory.systemTemp.createTempSync('bootlog_iso2_');
      addTearDown(() => dir.deleteSync(recursive: true));
      BootLog.attachFile('${dir.path}/no/such/dir/boot.log');
      expect(() => BootLog.event('x'), returnsNormally);
    });
  });

  group('BootLog sessions', () {
    test('attachFile starts a new line budget so a later boot is not silenced',
        () {
      final dir = Directory.systemTemp.createTempSync('bootlog_sess_');
      addTearDown(() => dir.deleteSync(recursive: true));
      BootLog.maxLines = 2;
      BootLog.feed('t', 'a\nb\nc\n');
      expect(out.where((l) => l.contains('log capped')), hasLength(1));
      out.clear();
      BootLog.attachFile('${dir.path}/boot.log');
      BootLog.feed('t', 'd\ne\nf\n');
      expect(out.where((l) => l.contains('[t] d') || l.contains('[t] e')),
          hasLength(2));
      expect(out.where((l) => l.contains('log capped')), hasLength(1),
          reason: 'the new session gets its own notice');
    });
  });

  group('BootLog byte accounting and guard', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bootlog_bytes_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('rollover counts UTF-8 bytes, not UTF-16 units', () {
      final path = '${dir.path}/boot.log';
      BootLog.maxFileBytes = 300;
      BootLog.attachFile(path);
      for (var i = 0; i < 5; i++) {
        BootLog.event('漢' * 30);
      }
      expect(File('$path.1').existsSync(), isTrue);
      expect(File(path).lengthSync(), lessThanOrEqualTo(300));
    });

    test('the unterminated-line guard says how many characters it dropped', () {
      BootLog.maxLineLength = 10;
      BootLog.feed('t', 'z' * 100);
      expect(out.single, contains('[+90 chars dropped]'));
    });

    test('the guard holds 1200 characters and releases at 1201', () {
      BootLog.feed('t', 'a' * 1200);
      expect(out, isEmpty);
      BootLog.feed('t', 'a');
      expect(out, hasLength(1));
      expect(out.single, contains('chars dropped'));
    });

    test('the file-disabled notice names the path', () {
      final path = '${dir.path}/missing-dir/boot.log';
      BootLog.attachFile(path);
      BootLog.event('x');
      expect(out.firstWhere((l) => l.contains('boot log file disabled')),
          contains(path));
    });
  });

  group('BootLog escape stripping', () {
    test('charset selects, bare escapes and an unterminated OSC are removed',
        () {
      BootLog.feed('t', '\x1B(Bhi\n\x1Bcclean\n\x1B]0;never closed\n');
      expect(out.map((l) => l.split('] ').last), ['hi', 'clean']);
    });

    test('a CSI sequence split across chunks is still stripped', () {
      BootLog.feed('t', '\x1B[1;3');
      BootLog.feed('t', '2mok\n');
      expect(out.single, endsWith('[t] ok'));
    });
  });
}
