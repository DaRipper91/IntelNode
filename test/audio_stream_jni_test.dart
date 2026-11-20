import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// F4/F19/F20: the JNI symbol names in native-socket.cpp must match the Kotlin
// package + object + `external fun` declarations, or the first native call throws
// UnsatisfiedLinkError at run time (the library still loads, so nothing fails earlier).
// libnative-socket.so is built from source by Gradle (externalNativeBuild -> cmake),
// so fixing the C++ changes the shipped binary; this test checks the source contract
// because the .so itself is only produced by a Gradle/NDK build.
String _jniMangle(String s) => s
    .replaceAll('_', '_1')
    .replaceAll('.', '_');

void main() {
  const kotlinPath =
      'android/app/src/main/kotlin/com/daripper91/daripped/AudioStream.kt';
  const cppPath = 'android/app/src/main/cpp/native-socket.cpp';
  const mainActivityPath =
      'android/app/src/main/kotlin/com/daripper91/daripped/MainActivity.kt';
  final kotlin = File(kotlinPath).readAsStringSync();
  final cpp = File(cppPath).readAsStringSync();
  final mainActivity = File(mainActivityPath).readAsStringSync();

  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true)
      .firstMatch(kotlin)!
      .group(1)!;
  final cls = RegExp(r'^\s*(?:object|class)\s+(\w+)', multiLine: true)
      .firstMatch(kotlin)!
      .group(1)!;
  final natives = RegExp(r'external\s+fun\s+(\w+)\s*\(')
      .allMatches(kotlin)
      .map((m) => m.group(1)!)
      .toList();

  group('F4 JNI symbols match the Kotlin declarations', () {
    test('Kotlin declares the four native functions', () {
      expect(natives,
          unorderedEquals(['nativeInit', 'nativeAccept', 'nativeSend', 'nativeClose']));
    });

    test('every external fun has a matching Java_<pkg>_<class>_<fn> in C++', () {
      for (final fn in natives) {
        final symbol = 'Java_${_jniMangle(pkg)}_${_jniMangle(cls)}_${_jniMangle(fn)}';
        expect(cpp, contains('$symbol('), reason: 'missing $symbol');
      }
    });

    test('every JNI function in C++ corresponds to a Kotlin external fun', () {
      final defined = RegExp(r'\bJava_\w+')
          .allMatches(cpp)
          .map((m) => m.group(0)!)
          .toSet();
      final expected = {
        for (final fn in natives)
          'Java_${_jniMangle(pkg)}_${_jniMangle(cls)}_${_jniMangle(fn)}',
      };
      expect(defined, expected);
      expect(cpp, isNot(contains('com_example')));
    });

    test('the library is built from source by Gradle, not a checked-in prebuilt', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      expect(gradle, contains('externalNativeBuild'));
      expect(gradle, contains('src/main/cpp/CMakeLists.txt'));
      expect(File('android/app/src/main/cpp/CMakeLists.txt').readAsStringSync(),
          contains('add_library(native-socket SHARED native-socket.cpp)'));
      expect(
        Directory('android/app/src/main/jniLibs')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.contains('native-socket')),
        isEmpty,
      );
    });
  });

  group('F19 MainActivity audio channel', () {
    test('startStreaming and stopStreaming reply to Dart', () {
      final start = mainActivity.substring(
        mainActivity.indexOf('"startStreaming" ->'),
        mainActivity.indexOf('"stopStreaming" ->'),
      );
      expect(start, contains('result.success'));
      expect(start, contains('result.error'));
      final stop = mainActivity.substring(
        mainActivity.indexOf('"stopStreaming" ->'),
        mainActivity.indexOf('else ->'),
      );
      expect(stop, contains('result.success'));
    });

    test('no non-null assertion remains in the Kotlin/Java sources', () {
      for (final f in Directory('android/app/src/main')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt') || f.path.endsWith('.java'))) {
        expect(f.readAsStringSync().contains('!!'), isFalse, reason: f.path);
      }
    });

    test('TERMUX_X11_DEBUG is only set in debug builds', () {
      final idx = mainActivity.indexOf('"TERMUX_X11_DEBUG"');
      expect(idx, greaterThan(0));
      expect(mainActivity.substring(idx - 120, idx), contains('BuildConfig.DEBUG'));
    });
  });

  group('F20 AudioStream state handling', () {
    test('isStreaming is volatile and reset in a finally block', () {
      expect(kotlin, matches(RegExp(r'@Volatile\s+private var isStreaming')));
      expect(kotlin, contains('finally {'));
      expect(kotlin.substring(kotlin.indexOf('finally {')),
          contains('isStreaming = false'));
    });

    test('buffer size and recorder state are validated', () {
      expect(kotlin, contains('bufferSize <= 0'));
      expect(kotlin, contains('STATE_INITIALIZED'));
    });

    test('native library load failure is contained', () {
      expect(kotlin, contains('catch (t: Throwable)'));
      expect(kotlin, contains('nativeLoaded'));
    });

    test('C++ includes <cstring> and releases the UTF chars on failure paths', () {
      expect(cpp, contains('#include <cstring>'));
      // one release per return path of nativeInit (socket, bind, listen, success)
      expect('ReleaseStringUTFChars'.allMatches(cpp).length, greaterThanOrEqualTo(4));
      expect(cpp, contains('std::mutex'));
    });
  });
}
