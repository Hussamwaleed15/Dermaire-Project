import 'dart:io';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real protected key create/load, isolation and fenced cleanup', (
    tester,
  ) async {
    final p = NativeJournalPlatform();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final a = await JournalNamespace.resolve(
      p,
      owner: 'synthetic-$suffix',
      role: 'patient',
    );
    final b = await JournalNamespace.resolve(
      p,
      owner: 'synthetic-$suffix',
      role: 'doctor',
    );
    final path = await p.directory(a.value);
    await expectLater(
      p.key(a.value, create: false),
      throwsA(isA<JournalUnavailable>()),
    );
    final key = await p.key(a.value, create: true);
    expect(key.length, 32);
    expect(await p.key(a.value, create: false), key);
    final other = await p.key(b.value, create: true);
    expect(other, isNot(key));
    key.fillRange(0, key.length, 0);
    other.fillRange(0, other.length, 0);
    await p.action(a.value, 'fence');
    await expectLater(
      p.key(a.value, create: false),
      throwsA(isA<JournalUnavailable>()),
    );
    await p.action(a.value, 'destroyKey');
    await p.action(a.value, 'eraseFiles');
    expect(Directory(path).existsSync(), isFalse);
    await p.action(a.value, 'destroyKey');
    await p.action(a.value, 'eraseFiles');
    await expectLater(p.directory(a.value), throwsA(isA<JournalUnavailable>()));
    await p.action(b.value, 'fence');
    await p.action(b.value, 'destroyKey');
    await p.action(b.value, 'eraseFiles');
  });
}
