import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:flutter_test/flutter_test.dart';

// Deliberately test-only. A Map is not a durable encrypted journal.
class TestJournal implements OperationJournal {
  JournalEntry? saved;
  int failWrite = 0, writes = 0;
  Completer<void>? pause;
  @override
  Future<JournalEntry?> read(OperationIdentity i) async => saved;
  void write() {
    if (++writes == failWrite) throw StateError('synthetic disk failure');
  }

  @override
  Future<void> insertDurably(JournalEntry e) async {
    write();
    if (saved != null) throw StateError('duplicate original');
    if (pause != null) await pause!.future;
    saved = e;
  }

  @override
  Future<void> replaceDurably(JournalEntry e, JournalPhase expected) async {
    write();
    if (saved?.phase != expected) throw StateError('CAS changed');
    saved = e;
  }
}

class Reader implements JournalReceiptReader {
  ReceiptOutcome outcome = ReceiptOutcome.committed;
  bool current = true, denied = false;
  int reads = 0;
  Completer<void>? pause;
  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    reads++;
    if (pause != null) await pause!.future;
    if (denied) throw RecoveryPermissionLost();
    return ReceiptEvidence(outcome, resource: 'product-1', revision: 2);
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async =>
      current;
}

class Cleanup implements JournalCleanup {
  final steps = <String>[];
  String? fail;
  Future<void> step(String name) async {
    steps.add(name);
    if (fail == name) throw StateError('synthetic');
  }

  @override
  Future<void> fenceDurably(String owner, String role) => step('fence');
  @override
  Future<void> destroyKey(String owner, String role) => step('key');
  @override
  Future<void> eraseFiles(String owner, String role) => step('files');
}

