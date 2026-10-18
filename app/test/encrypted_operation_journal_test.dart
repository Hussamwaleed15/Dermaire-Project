import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dermaire_app/recovery/encrypted_operation_journal.dart';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/recovery/secure_recovery_session.dart';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// Fake platform only. Storage below executes the actual packaged SQLCipher.
class Keys implements JournalPlatform {
  Keys(this.root);
  final Directory root;
  final keys = <String, Uint8List>{};
  final fenced = <String>{};
  bool ioFailure = false, missing = false;
  int creates = 0;
  @override
  Future<Uint8List> epoch() async => Uint8List.fromList(List.filled(32, 33));
  @override
  Future<String> directory(String ns) async {
    if (fenced.contains(ns)) throw const JournalUnavailable();
    final dir = Directory('${root.path}/$ns')..createSync();
    return dir.path;
  }

  @override
  Future<Uint8List> key(String ns, {required bool create}) async {
    if (fenced.contains(ns) || missing) throw const JournalUnavailable();
    if (create && keys.containsKey(ns)) throw const JournalUnavailable();
    if (!keys.containsKey(ns)) {
      if (!create) throw const JournalUnavailable();
      creates++;
      keys[ns] = Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
    }
    return Uint8List.fromList(keys[ns]!);
  }

  @override
  Future<void> action(String ns, String action) async {
    if (ioFailure) throw const JournalUnavailable();
    if (action == 'fence') fenced.add(ns);
    if (action == 'destroyKey') keys.remove(ns);
    if (action == 'eraseFiles') {
      final dir = Directory('${root.path}/$ns');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }
}

OperationIdentity original([
  String owner = 'synthetic-patient',
  String key = 'a',
]) => OperationIdentity(
  owner: owner,
  role: 'patient',
  path: 'products',
  receiptPath: 'products/attempts',
  key: key * 48,
  fingerprint: 'b' * 64,
);
JournalEntry record([OperationIdentity? i]) => JournalEntry(
  identity: i ?? original(),
  createdAt: DateTime.utc(2026, 10, 19),
  reviewAt: DateTime.utc(2026, 10, 26),
  phase: JournalPhase.prepared,
);

class Receipts implements JournalReceiptReader {
  ReceiptOutcome outcome = ReceiptOutcome.committed;
  bool current = true, denied = false;
  int lookups = 0, refreshes = 0;
  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    lookups++;
    if (denied) throw RecoveryPermissionLost();
    return ReceiptEvidence(outcome, resource: 'synthetic-product', revision: 1);
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    refreshes++;
    return current;
  }
}

