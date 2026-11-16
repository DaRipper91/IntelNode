import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:da_ripped_tiny_computer/workflow.dart';

/// A server that serves [body], optionally cutting the first [dropAfter] bytes
/// response short with an error and optionally ignoring Range.
class FakeServer extends http.BaseClient {
  FakeServer(this.body, {this.dropFirstAfter, this.ignoreRange = false, this.status});
  final List<int> body;
  final int? dropFirstAfter;
  final bool ignoreRange;
  final int? status;
  final List<String?> rangeHeaders = [];
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    rangeHeaders.add(request.headers['Range']);
    if (status != null) {
      return http.StreamedResponse(const Stream.empty(), status!);
    }
    var start = 0;
    var code = 200;
    final range = request.headers['Range'];
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= body.length) {
        return http.StreamedResponse(const Stream.empty(), 416,
            headers: {'content-range': 'bytes */${body.length}'});
      }
      code = 206;
    }
    final slice = body.sublist(start);
    final drop = calls == 1 ? dropFirstAfter : null;
    Stream<List<int>> stream;
    if (drop != null) {
      stream = () async* {
        yield slice.sublist(0, drop);
        throw const SocketException('Connection closed while receiving data');
      }();
    } else {
      stream = Stream.value(slice);
    }
    return http.StreamedResponse(stream, code, contentLength: slice.length);
  }
}

void main() {
  late Directory dir;
  late String dest;
  final body = utf8.encode('0123456789' * 1000);
  setUp(() {
    dir = Directory.systemTemp.createTempSync('dl_');
    dest = '${dir.path}/file.tar';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> run(FakeServer s, {int attempts = 5, List<String>? log}) =>
      Util.downloadFile('https://example.test/f', dest,
          onProgress: (m) => log?.add(m),
          client: s,
          maxAttempts: attempts,
          retryDelay: Duration.zero);

  test('plain download writes the whole body', () async {
    await run(FakeServer(body));
    expect(File(dest).readAsBytesSync(), body);
  });

  test('resumes with a Range request after the connection drops mid-body', () async {
    final s = FakeServer(body, dropFirstAfter: 3000);
    final log = <String>[];
    await run(s, log: log);
    expect(File(dest).readAsBytesSync(), body);
    expect(s.calls, 2);
    expect(s.rangeHeaders[1], 'bytes=3000-');
    expect(log.any((m) => m.startsWith('Connection lost')), isTrue);
  });

  test('restarts from zero when the server ignores Range', () async {
    final s = FakeServer(body, dropFirstAfter: 3000, ignoreRange: true);
    await run(s);
    expect(File(dest).readAsBytesSync(), body);
  });

  test('an already complete file on disk is accepted via 416, not re-downloaded', () async {
    File(dest).writeAsBytesSync(body);
    final s = FakeServer(body);
    await run(s);
    expect(s.calls, 1);
    expect(File(dest).readAsBytesSync(), body);
  });

  test('a stale file longer than the server copy is discarded and re-downloaded', () async {
    File(dest).writeAsBytesSync([...body, ...body]);
    final s = FakeServer(body);
    await run(s);
    expect(File(dest).readAsBytesSync(), body);
    expect(s.calls, 2);
  });

  test('does not retry a 404', () async {
    final s = FakeServer(body, status: 404);
    await expectLater(run(s), throwsA(isA<DownloadHttpException>()));
    expect(s.calls, 1);
  });

  test('retries a 503 and gives up after maxAttempts', () async {
    final s = FakeServer(body, status: 503);
    await expectLater(run(s, attempts: 3), throwsA(isA<DownloadHttpException>()));
    expect(s.calls, 3);
  });
}
