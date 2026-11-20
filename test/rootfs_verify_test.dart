import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

// Drives ContainerInstaller.installBase with a mock HTTP client and a real `sh`
// for the checksum and cleanup scripts. Only the proot-based steps (extract,
// provisioning, finalize, boot check) are faked, because proot does not exist
// on the test host.
void main() {
  late Directory dir;
  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('rootfs_verify_');
    G.dataPath = dir.path;
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  setUp(() {
    for (final e in dir.listSync()) {
      e.deleteSync(recursive: true);
    }
    Directory('${dir.path}/bin').createSync();
    // Like the real dynamic busybox, refuses to start without LD_LIBRARY_PATH.
    File('${dir.path}/bin/busybox').writeAsStringSync(
      '#!/bin/sh\n[ "\$LD_LIBRARY_PATH" = "${dir.path}/lib" ] || '
      '{ echo "CANNOT LINK EXECUTABLE" >&2; exit 1; }\n"\$@"\n',
    );
    Process.runSync('chmod', ['+x', '${dir.path}/bin/busybox']);
  });

  const good = 'good rootfs bytes';
  const other = 'other rootfs bytes';
  String sha256Of(String content) {
    final f = File('${dir.path}/hash_input')..writeAsStringSync(content);
    final out = Process.runSync('sha256sum', [f.path]).stdout.toString();
    f.deleteSync();
    return out.split(' ').first;
  }

  String md5Of(String content) {
    final f = File('${dir.path}/hash_input')..writeAsStringSync(content);
    final out = Process.runSync('md5sum', [f.path]).stdout.toString();
    f.deleteSync();
    return out.split(' ').first;
  }

  // Serves each URL's body; records GETs of tarballs (host + Range header).
  http.Client server(Map<String, String> bodies,
      {Map<String, int> headStatus = const {}, List<String>? log}) {
    return MockClient((req) async {
      final key = req.url.toString();
      if (req.method == 'HEAD') {
        return http.Response('', headStatus[req.url.host] ?? 200);
      }
      log?.add('${req.method} $key range=${req.headers['Range']}');
      final body = bodies[key];
      if (body == null) return http.Response('not found', 404);
      return http.Response(body, 200);
    });
  }

  // Runs checksum/cleanup scripts for real; pretends the proot steps and the
  // finalize move succeed.
  // [prootExit] lets a test make the extraction fail.
  Future<int> Function(String) runner(List<String> ran, {int prootExit = 0}) =>
      (script) async {
        ran.add(script);
        if (script.contains('bin/proot')) return prootExit;
        if (script.contains('\nmv ')) return 0; // finalize swaps dirs that were never built
        return Process.runSync('sh', ['-c', script]).exitCode;
      };

  RootfsSource pinned(String url, String hash, {List<String> fallbacks = const []}) =>
      RootfsSource.direct(
        url: url,
        fallbackUrls: fallbacks,
        sha256: {url: hash},
        verified: true,
      );

  DistroSpec spec(String id, RootfsSource rootfs) => DistroSpec(
        id: id,
        displayName: id,
        description: '',
        packageManager: PackageManagerFamily.apk,
        rootfs: rootfs,
        firstBootScript: (_) => 'true',
      );

  Future<void> install(DistroSpec d, http.Client c, List<String> ran,
          {int prootExit = 0}) =>
      ContainerInstaller.installBase(
        distro: d,
        containerIndex: 0,
        run: runner(ran, prootExit: prootExit),
        log: (_) {},
        onProgress: (_) {},
        client: c,
      );

  List<String> partials() => dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.startsWith('new_rootfs_'))
      .toList();

  test('a correct pinned hash passes and the tarball is kept under its pin name', () async {
    const url = 'https://a.test/fedora.tar.xz';
    final hash = sha256Of(good);
    final ran = <String>[];
    await install(spec('a', pinned(url, hash)), server({url: good}), ran);
    expect(ran.any((s) => s.contains('checksum ok')), isTrue);
    expect(ran.any((s) => s.contains('-xJpf')), isTrue, reason: 'xz tar flag from the URL path');
    expect(partials(), ['new_rootfs_${hash.substring(0, 16)}.tar']);
  });

  test('a wrong hash aborts and deletes the partial', () async {
    const url = 'https://a.test/fedora.tar.xz';
    final wrong = sha256Of(other);
    final ran = <String>[];
    await expectLater(
      install(spec('a', pinned(url, wrong)), server({url: good}), ran),
      throwsA(predicate((e) => e.toString().contains('Checksum mismatch'))),
    );
    expect(partials(), isEmpty);
    expect(ran.any((s) => s.contains('-xJpf')), isFalse, reason: 'must not extract');
  });

  test('a download with no pin and no scheme is refused before any download', () async {
    const url = 'https://a.test/fedora.tar.xz';
    final log = <String>[];
    final ran = <String>[];
    await expectLater(
      install(
        spec('a', const RootfsSource.direct(url: url, verified: true)),
        server({url: good}, log: log),
        ran,
      ),
      throwsA(isA<StateError>()),
    );
    expect(log, isEmpty, reason: 'no GET may be issued');
    expect(partials(), isEmpty);
  });

  test('an unknown archive type is refused before any download', () async {
    const url = 'https://a.test/fedora.tar.zst';
    final log = <String>[];
    await expectLater(
      install(spec('a', pinned(url, 'a' * 64)), server({url: good}, log: log), []),
      throwsA(isA<StateError>()),
    );
    expect(log, isEmpty);
  });

  test('a partial named for one source is not reused for another', () async {
    const urlB = 'https://b.test/alpine.tar.xz';
    final hashA = sha256Of(other);
    final hashB = sha256Of(good);
    // A failed attempt for A left half of A's bytes behind under A's name.
    final stale = File('${dir.path}/new_rootfs_${hashA.substring(0, 16)}.tar')
      ..writeAsStringSync('half of A');
    final log = <String>[];
    await install(spec('b', pinned(urlB, hashB)), server({urlB: good}, log: log), []);
    expect(log, ['GET $urlB range=null'],
        reason: 'B must start from zero, not resume A\'s bytes');
    expect(stale.readAsStringSync(), 'half of A', reason: 'A\'s partial is untouched');
    expect(partials().toSet(), {
      'new_rootfs_${hashA.substring(0, 16)}.tar',
      'new_rootfs_${hashB.substring(0, 16)}.tar',
    });
  });

  test('an unpinned source keeps its partial apart per URL', () async {
    const urlA = 'https://a.test/x.tar.gz';
    const urlB = 'https://b.test/x.tar.gz';
    expect(
      ContainerInstaller.tarballPathFor(dir.path, urlA),
      isNot(ContainerInstaller.tarballPathFor(dir.path, urlB)),
    );
  });

  test('a mirror\'s md5 comes from the first listed origin, not the serving mirror', () async {
    const first = 'https://first.test/os/Arch-latest.tar.gz';
    const second = 'https://second.test/os/Arch-latest.tar.gz';
    final log = <String>[];
    final c = server(
      {
        '$first.md5': '${md5Of(good)}  Arch-latest.tar.gz\n',
        // A rogue fallback that vouches for itself with a different hash.
        '$second.md5': '${md5Of(other)}  Arch-latest.tar.gz\n',
        second: good,
      },
      headStatus: {'first.test': 503},
      log: log,
    );
    final src = const RootfsSource.direct(
      url: first,
      fallbackUrls: [second],
      checksumKind: ChecksumKind.md5Sidecar,
      verified: true,
    );
    await install(spec('arch', src), c, []);
    expect(log.any((l) => l.contains('GET $first.md5')), isTrue);
    expect(log.any((l) => l.contains('GET $second.md5')), isFalse);
  });

  test('a mirror whose bytes disagree with the first origin\'s md5 is rejected', () async {
    const first = 'https://first.test/os/Arch-latest.tar.gz';
    const second = 'https://second.test/os/Arch-latest.tar.gz';
    final c = server(
      {'$first.md5': '${md5Of(good)}  Arch-latest.tar.gz\n', second: other},
      headStatus: {'first.test': 503},
    );
    final src = const RootfsSource.direct(
      url: first,
      fallbackUrls: [second],
      checksumKind: ChecksumKind.md5Sidecar,
      verified: true,
    );
    await expectLater(
      install(spec('arch', src), c, []),
      throwsA(predicate((e) => e.toString().contains('Checksum mismatch'))),
    );
    expect(partials(), isEmpty);
  });

  test('a checksum-tool failure keeps the download (exit 2)', () async {
    const url = 'https://a.test/fedora.tar.xz';
    File('${dir.path}/bin/busybox').writeAsStringSync('#!/bin/sh\nexit 1\n');
    await expectLater(
      install(spec('a', pinned(url, sha256Of(good))), server({url: good}), []),
      throwsA(predicate((e) => e.toString().contains('download was kept'))),
    );
    expect(partials(), hasLength(1));
  });
}
