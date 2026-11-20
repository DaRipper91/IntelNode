import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

// S14: the HiDPI / VirGL / Turnip option strings are user-edited and end up on
// the boot line; they must stay data.
void main() {
  List<String> tokens(String options) {
    final args = Workflow.envAssignmentArguments(options);
    final result = Process.runSync('sh', [
      '-c',
      'capture() { printf "%s\\000" "\$@"; }; capture $args',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).split('\u0000')..removeLast();
  }

  test('the shipped defaults pass through unchanged', () {
    expect(tokens('GDK_SCALE=2 QT_FONT_DPI=192'), ['GDK_SCALE=2', 'QT_FONT_DPI=192']);
    expect(tokens('GALLIUM_DRIVER=virpipe'), ['GALLIUM_DRIVER=virpipe']);
    expect(
      tokens('MESA_LOADER_DRIVER_OVERRIDE=zink '
          'VK_ICD_FILENAMES=/home/tiny/.local/share/tiny/extra/freedreno_icd.aarch64.json '
          'TU_DEBUG=noconform'),
      [
        'MESA_LOADER_DRIVER_OVERRIDE=zink',
        'VK_ICD_FILENAMES=/home/tiny/.local/share/tiny/extra/freedreno_icd.aarch64.json',
        'TU_DEBUG=noconform',
      ],
    );
  });

  test('extra whitespace and an empty string produce no stray arguments', () {
    expect(tokens('  A=1 \t B=2\n'), ['A=1', 'B=2']);
    expect(Workflow.envAssignmentArguments(''), isEmpty);
    expect(Workflow.envAssignmentArguments('   '), isEmpty);
  });

  test('quotes, semicolons and command substitution stay literal and run nothing', () {
    final dir = Directory.systemTemp.createTempSync('envopt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = '${dir.path}/pwned';
    final options = "A='x B=\"y C=\$(touch $marker) D=`touch $marker` "
        "E=1;touch\$IFS$marker F=a'b G=\$HOME";
    expect(tokens(options), [
      "A='x",
      'B="y',
      r'C=$(touch',
      r'D=`touch',
      'E=1;touch\$IFS$marker',
      "F=a'b",
      r'G=$HOME',
    ]);
    expect(File(marker).existsSync(), isFalse);
  });

  test('a token that is not NAME=value is dropped instead of becoming the env command', () {
    expect(tokens('rm -rf / A=1 =x 9B=2 ok_1=v'), ['A=1', 'ok_1=v']);
  });

  test('a value is passed as one argument even when it contains shell syntax', () {
    final dir = Directory.systemTemp.createTempSync('envopt2_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = '${dir.path}/pwned';
    // No whitespace inside the value, so it survives tokenizing as one token.
    final out = tokens('A=\$(touch\${IFS}$marker) B=x;touch\${IFS}$marker C=`id` D=\$HOME');
    expect(out.length, 4);
    expect(out[3], r'D=$HOME');
    expect(File(marker).existsSync(), isFalse);
  });
}
