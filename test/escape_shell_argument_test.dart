import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  group('Util.escapeShellArgument', () {
    test('escapes empty string', () {
      expect(Util.escapeShellArgument(''), "''");
    });

    test('escapes normal string', () {
      expect(Util.escapeShellArgument('hello'), "'hello'");
    });

    test('escapes string with spaces', () {
      expect(Util.escapeShellArgument('hello world'), "'hello world'");
    });

    test('escapes string with single quotes', () {
      expect(Util.escapeShellArgument("hello'world"), "'hello'\\''world'");
    });

    test('escapes string with special characters', () {
      expect(Util.escapeShellArgument('--opt=val; rm -rf /'), "'--opt=val; rm -rf /'");
    });
  });
}
