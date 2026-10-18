import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dermaire/journal-keys-v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'opaque namespace stable per installation, isolated by account and role',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => Uint8List(32)..fillRange(0, 32, 7),
      );
      final p = NativeJournalPlatform();
      final a = await JournalNamespace.resolve(
        p,
        owner: 'patient-a',
        role: 'patient',
      );
      final again = await JournalNamespace.resolve(
        p,
        owner: 'patient-a',
        role: 'patient',
      );
      final b = await JournalNamespace.resolve(
        p,
        owner: 'patient-b',
        role: 'patient',
      );
      final doctor = await JournalNamespace.resolve(
        p,
        owner: 'patient-a',
        role: 'doctor',
      );
      expect(a.value, again.value);
      expect({a.value, b.value, doctor.value}.length, 3);
      expect(a.value, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(a.value, isNot(contains('patient')));
    },
  );
  for (final method in [
    'loadKey',
    'createKey',
    'epoch',
    'directory',
    'fence',
    'destroyKey',
    'eraseFiles',
    'protectFiles',
  ]) {
    test('$method unavailable reports sanitized failure', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'private-path-key'),
      );
      final p = NativeJournalPlatform();
      final ns = 'a' * 64;
      final Future<Object?> future = switch (method) {
        'loadKey' => p.key(ns, create: false),
        'createKey' => p.key(ns, create: true),
        'epoch' => p.epoch(),
        'directory' => p.directory(ns),
        _ => p.action(ns, method),
      };
      await expectLater(future, throwsA(isA<JournalUnavailable>()));
      expect(const JournalUnavailable().toString(), isNot(contains('private')));
    });
  }
  test('short key and epoch rejected; key load never creates', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c.method);
      return Uint8List(31);
    });
    final p = NativeJournalPlatform();
    await expectLater(
      p.key('a' * 64, create: false),
      throwsA(isA<JournalUnavailable>()),
    );
    await expectLater(p.epoch(), throwsA(isA<JournalUnavailable>()));
    expect(calls, ['loadKey', 'epoch']);
  });
  test(
    'reject invalid namespace and unsupported actions before bridge',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      final p = NativeJournalPlatform();
      await expectLater(
        p.directory('../escape'),
        throwsA(isA<JournalUnavailable>()),
      );
      await expectLater(
        p.action('a' * 64, 'rekey'),
        throwsA(isA<JournalUnavailable>()),
      );
      expect(calls, 0);
    },
  );
}