OperationIdentity identity([String owner = 'patient-1']) => OperationIdentity(
  owner: owner,
  role: 'patient',
  path: 'products',
  receiptPath: 'products/attempts',
  key: 'a' * 48,
  fingerprint: 'b' * 64,
);
JournalEntry entry(OperationIdentity i) => JournalEntry(
  identity: i,
  createdAt: DateTime.utc(2026, 10, 18),
  reviewAt: DateTime.utc(2026, 10, 25),
  phase: JournalPhase.prepared,
);
void main() {
  late TestJournal store;
  late JournalCoordinator coordinator;
  late bool active;
  setUp(() {
    store = TestJournal();
    active = true;
    coordinator = JournalCoordinator(
      store,
      active: (i) => active && i.owner == 'patient-1',
      now: () => DateTime.utc(2026, 10, 18),
    );
  });
  test('versioned roundtrip contains bounded metadata only', () {
    final original = entry(identity());
    expect(JournalEntry.decode(original.encode()).encode(), original.encode());
    expect(jsonDecode(original.encode()), isNot(contains('body')));
  });
  for (final change in [
    'schema',
    'phase',
    'private',
    'owner',
    'corrupt',
    'oversize',
    'retention',
  ]) {
    test(
      'corrupt/newer/$change journal locks recovery without exposing input',
      () {
        var value = entry(identity()).encode();
        final data = jsonDecode(value) as Map<String, dynamic>;
        if (change == 'schema') data['schema'] = 2;
        if (change == 'phase') data['phase'] = 'automatically_replayed';
        if (change == 'private') data['raw_message'] = 'SECRET';
        if (change == 'owner') (data['identity'] as Map)['owner'] = 'bad owner';
        if (change == 'retention') data['review_at'] = '2028-01-01T00:00:00Z';
        value = change == 'corrupt'
            ? 'SECRET malformed'
            : change == 'oversize'
            ? 'X' * 8193
            : jsonEncode(data);
        expect(() => JournalEntry.decode(value), throwsFormatException);
      },
    );
  }
  for (final failure in [1, 2]) {
    test('durable write$failure failure prevents network send', () async {
      store.failWrite = failure;
      var sent = 0;
      await expectLater(
        coordinator.prepareAndSend(entry(identity()), () async {
          sent++;
        }),
        throwsStateError,
      );
      expect(sent, 0);
    });
  }
  test(
    'persisted identity precedes send and a lost reply remains original',
    () async {
      var sent = 0;
      final i = identity();
      expect(
        await coordinator.prepareAndSend(entry(i), () async {
          expect(store.saved!.phase, JournalPhase.unconfirmed);
          expect(store.saved!.identity.key, i.key);
          sent++;
          throw TimeoutException('synthetic lost response after commit');
        }),
        JournalPhase.unconfirmed,
      );
      await expectLater(
        coordinator.prepareAndSend(entry(i), () async {
          sent++;
        }),
        throwsStateError,
      );
      expect(sent, 1);
      expect(
        await coordinator.reconcile(i, Reader()),
        JournalPhase.receiptRecorded,
      );
      expect(sent, 1);
    },
  );
  for (final outcome in ReceiptOutcome.values) {
    test('receipt $outcome does not replay or clear original', () async {
      final i = identity();
      store.saved = entry(i).transition(JournalPhase.unconfirmed);
      final r = Reader()..outcome = outcome;
      expect(await coordinator.reconcile(i, r), switch (outcome) {
        ReceiptOutcome.committed => JournalPhase.receiptRecorded,
        ReceiptOutcome.unknown => JournalPhase.unresolved,
        ReceiptOutcome.expired => JournalPhase.expired,
      });
      expect(store.saved!.identity.key, i.key);
    });
  }
  test(
    'stale current resource needs review despite committed receipt',
    () async {
      store.saved = entry(identity()).transition(JournalPhase.unconfirmed);
      expect(
        await coordinator.reconcile(identity(), Reader()..current = false),
        JournalPhase.reviewRequired,
      );
    },
  );
  test('permission denied retains identity', () async {
    store.saved = entry(identity()).transition(JournalPhase.unconfirmed);
    expect(
      await coordinator.reconcile(identity(), Reader()..denied = true),
      JournalPhase.permissionDenied,
    );
    expect(store.saved!.identity.key, identity().key);
  });
  test('wrong account cannot read or send', () async {
    await expectLater(
      coordinator.prepareAndSend(
        entry(identity('patient-2')),
        () async => fail('sent'),
      ),
      throwsA(isA<RecoverySessionLost>()),
    );
    expect(store.writes, 0);
  });
  test('session expires while persisting: no send', () async {
    store.pause = Completer();
    final task = coordinator.prepareAndSend(
      entry(identity()),
      () async => fail('sent'),
    );
    final expectation = expectLater(task, throwsA(isA<RecoverySessionLost>()));
    await Future<void>.delayed(Duration.zero);
    active = false;
    store.pause!.complete();
    await expectation;
    expect(store.saved!.identity.key, identity().key);
  });
  test('late receipt after account change cannot publish or rewrite', () async {
    store.saved = entry(identity()).transition(JournalPhase.unconfirmed);
    final r = Reader()..pause = Completer();
    final expectation = expectLater(
      coordinator.reconcile(identity(), r),
      throwsA(isA<RecoverySessionLost>()),
    );
    await Future<void>.delayed(Duration.zero);
    active = false;
    r.pause!.complete();
    await expectation;
    expect(store.writes, 0);
  });
  test('duplicate concurrent send is fenced', () async {
    store.pause = Completer();
    var sends = 0;
    final first = coordinator.prepareAndSend(entry(identity()), () async {
      sends++;
    });
    await expectLater(
      coordinator.prepareAndSend(entry(identity()), () async {
        sends++;
      }),
      throwsStateError,
    );
    store.pause!.complete();
    await first;
    expect(sends, 1);
  });
  test(
    'local review deadline retains identity without asserting server expiry',
    () async {
      store.saved = JournalEntry(
        identity: identity(),
        createdAt: DateTime.utc(2026, 10, 1),
        reviewAt: DateTime.utc(2026, 10, 2),
        phase: JournalPhase.unconfirmed,
      );
      final reader = Reader();
      expect(
        await coordinator.reconcile(identity(), reader),
        JournalPhase.expired,
      );
      expect(reader.reads, 0);
      expect(store.saved, isNotNull);
    },
  );
  test('CAS failure never overwrites a concurrent result', () async {
    store.saved = entry(identity()).transition(JournalPhase.unconfirmed);
    final r = Reader()..pause = Completer();
    final expectation = expectLater(
      coordinator.reconcile(identity(), r),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    store.saved = store.saved!.transition(JournalPhase.permissionDenied);
    r.pause!.complete();
    await expectation;
    expect(store.saved!.phase, JournalPhase.permissionDenied);
  });
  for (final failure in ['fence', 'key', 'files']) {
    test(
      'interrupted cleanup at $failure retains fence and retries in order',
      () async {
        final c = Cleanup()..fail = failure;
        await expectLater(
          cleanupJournal(c, 'patient-1', 'patient'),
          throwsStateError,
        );
        expect(c.steps, [
          'fence',
          if (failure != 'fence') 'key',
          if (failure == 'files') 'files',
        ]);
        c.fail = null;
        await cleanupJournal(c, 'patient-1', 'patient');
        expect(c.steps.sublist(c.steps.length - 3), ['fence', 'key', 'files']);
      },
    );
  }
}
