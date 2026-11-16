import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

void main() {
  List<String> arguments(String options, String containerPath) {
    final command = Workflow.virglServerArguments(options, containerPath);
    final result = Process.runSync('sh', [
      '-c',
      'capture() { printf "%s\\000" "\$@"; }; capture $command',
    ], environment: {
      'CONTAINER_DIR': '/wrong-shell-value'
    });
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).split('\u0000')..removeLast();
  }

  test('the default socket argument contains the concrete container path', () {
    expect(
      arguments(
        r'--use-egl-surfaceless --use-gles --socket-path=$CONTAINER_DIR/tmp/.virgl_test',
        '/data/user/0/intelnode/files/containers/0',
      ),
      [
        '--use-egl-surfaceless',
        '--use-gles',
        '--socket-path=/data/user/0/intelnode/files/containers/0/tmp/.virgl_test',
      ],
    );
  });

  test(
      'expands both supported placeholders after tokenizing and before quoting',
      () {
    const path = r"/root with spaces/quo'te/$HOME;`id`/$(id)";
    expect(
      arguments(
        r'  --socket-path=${CONTAINER_DIR}/tmp/socket  --other=$CONTAINER_DIR/test ',
        path,
      ),
      ['--socket-path=$path/tmp/socket', '--other=$path/test'],
    );
  });

  test('unsupported variables and shell expressions remain literal', () {
    final dir = Directory.systemTemp.createTempSync('virgl_args_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = File('${dir.path}/unexpected');
    final options =
        r'--prefix=$CONTAINER_DIR_SUFFIX --braced=${CONTAINER_DIR_SUFFIX} '
        r'--home=$HOME --command=$(id) --backtick=`id` '
        '--side-effect=;touch\$IFS${marker.path}';
    expect(
      arguments(options, '/actual'),
      [
        r'--prefix=$CONTAINER_DIR_SUFFIX',
        r'--braced=${CONTAINER_DIR_SUFFIX}',
        r'--home=$HOME',
        r'--command=$(id)',
        r'--backtick=`id`',
        '--side-effect=;touch\$IFS${marker.path}',
      ],
    );
    expect(marker.existsSync(), isFalse);
  });

  test('an empty options string produces no server arguments', () {
    expect(Workflow.virglServerArguments('   ', '/container'), isEmpty);
  });
}
