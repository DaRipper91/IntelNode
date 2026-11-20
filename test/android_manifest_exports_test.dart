import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Returns the text of the first manifest element (`<tag ... >`) that declares
/// `android:name="<name>"`, so assertions stay scoped to one component.
String _component(String manifest, String tag, String name) {
  final start = manifest.indexOf(RegExp('<$tag\\b[^>]*android:name="$name"'));
  expect(start, isNonNegative, reason: '<$tag android:name="$name"> not found');
  return manifest.substring(start, manifest.indexOf('>', start) + 1);
}

void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  group('exported components', () {
    test('keyboard receiver is not exported (guest/shell cannot broadcast to it)',
        () {
      final receiver = _component(manifest, 'receiver', '.X11KeyboardReceiver');
      expect(receiver, contains('android:exported="false"'));
      expect(receiver, isNot(contains('android:exported="true"')));
    });

    test('Signal9Activity is only started explicitly by the app', () {
      final activity = _component(manifest, 'activity', '.Signal9Activity');
      expect(activity, contains('android:exported="false"'));
    });

    test('documents provider stays gated by MANAGE_DOCUMENTS', () {
      final provider = _component(manifest, 'provider',
          'com.daripper91.daripped.filepicker.TinyDocumentsProvider');
      expect(provider,
          contains('android:permission="android.permission.MANAGE_DOCUMENTS"'));
    });
  });

  group('X11KeyboardReceiver socket bounds', () {
    final source = File(
            'android/app/src/main/kotlin/com/daripper91/daripped/X11KeyboardReceiver.kt')
        .readAsStringSync();

    test('stays loopback-only and sets reuseAddress before bind', () {
      expect(source, contains('InetAddress.getByName("127.0.0.1")'));
      final reuse = source.indexOf('reuseAddress = true');
      final bind = source.indexOf('bind(InetSocketAddress');
      expect(reuse, isNonNegative);
      expect(bind, greaterThan(reuse));
    });

    test('caps line length, read time and concurrent clients', () {
      expect(source, contains('MAX_LINE_CHARS'));
      expect(source, contains('READ_TIMEOUT_MS'));
      expect(source, contains('MAX_CONCURRENT_CLIENTS'));
      expect(source, isNot(contains('reader.readLine()')));
    });
  });

  group('TinyDocumentsProvider confinement', () {
    const dir = 'android/app/src/main/java/com/daripper91/daripped';
    final provider = File('$dir/TinyDocumentsProvider.java').readAsStringSync();

    test('no raw string-prefix containment or fail-open search', () {
      expect(provider, isNot(contains('documentId.startsWith(parentDocumentId)')));
      expect(provider, isNot(contains('new File(parentDocumentId, displayName)')));
      expect(provider, contains('DocumentPathGuard.sanitizeDisplayName'));
      expect(provider, contains('DocumentPathGuard.isChild'));
      // The search IOException fallback must deny, not allow.
      expect(provider, contains('isInsideHome = false;'));
      expect(provider, isNot(contains('isInsideHome = true;')));
    });

    test('listFiles() results are null-checked', () {
      expect(provider, contains('if (children == null) return result;'));
      expect(provider, contains('if (children != null) Collections.addAll'));
    });
  });
}
