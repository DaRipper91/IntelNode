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
}
