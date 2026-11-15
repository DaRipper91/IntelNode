import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Util.copyAssetsSequentially', () {
    test('never runs two copies at once and preserves sorted order', () async {
      var running = 0;
      var maxRunning = 0;
      final order = <String>[];

      await Util.copyAssetsSequentially(['xac', 'xaa', 'xab'], (name) async {
        running++;
        maxRunning = running > maxRunning ? running : maxRunning;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add(name);
        running--;
      });

      expect(maxRunning, 1);
      expect(order, ['xaa', 'xab', 'xac']);
    });

    test('does not mutate the caller list and handles empty input', () async {
      final input = ['b', 'a'];
      await Util.copyAssetsSequentially(input, (_) async {});
      expect(input, ['b', 'a']);
      await Util.copyAssetsSequentially(const [], (_) async => fail('no calls'));
    });

    test('stops at the first failure instead of continuing', () async {
      final seen = <String>[];
      await expectLater(
        Util.copyAssetsSequentially(['a', 'b', 'c'], (name) async {
          seen.add(name);
          if (name == 'b') throw StateError('disk full');
        }),
        throwsStateError,
      );
      expect(seen, ['a', 'b']);
    });
  });
}
