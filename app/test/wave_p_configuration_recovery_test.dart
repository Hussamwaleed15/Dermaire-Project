import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dermaire_app/integration/configuration_receipt.dart';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/recovery/configuration_receipt_reader.dart';
import 'package:dermaire_app/recovery/encrypted_operation_journal.dart';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/recovery/recovery_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_routine_receipt_test.dart' as routine;
import 'wave_experiment_receipt_test.dart' as experiment;
import 'wave_experiment_revision_test.dart' as revision;
import 'encrypted_operation_journal_test.dart' as disk;
import 'product_authority_test.dart' as auth;

OperationIdentity identity(ConfigurationPending op) => OperationIdentity(
  owner: op.owner,
  role: 'patient',
  path: op.path,
  receiptPath: op.attemptPath,
  key: op.key,
  fingerprint: OperationIdentity.digest(op.body),
  scope: op.recoveryScope,
);

class RecoveryWire extends routine.RoutineWire {
  @override
  Future<http.Response> call(http.Request r) {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/auth/logout')) {
      return Future.value(http.Response('', 204));
    }
    return super.call(r);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final operation in ['create', 'edit', 'stop']) {
    test(
      'routine $operation metadata reads original then independent current',
      () async {
        final w = RecoveryWire()..operation = operation;
        if (operation == 'create') w.current = null;
        await w.run((c) async {
          expect(await w.submit(c), false);
          final i = identity(c.configurationPending!);
          final reader = ConfigurationReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.outcome, ReceiptOutcome.committed);
          expect(await reader.verifyCurrent(i, r), true);
          w.current = {...w.current!, 'revision': 20};
          expect(await reader.verifyCurrent(i, r), false);
          w.current = null;
          expect(await reader.verifyCurrent(i, r), false);
          expect(w.writes, 1);
        });
      },
    );
  }
  for (final operation in [
    'create',
    'edit',
    'activate',
    'finish',
    'cancel',
    'evaluate',
  ]) {
    test(
      'experiment $operation receipt does not assert related/current derived state',
      () async {
        final w = experiment.ReceiptWire()..operation = operation;
        if (['finish', 'evaluate'].contains(operation)) {
          w.row = revision.experiment('active');
        }
        await w.run((c) async {
          expect(await w.submit(c), false);
          final i = identity(c.configurationPending!);
          final reader = ConfigurationReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.outcome, ReceiptOutcome.committed);
          expect(
            await reader.verifyCurrent(i, r),
            !['activate', 'evaluate'].contains(operation),
          );
          w.row = {...w.row, 'revision': 30};
          expect(await reader.verifyCurrent(i, r), false);
          expect(w.submissions, 1);
        });
      },
    );
  }
  for (final field in [
    'owner_id',
    'actor_id',
    'domain',
    'operation',
    'resource_id',
    'resource_revision',
    'result',
  ]) {
    test('configuration rejects inconsistent $field', () async {
      final w = RecoveryWire();
      await w.run((c) async {
        await w.submit(c);
        final i = identity(c.configurationPending!);
        w.change = (v) => {
          ...v,
          field: switch (field) {
            'resource_revision' => 1,
            'result' => {...v['result'] as Map, 'id': 'other'},
            _ => 'other',
          },
        };
        await expectLater(
          ConfigurationReceiptReader(api, api.sessionGeneration).lookup(i),
          throwsFormatException,
        );
        expect(w.writes, 1);
      });
    });
  }
  test('unknown, expired, erased and denied never replay', () async {
    final w = RecoveryWire()..loss = 'before';
    await w.run((c) async {
      await w.submit(c);
      final i = identity(c.configurationPending!);
      final reader = ConfigurationReceiptReader(api, api.sessionGeneration);
      expect((await reader.lookup(i)).outcome, ReceiptOutcome.unknown);
      w.original = routine.row(9);
      w.change = (v) => {
        ...v,
        'status': 'expired',
        'result_availability': 'expired',
        'result': null,
      };
      expect((await reader.lookup(i)).outcome, ReceiptOutcome.expired);
      w.change = (v) => {...v, 'result_availability': 'erased', 'result': null};
      expect((await reader.lookup(i)).outcome, ReceiptOutcome.committed);
      w.lookupStatus = 403;
      await expectLater(
        reader.lookup(i),
        throwsA(isA<RecoveryPermissionLost>()),
      );
      expect(w.writes, 1);
      await api.logout();
      await expectLater(reader.lookup(i), throwsA(isA<RecoverySessionLost>()));
    });
  });
  test('late original receipt after logout cannot publish evidence', () async {
    final w = RecoveryWire();
    await w.run((c) async {
      await w.submit(c);
      final i = identity(c.configurationPending!);
      w.delayed = Completer<http.Response>();
      final read = ConfigurationReceiptReader(
        api,
        api.sessionGeneration,
      ).lookup(i);
      await w.lookupSent.future;
      await api.logout();
      w.delayed!.complete(http.Response(jsonEncode(w.receipt()), 200));
      await expectLater(read, throwsA(anything));
      expect(api.isAuthenticated, false);
      expect(w.writes, 1);
    });
  });
  test(
    'encrypted journal reopen reconciles configuration without payload or replay',
    () async {
      final w = RecoveryWire();
      await w.run((c) async {
        await w.submit(c);
        final i = identity(c.configurationPending!);
        final root = Directory.systemTemp.createTempSync(
          'dermaire-config-recovery-',
        );
        final platform = disk.Keys(root);
        final ns = await JournalNamespace.resolve(
          platform,
          owner: i.owner,
          role: i.role,
        );
        var journal = await EncryptedOperationJournal.open(
          platform: platform,
          namespace: ns,
          active: () => api.isAuthenticated,
        );
        try {
          var coordinator = JournalCoordinator(
            journal,
            active: (v) =>
                api.isAuthenticated && v.owner == api.authenticatedOwner,
            now: () => DateTime.utc(2026, 10, 19),
          );
          final entry = disk.record(i);
          int syntheticSends = 0;
          expect(
            await coordinator.prepareAndSend(entry, () async {
              syntheticSends++;
              throw TimeoutException('synthetic lost response');
            }),
            JournalPhase.unconfirmed,
          );
          journal.close();
          journal = await EncryptedOperationJournal.open(
            platform: platform,
            namespace: ns,
            active: () => api.isAuthenticated,
          );
          coordinator = JournalCoordinator(
            journal,
            active: (v) =>
                api.isAuthenticated && v.owner == api.authenticatedOwner,
            now: () => DateTime.utc(2026, 10, 19),
          );
          expect(
            await coordinator.reconcile(
              i,
              ConfigurationReceiptReader(api, api.sessionGeneration),
            ),
            JournalPhase.receiptRecorded,
          );
          final retained = await journal.read(i);
          expect(retained!.identity.key, i.key);
          expect(retained.encode(), isNot(contains('Original instruction')));
          expect(syntheticSends, 1);
          expect(w.writes, 1);
          await expectLater(
            coordinator.prepareAndSend(entry, () async {
              syntheticSends++;
            }),
            throwsStateError,
          );
          expect(syntheticSends, 1);
        } finally {
          journal.close();
          root.deleteSync(recursive: true);
        }
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets('routine receipt review after login dark=$dark at320px200%', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final w = RecoveryWire();
      await w.run((c) async {
        try {
          await w.submit(c);
          final key = c.configurationPending!.key;
          // Expired authorization retains minimum correlation. Explicit logout
          // deliberately purges session memory under the established lifecycle.
          w.lookupStatus = 401;
          await expectLater(
            ConfigurationReceiptReader(
              api,
              api.sessionGeneration,
            ).lookup(identity(c.configurationPending!)),
            throwsA(anything),
          );
          w.lookupStatus = 200;
          await auth.login();
          expect(api.quarantinedOperations.single.key, key);
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const RecoveryReviewScreen(),
            ),
          );
          await t.pumpAndSettle();
          final button = find.text('Check original routine receipt');
          await t.scrollUntilVisible(button, 200);
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          await t.tap(button);
          await t.pumpAndSettle();
          expect(
            find.textContaining('current routine verified separately'),
            findsOneWidget,
          );
          expect(w.writes, 1);
          expect(api.quarantinedOperations.single.key, key);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          await api.init();
        }
      });
    });
  }
}
