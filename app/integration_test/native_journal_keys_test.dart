import 'dart:io';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:dermaire_app/recovery/encrypted_operation_journal.dart';
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
    await File(
      '$path/synthetic-protection-test',
    ).writeAsString('Synthetic only', flush: true);
    expect(await p.key(a.value, create: false), key);
    await expectLater(
      p.key(a.value, create: true),
      throwsA(isA<JournalUnavailable>()),
    );
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
  testWidgets(
    'strict adapter refuses an unverified protection class on simulator',
    (tester) async {
      final p = NativeJournalPlatform();
      final ns = await JournalNamespace.resolve(
        p,
        owner: 'synthetic-strict-${DateTime.now().microsecondsSinceEpoch}',
        role: 'patient',
      );
      try {
        if (const bool.fromEnvironment(
          'DERMAIRE_EXPECT_PROTECTION_UNAVAILABLE',
        )) {
          await expectLater(
            EncryptedOperationJournal.open(
              platform: p,
              namespace: ns,
              active: () => true,
            ),
            throwsA(
              isA<JournalUnavailable>().having(
                (e) => e.stage,
                'stage',
                'file-protection',
              ),
            ),
          );
        } else {
          final journal = await EncryptedOperationJournal.open(
            platform: p,
            namespace: ns,
            active: () => true,
          );
          journal.close();
        }
      } finally {
        await EncryptedOperationJournal.eraseNamespace(p, ns);
      }
    },
  );
}