void main() {
  late Directory root;
  late Keys platform;
  late JournalNamespace ns;
  late EncryptedOperationJournal journal;
  late bool active;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('dermaire-encrypted-test-');
    platform = Keys(root);
    active = true;
    ns = await JournalNamespace.resolve(
      platform,
      owner: 'synthetic-patient',
      role: 'patient',
    );
    journal = await EncryptedOperationJournal.open(
      platform: platform,
      namespace: ns,
      active: () => active,
    );
  });
  tearDown(() {
    journal.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  Future<void> reopen() async {
    journal.close();
    journal = await EncryptedOperationJournal.open(
      platform: platform,
      namespace: ns,
      active: () => active,
    );
  }

  test(
    'real SQLCipher present; encrypted DB/WAL lacks known synthetic markers',
    () async {
      await journal.insertDurably(record());
      final files = Directory(
        journal.directory,
      ).listSync().whereType<File>().toList();
      expect(files.map((f) => f.path).any((p) => p.endsWith('-wal')), isTrue);
      for (final f in files) {
        final bytes = f.readAsBytesSync();
        final text = String.fromCharCodes(bytes);
        for (final marker in [
          'SQLite format 3',
          'synthetic-patient',
          'products/attempts',
          'a' * 48,
        ]) {
          expect(
            text,
            isNot(contains(marker)),
            reason: 'synthetic marker must be encrypted',
          );
        }
      }
      await reopen();
      expect((await journal.read(original()))!.encode(), record().encode());
    },
  );
  test(
    'wrong key rejected without replacement or plaintext fallback',
    () async {
      await journal.insertDurably(record());
      journal.close();
      final correct = platform.keys[ns.value]!;
      platform.keys[ns.value] = Uint8List(32);
      await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
      expect(platform.creates, 1);
      platform.keys[ns.value] = correct;
      await reopen();
      expect(await journal.read(original()), isNotNull);
    },
  );
  test('no key cannot create new journal over original database', () async {
    await journal.insertDurably(record());
    journal.close();
    platform.missing = true;
    await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
    expect(platform.creates, 1);
  });
  test('duplicate identity cannot overwrite original', () async {
    await journal.insertDurably(record());
    await expectLater(
      journal.insertDurably(record()),
      throwsA(isA<JournalUnavailable>()),
    );
    expect((await journal.pending()).length, 1);
  });
  test('transactional CAS preserves original metadata', () async {
    final e = record();
    await journal.insertDurably(e);
    await journal.replaceDurably(
      e.transition(JournalPhase.unconfirmed),
      JournalPhase.prepared,
    );
    await expectLater(
      journal.replaceDurably(
        e.transition(JournalPhase.expired),
        JournalPhase.prepared,
      ),
      throwsA(isA<JournalUnavailable>()),
    );
    await reopen();
    expect((await journal.read(original()))!.phase, JournalPhase.unconfirmed);
  });
  test('two actual connections cannot insert same original', () async {
    final second = await EncryptedOperationJournal.open(
      platform: platform,
      namespace: ns,
      active: () => active,
    );
    try {
      final results = await Future.wait([
        journal
            .insertDurably(record())
            .then((_) => true, onError: (_) => false),
        second.insertDurably(record()).then((_) => true, onError: (_) => false),
      ]);
      expect(results.where((v) => v).length, 1);
    } finally {
      second.close();
    }
  });
  test('owner mismatch denied before read or insertion', () async {
    await expectLater(
      journal.read(original('other-account')),
      throwsA(isA<RecoverySessionLost>()),
    );
    await expectLater(
      journal.insertDurably(record(original('other-account'))),
      throwsA(isA<RecoverySessionLost>()),
    );
  });
  test(
    'session expiration hides disk content without discarding identity',
    () async {
      await journal.insertDurably(record());
      active = false;
      await expectLater(journal.pending(), throwsA(isA<RecoverySessionLost>()));
      active = true;
      await reopen();
      expect((await journal.pending()).length, 1);
    },
  );
  test(
    'I/O acknowledgment failure before send never invokes network',
    () async {
      final c = JournalCoordinator(
        journal,
        active: (_) => active,
        now: () => DateTime.utc(2026, 10, 19),
      );
      platform.ioFailure = true;
      var sends = 0;
      await expectLater(
        c.prepareAndSend(record(), () async {
          sends++;
        }),
        throwsA(isA<JournalUnavailable>()),
      );
      expect(sends, 0);
      platform.ioFailure = false;
      await reopen();
      expect(
        (await journal.pending()).length,
        1,
      ); // Commit may have succeeded: preserve ambiguity.
    },
  );
  test(
    'original server commit + lost reply then disk reconstruction reconciles without replay',
    () async {
      var sends = 0;
      final c = JournalCoordinator(
        journal,
        active: (_) => active,
        now: () => DateTime.utc(2026, 10, 19),
      );
      await c.prepareAndSend(record(), () async {
        sends++;
        throw const SocketException('synthetic');
      });
      await reopen();
      final r = Receipts();
      final restored = JournalCoordinator(
        journal,
        active: (_) => active,
        now: () => DateTime.utc(2026, 10, 19),
      );
      expect(
        await restored.reconcile(original(), r),
        JournalPhase.receiptRecorded,
      );
      expect(r.lookups, 1);
      expect(r.refreshes, 1);
      expect(sends, 1);
      await expectLater(
        restored.prepareAndSend(record(), () async {
          sends++;
        }),
        throwsStateError,
      );
      expect(sends, 1);
    },
  );
  for (final outcome in ReceiptOutcome.values) {
    test(
      'restart receipt ${outcome.name} is historical, never replayed',
      () async {
        await journal.insertDurably(record());
        await reopen();
        final r = Receipts()..outcome = outcome;
        final c = JournalCoordinator(
          journal,
          active: (_) => active,
          now: () => DateTime.utc(2026, 10, 19),
        );
        expect(await c.reconcile(original(), r), switch (outcome) {
          ReceiptOutcome.committed => JournalPhase.receiptRecorded,
          ReceiptOutcome.unknown => JournalPhase.unresolved,
          ReceiptOutcome.expired => JournalPhase.expired,
        });
      },
    );
  }
  test('newer resource and grant revocation remain locked', () async {
    await journal.insertDurably(record());
    final r = Receipts()..current = false;
    final c = JournalCoordinator(
      journal,
      active: (_) => active,
      now: () => DateTime.utc(2026, 10, 19),
    );
    expect(await c.reconcile(original(), r), JournalPhase.reviewRequired);
    r.denied = true;
    expect(await c.reconcile(original(), r), JournalPhase.permissionDenied);
  });
  test(
    'expired local retention is unresolved evidence, not deleted identity',
    () async {
      await journal.insertDurably(record());
      final r = Receipts();
      final c = JournalCoordinator(
        journal,
        active: (_) => active,
        now: () => DateTime.utc(2026, 11, 19),
      );
      expect(await c.reconcile(original(), r), JournalPhase.expired);
      expect(r.lookups, 0);
      expect((await journal.pending()).length, 1);
    },
  );
  for (final version in [0, 2, 99]) {
    test(
      'unsupported existing schema $version locks, never reinitializes',
      () async {
        await journal.insertDurably(record());
        journal.close();
        final db = sqlite3.open('${journal.directory}/operations.db');
        final hex = platform.keys[ns.value]!
            .map((v) => v.toRadixString(16).padLeft(2, '0'))
            .join();
        db.execute('PRAGMA key="x\'$hex\'"');
        db.execute('PRAGMA user_version=$version');
        db.close();
        await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
        expect(platform.creates, 1);
      },
    );
  }
  test('corrupt ciphertext never treated as empty database', () async {
    await journal.insertDurably(record());
    journal.close();
    final f = File('${journal.directory}/operations.db');
    final bytes = f.readAsBytesSync();
    bytes[100] ^= 255;
    f.writeAsBytesSync(bytes, flush: true);
    await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
    expect(platform.creates, 1);
  });
  test(
    'logout fence precedes key and files; fenced namespace never reused',
    () async {
      await journal.insertDurably(record());
      await journal.erase();
      expect(platform.fenced, contains(ns.value));
      expect(platform.keys, isNot(contains(ns.value)));
      expect(Directory(journal.directory).existsSync(), false);
      await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
      await EncryptedOperationJournal.eraseNamespace(platform, ns);
    },
  );
  test('secure session restores only after current reauthorization', () async {
    journal.close();
    final session = await SecureRecoverySession.open(
      platform: platform,
      owner: ns.owner,
      role: ns.role,
      authorized: () => active,
      now: () => DateTime.utc(2026, 10, 19),
    );
    await session.prepareAndSend(record(), () async {});
    session.suspend();
    active = false;
    await expectLater(session.restore(), throwsA(isA<RecoverySessionLost>()));
    await expectLater(
      SecureRecoverySession.open(
        platform: platform,
        owner: ns.owner,
        role: ns.role,
        authorized: () => active,
        now: () => DateTime.utc(2026, 10, 19),
      ),
      throwsA(isA<RecoverySessionLost>()),
    );
    active = true;
    final restored = await SecureRecoverySession.open(
      platform: platform,
      owner: ns.owner,
      role: ns.role,
      authorized: () => active,
      now: () => DateTime.utc(2026, 10, 19),
    );
    expect((await restored.restore()).single.phase, JournalPhase.unconfirmed);
    await restored.erase();
  });
  test(
    'late send response after session suspension cannot publish old phase',
    () async {
      journal.close();
      final session = await SecureRecoverySession.open(
        platform: platform,
        owner: ns.owner,
        role: ns.role,
        authorized: () => active,
        now: () => DateTime.utc(2026, 10, 19),
      );
      final sent = Completer<void>(), reply = Completer<void>();
      final pending = session.prepareAndSend(record(), () async {
        sent.complete();
        await reply.future;
      });
      final assertion = expectLater(
        pending,
        throwsA(isA<RecoverySessionLost>()),
      );
      await sent.future;
      session.suspend();
      active = false;
      reply.complete();
      await assertion;
      active = true;
      await reopen();
      expect((await journal.read(original()))!.phase, JournalPhase.unconfirmed);
    },
  );
  test(
    'other account restart reads empty distinct encrypted journal',
    () async {
      await journal.insertDurably(record());
      final other = await SecureRecoverySession.open(
        platform: platform,
        owner: 'patient-b',
        role: 'patient',
        authorized: () => true,
        now: () => DateTime.utc(2026, 10, 19),
      );
      expect(await other.restore(), isEmpty);
      await other.erase();
      expect((await journal.pending()).length, 1);
    },
  );
  test('interrupted encrypted transaction rolls back original row', () async {
    await journal.insertDurably(record());
    journal.close();
    final db = sqlite3.open('${journal.directory}/operations.db');
    final hex = platform.keys[ns.value]!
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    db.execute('PRAGMA key="x\'$hex\'"');
    db.execute('BEGIN IMMEDIATE');
    db.execute('DELETE FROM operations');
    db.close();
    await reopen();
    expect((await journal.pending()).length, 1);
  });
  test(
    'existing plaintext SQLite is rejected rather than migrated or opened',
    () async {
      journal.close();
      final file = File('${journal.directory}/operations.db');
      file.deleteSync();
      final plain = sqlite3.open(file.path);
      plain.execute('CREATE TABLE synthetic (value TEXT)');
      plain.execute("INSERT INTO synthetic VALUES ('SYNTHETIC-PLAINTEXT')");
      plain.close();
      final before = file.readAsBytesSync();
      await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
      expect(file.readAsBytesSync(), before);
      expect(platform.creates, 1);
    },
  );
  test(
    'encrypted malformed row locks review instead of silently dropping identity',
    () async {
      await journal.insertDurably(record());
      journal.close();
      final db = sqlite3.open('${journal.directory}/operations.db');
      final hex = platform.keys[ns.value]!
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join();
      db.execute('PRAGMA key="x\'$hex\'"');
      db.execute("UPDATE operations SET value='{}'");
      db.close();
      await reopen();
      await expectLater(journal.pending(), throwsA(isA<JournalUnavailable>()));
    },
  );
  test(
    'same original key with changed fingerprint cannot read or replace journal identity',
    () async {
      await journal.insertDurably(record());
      final changed = OperationIdentity(
        owner: ns.owner,
        role: ns.role,
        path: 'products',
        receiptPath: 'products/attempts',
        key: 'a' * 48,
        fingerprint: 'e' * 64,
      );
      await expectLater(
        journal.read(changed),
        throwsA(isA<JournalUnavailable>()),
      );
      await expectLater(
        journal.replaceDurably(
          record(changed).transition(JournalPhase.unresolved),
          JournalPhase.prepared,
        ),
        throwsA(isA<JournalUnavailable>()),
      );
      expect((await journal.read(original()))!.phase, JournalPhase.prepared);
    },
  );
  test(
    'lost database with existing protected key never silently creates an empty journal',
    () async {
      await journal.insertDurably(record());
      journal.close();
      Directory(journal.directory).deleteSync(recursive: true);
      await expectLater(reopen(), throwsA(isA<JournalUnavailable>()));
      expect(platform.creates, 1);
    },
  );
}
