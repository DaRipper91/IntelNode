import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/distros.dart';

// Rolling files that cannot be pinned; they must name a sidecar scheme instead.
const _rolling = {
  'https://fl.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz',
  'https://ca.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz',
  'https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz',
  'https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz',
};

List<String> _fixedUrls(RootfsSource s) =>
    [s.directUrl!, ...s.fallbackUrls].where((u) => !_rolling.contains(u)).toList();

void main() {
  final direct = Distros.all
      .where((d) => d.rootfs.kind == RootfsSourceKind.direct)
      .toList();

  group('pinned rootfs hashes (S3)', () {
    test('every pin is exactly 64 lowercase hex', () {
      final hex = RegExp(r'^[0-9a-f]{64}$');
      for (final d in direct) {
        for (final e in d.rootfs.sha256.entries) {
          expect(hex.hasMatch(e.value), isTrue, reason: '${d.id} ${e.key}');
        }
      }
    });

    test('every fixed versioned URL has a pin', () {
      for (final d in direct) {
        for (final u in _fixedUrls(d.rootfs)) {
          expect(d.rootfs.sha256.containsKey(u), isTrue, reason: '${d.id}: $u');
        }
      }
    });

    test('every pin is keyed by a URL the source can actually use', () {
      for (final d in direct) {
        final urls = {d.rootfs.directUrl!, ...d.rootfs.fallbackUrls};
        for (final k in d.rootfs.sha256.keys) {
          expect(urls, contains(k), reason: '${d.id}: $k');
        }
      }
    });

    test('rolling URLs are not pinned and name a sidecar scheme instead', () {
      for (final d in direct) {
        final rolling = [d.rootfs.directUrl!, ...d.rootfs.fallbackUrls]
            .where(_rolling.contains);
        if (rolling.isEmpty) continue;
        expect(d.rootfs.checksumKind, isNot(ChecksumKind.none), reason: d.id);
        for (final u in rolling) {
          expect(d.rootfs.sha256.containsKey(u), isFalse, reason: u);
        }
      }
    });

    test('no distro can reach a URL that has neither a pin nor a scheme', () {
      for (final d in direct) {
        for (final u in [d.rootfs.directUrl!, ...d.rootfs.fallbackUrls]) {
          expect(() => ContainerInstaller.checksumSource(d.rootfs, u), returnsNormally,
              reason: '${d.id}: $u');
        }
      }
    });

    test('Ubuntu prefers the pinned dated directory over the rolling one', () {
      final u = Distros.byId('ubuntu').rootfs;
      expect(u.directUrl, contains('/release-'));
      expect(u.sha256.containsKey(u.directUrl), isTrue);
    });
  });

  group('checksumSource (S4)', () {
    RootfsSource src(String url,
            {List<String> fallbacks = const [],
            Map<String, String> pins = const {},
            ChecksumKind kind = ChecksumKind.none}) =>
        RootfsSource.direct(
          url: url,
          fallbackUrls: fallbacks,
          sha256: pins,
          checksumKind: kind,
          verified: true,
        );

    test('a pin wins over the sidecar scheme', () {
      final pin = 'a' * 64;
      final s = ContainerInstaller.checksumSource(
        src('https://h.test/x.tar.xz',
            pins: {'https://h.test/x.tar.xz': pin}, kind: ChecksumKind.md5Sidecar),
        'https://h.test/x.tar.xz',
      );
      expect(s.pinnedSha256, pin);
      expect(s.sumsUrl, isNull);
    });

    test('an unpinned URL with no scheme is refused (fail closed)', () {
      expect(
        () => ContainerInstaller.checksumSource(
            src('https://h.test/x.tar.xz'), 'https://h.test/x.tar.xz'),
        throwsA(isA<StateError>()),
      );
    });

    test('the substring archlinuxarm.org in a path or query does not pick md5', () {
      for (final u in [
        'https://evil.test/archlinuxarm.org/x.tar.gz',
        'https://evil.test/x.tar.gz?h=archlinuxarm.org',
        'https://evil.test/cloud-images.ubuntu.com/x.tar.xz',
      ]) {
        expect(() => ContainerInstaller.checksumSource(src(u), u),
            throwsA(isA<StateError>()),
            reason: u);
      }
    });

    test('md5 sidecar for a fallback mirror is fetched from the first mirror', () {
      final s = src(
        'https://first.test/os/Arch-latest.tar.gz',
        fallbacks: ['https://second.test/os/Arch-latest.tar.gz'],
        kind: ChecksumKind.md5Sidecar,
      );
      final viaFallback =
          ContainerInstaller.checksumSource(s, 'https://second.test/os/Arch-latest.tar.gz');
      expect(viaFallback.sumsUrl, 'https://first.test/os/Arch-latest.tar.gz.md5');
      expect(viaFallback.tool, 'md5sum');
      expect(Uri.parse(viaFallback.sumsUrl!).host,
          isNot(Uri.parse('https://second.test/').host));
    });

    test('a differently named fallback keeps its own sidecar', () {
      final s = src(
        'https://first.test/os/Arch-latest.tar.gz',
        fallbacks: ['https://second.test/os/Other.tar.gz'],
        kind: ChecksumKind.md5Sidecar,
      );
      expect(
        ContainerInstaller.checksumSource(s, 'https://second.test/os/Other.tar.gz').sumsUrl,
        'https://second.test/os/Other.tar.gz.md5',
      );
    });

    test('SHA256SUMS sits next to the tarball and ignores the query string', () {
      final s = src('https://h.test/d/root.tar.xz?x=1', kind: ChecksumKind.sha256Sums);
      final r = ContainerInstaller.checksumSource(s, 'https://h.test/d/root.tar.xz?x=1');
      expect(r.sumsUrl, 'https://h.test/d/SHA256SUMS');
      expect(r.tool, 'sha256sum');
    });

    test('the real Arch fallbacks take their md5 from the first listed mirror', () {
      final s = Distros.byId('archlinux').rootfs;
      for (final u in s.fallbackUrls) {
        final r = ContainerInstaller.checksumSource(s, u);
        expect(Uri.parse(r.sumsUrl!).host, Uri.parse(s.directUrl!).host);
        expect(Uri.parse(r.sumsUrl!).host, isNot(Uri.parse(u).host));
      }
    });
  });

  group('tarFlagForUrl (S4)', () {
    test('maps known archive types', () {
      expect(ContainerInstaller.tarFlagForUrl('https://h.test/a.tar.xz'), 'J');
      expect(ContainerInstaller.tarFlagForUrl('https://h.test/a.tar.gz'), 'z');
      expect(ContainerInstaller.tarFlagForUrl('https://h.test/a.tgz'), 'z');
      expect(ContainerInstaller.tarFlagForUrl('https://h.test/a.tar.bz2'), 'j');
    });

    test('the extension is read from the path, not the query', () {
      expect(ContainerInstaller.tarFlagForUrl('https://h.test/a.tar.xz?f=x.tar.gz'), 'J');
      expect(
          () => ContainerInstaller.tarFlagForUrl('https://h.test/a?f=x.tar.xz'),
          throwsA(isA<StateError>()));
    });

    test('unknown or bare archives raise instead of defaulting to gzip', () {
      for (final u in [
        'https://h.test/a.tar.zst',
        'https://h.test/a.tar',
        'https://h.test/a.zip',
      ]) {
        expect(() => ContainerInstaller.tarFlagForUrl(u), throwsA(isA<StateError>()),
            reason: u);
      }
    });

    test('every URL in the manifest has a known archive type', () {
      for (final d in direct) {
        for (final u in [d.rootfs.directUrl!, ...d.rootfs.fallbackUrls]) {
          expect(() => ContainerInstaller.tarFlagForUrl(u), returnsNormally, reason: u);
        }
      }
    });
  });

  group('tarballPathFor (F9)', () {
    test('two URLs produce different partial paths', () {
      final a = ContainerInstaller.tarballPathFor('/d', 'https://h.test/fedora.tar.xz');
      final b = ContainerInstaller.tarballPathFor('/d', 'https://h.test/alpine.tar.xz');
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^/d/new_rootfs_[0-9a-f]{16}\.tar$')));
    });

    test('is stable for the same URL', () {
      expect(ContainerInstaller.tarballPathFor('/d', 'https://h.test/x'),
          ContainerInstaller.tarballPathFor('/d', 'https://h.test/x'));
    });

    test('is named by the first 16 hex of the pin when there is one', () {
      expect(
        ContainerInstaller.tarballPathFor('/d', 'https://h.test/x',
            pinnedSha256: 'abcdef0123456789${'0' * 48}'),
        '/d/new_rootfs_abcdef0123456789.tar',
      );
    });

    test('every pinned URL in the manifest gets its own partial name', () {
      final names = <String>{};
      var count = 0;
      for (final d in direct) {
        for (final e in d.rootfs.sha256.entries) {
          names.add(ContainerInstaller.tarballPathFor('/d', e.key, pinnedSha256: e.value));
          count++;
        }
      }
      expect(names.length, count);
    });
  });
}
