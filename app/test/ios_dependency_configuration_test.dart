import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool atLeast(String actual, String required) {
  final a = actual.split('.').map(int.parse).toList();
  final b = required.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left > right;
  }
  return true;
}

void main() {
  test('Runner deployment floor supports the resolved native file picker', () {
    // Read the actual resolved package, not a copied minimum-version constant.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
    final picker = packages.cast<Map>().singleWhere(
      (p) => p['name'] == 'file_picker_darwin',
    );
    final root = Directory.fromUri(
      config.uri.resolve(picker['rootUri'] as String),
    ).uri;
    final manifest = File.fromUri(
      root.resolve('darwin/file_picker_darwin/Package.swift'),
    ).readAsStringSync();
    final minimum = RegExp(
      r'\.iOS\("([0-9.]+)"\)',
    ).firstMatch(manifest)!.group(1)!;
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final targets = RegExp(
      r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
    ).allMatches(project).map((m) => m.group(1)!).toList();
    expect(targets, isNotEmpty);
    for (final target in targets) {
      expect(
        atLeast(target, minimum),
        isTrue,
        reason:
            'Runner $target cannot link file-picker-darwin requiring iOS $minimum',
      );
    }
  });

  test(
    'source-owned SwiftPM lockfiles contain immutable public dependency pins',
    () {
      for (final platform in ['ios', 'macos']) {
        for (final owner in [
          'Runner.xcodeproj/project.xcworkspace',
          'Runner.xcworkspace',
        ]) {
          final path = '$platform/$owner/xcshareddata/swiftpm/Package.resolved';
          final lock = jsonDecode(File(path).readAsStringSync()) as Map;
          final pins = (lock['pins'] as List).cast<Map>();
          expect(pins, isNotEmpty, reason: path);
          expect(pins.map((p) => p['identity']).toSet().length, pins.length);
          for (final pin in pins) {
            final remote = Uri.parse(pin['location'] as String);
            expect(remote.scheme, 'https');
            expect(remote.host, 'github.com');
            expect(remote.userInfo, isEmpty);
            expect(remote.query, isEmpty);
            expect(pin['kind'], 'remoteSourceControl');
            expect(
              pin['state']['revision'],
              matches(RegExp(r'^[a-f0-9]{40}$')),
            );
            expect(pin['state']['version'], isA<String>());
          }
        }
      }
    },
  );
}
