import 'package:flutter_test/flutter_test.dart';
import 'package:da_ripped_tiny_computer/models.dart';

void main() {
  group('CommandInfo Tests', () {
    test('CommandInfo.fromJson should create object from valid JSON', () {
      final json = {'name': 'test_name', 'command': 'test_command'};
      final commandInfo = CommandInfo.fromJson(json);

      expect(commandInfo.name, 'test_name');
      expect(commandInfo.command, 'test_command');
    });

    test('CommandInfo.toJson should return correct JSON map', () {
      final commandInfo = CommandInfo(name: 'test_name', command: 'test_command');
      final json = commandInfo.toJson();

      expect(json['name'], 'test_name');
      expect(json['command'], 'test_command');
      expect(json.length, 2);
    });
  });

  group('ContainerInfo Tests', () {
    test('ContainerInfo.fromJson should create object with all fields', () {
      final json = {
        'name': 'Arch Linux',
        'boot': 'start-arch',
        'vnc': 'vnc-server',
        'vncPassword': 'password123',
        'vncUrl': 'http://localhost:5901',
        'vncUri': 'vnc://localhost:5901',
        'commands': [
          {'name': 'Update', 'command': 'pacman -Syu'}
        ],
      };
      final containerInfo = ContainerInfo.fromJson(json);

      expect(containerInfo.name, 'Arch Linux');
      expect(containerInfo.boot, 'start-arch');
      expect(containerInfo.vnc, 'vnc-server');
      expect(containerInfo.vncPassword, 'password123');
      expect(containerInfo.vncUrl, 'http://localhost:5901');
      expect(containerInfo.vncUri, 'vnc://localhost:5901');
      expect(containerInfo.commands.length, 1);
      expect(containerInfo.commands[0]['name'], 'Update');
    });

    test('ContainerInfo.fromJson should apply default values for missing fields', () {
      final json = <String, dynamic>{};
      final containerInfo = ContainerInfo.fromJson(json);

      expect(containerInfo.name, 'Debian Trixie');
      expect(containerInfo.boot, '');
      expect(containerInfo.vnc, 'startnovnc &');
      expect(containerInfo.vncPassword, '');
      expect(containerInfo.vncUrl, '');
      expect(containerInfo.vncUri, '');
      expect(containerInfo.commands, isEmpty);
      expect(containerInfo.additionalProps, isEmpty);
    });

    test('ContainerInfo.fromJson should preserve unknown fields in additionalProps', () {
      final json = {
        'name': 'Custom Container',
        'custom_key': 'custom_value',
        'nested': {'key': 'val'}
      };
      final containerInfo = ContainerInfo.fromJson(json);

      expect(containerInfo.name, 'Custom Container');
      expect(containerInfo.additionalProps['custom_key'], 'custom_value');
      expect(containerInfo.additionalProps['nested']['key'], 'val');
    });

    test('ContainerInfo.toJson should return correct JSON map including additionalProps', () {
      final containerInfo = ContainerInfo(
        name: 'My OS',
        boot: 'boot.sh',
        vnc: 'vnc.sh',
        vncPassword: 'pass',
        vncUrl: 'url',
        vncUri: 'uri',
        commands: [],
        additionalProps: {'extra': 'data'},
      );

      final json = containerInfo.toJson();

      expect(json['name'], 'My OS');
      expect(json['extra'], 'data');
      expect(json.length, 8); // 7 known keys + 1 extra
    });

    test('ContainerInfo property methods should handle known and unknown keys', () {
      final containerInfo = ContainerInfo(
        name: 'Test',
        boot: 'boot',
        vnc: 'vnc',
        vncPassword: 'pass',
        vncUrl: 'url',
        vncUri: 'uri',
        commands: [],
        additionalProps: {'custom': 'initial'},
      );

      // hasProp
      expect(containerInfo.hasProp('name'), isTrue);
      expect(containerInfo.hasProp('custom'), isTrue);
      expect(containerInfo.hasProp('nonexistent'), isFalse);

      // getProp
      expect(containerInfo.getProp('name'), 'Test');
      expect(containerInfo.getProp('custom'), 'initial');
      expect(containerInfo.getProp('nonexistent'), isNull);

      // setProp
      containerInfo.setProp('name', 'Updated Name');
      containerInfo.setProp('custom', 'updated value');
      containerInfo.setProp('new_prop', 'new value');

      expect(containerInfo.name, 'Updated Name');
      expect(containerInfo.additionalProps['custom'], 'updated value');
      expect(containerInfo.additionalProps['new_prop'], 'new value');
      expect(containerInfo.hasProp('new_prop'), isTrue);
    });
  });
}
