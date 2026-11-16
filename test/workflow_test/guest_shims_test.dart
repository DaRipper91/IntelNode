import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/guest_shims.dart';

void main() {
  late Directory dir;
  late String bwrap;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('shim_');
    GuestShims.writeTo(dir.path);
    bwrap = GuestShims.bwrapPath(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProcessResult run(List<String> args) => Process.runSync(bwrap, args);

  test('writeTo creates an executable script', () {
    expect(File(bwrap).readAsStringSync(), startsWith('#!/bin/bash'));
    expect(FileStat.statSync(bwrap).mode & 0x40, isNot(0), reason: 'owner execute bit');
  });

  test('ignores the sandbox options glycin passes and runs the command', () {
    final r = run([
      '--unshare-all', '--die-with-parent', '--chdir', '/', '--ro-bind', '/usr', '/usr',
      '--dev', '/dev', '--ro-bind-try', '/etc/ld.so.cache', '/etc/ld.so.cache',
      '--tmpfs', '/tmp-home', '--symlink', '/usr/lib', '/lib', '--seccomp', '12',
      '--', '/bin/echo', 'loader-ran', '--not-an-option',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout.toString().trim(), 'loader-ran --not-an-option');
  });

  test('applies --clearenv and --setenv', () {
    final r = run([
      '--clearenv', '--setenv', 'HOME', '/tmp-home', '--setenv', 'FOO', 'bar',
      '--', '/usr/bin/env',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final out = r.stdout.toString();
    expect(out, contains('FOO=bar'));
    expect(out, contains('HOME=/tmp-home'));
    expect(out, isNot(contains('PATH=')), reason: 'clearenv removed the inherited environment');
  });

  test('applies --chdir and propagates the exit status', () {
    final r = run(['--chdir', '/tmp', '--', '/bin/sh', '-c', 'pwd; exit 7']);
    expect(r.stdout.toString().trim(), '/tmp');
    expect(r.exitCode, 7);
  });
}
