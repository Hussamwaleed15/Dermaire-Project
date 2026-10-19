import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dermaire_app/integration/contract.dart';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/recovery/clinical_receipt_reader.dart';
import 'package:dermaire_app/recovery/adherence_receipt_reader.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/recovery/recovery_ui.dart';
import 'package:dermaire_app/recovery/encrypted_operation_journal.dart';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_clinical_reviews_test.dart' as clinical;
import 'wave_q_clinical_receipt_test.dart' as keyed;
import 'wave_adherence_receipt_test.dart' as adherence;
import 'encrypted_operation_journal_test.dart' as disk;

OperationIdentity identity(PendingIntent op, String owner, String role) =>
    OperationIdentity(
      owner: owner,
      role: role,
      path: op.path,
      receiptPath: op.attemptPath,
      key: op.key,
      fingerprint: OperationIdentity.digest(op.body),
      scope: op.recoveryScope,
    );

class ClinicalReaderWire extends keyed.ClinicalContractWire {
  String selectedGrant = 'grant-patient-1';
  @override
  Map<String, dynamic> grant([String status = 'active']) => {
    ...super.grant(status),
    'id': selectedGrant,
  };
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final kind in ['notes', 'reviews']) {
    test(
      'metadata $kind reader rechecks original grant and never restores narrative',
      () async {
        final w = ClinicalReaderWire();
        await w.run(() async {
          final v = await clinical.editor(w);
          try {
            w.loseAfterCommit = true;
            await clinical.submit(v.$3, kind);
            final i = identity(v.$3.pending(kind)!, w.owner, w.role);
            final reader = ClinicalReceiptReader(api, api.sessionGeneration);
            final r = await reader.lookup(i);
            expect(r.outcome, ReceiptOutcome.committed);
            expect(await reader.verifyCurrent(i, r), true);
            expect(
              jsonEncode(i.toJson()),
              isNot(contains('Explicit clinician')),
            );
            if (kind == 'reviews') {
              w.mode = 'superseded';
              expect(await reader.verifyCurrent(i, r), false);
            }
            w.selectedGrant = 'replacement-grant';
            await expectLater(
              reader.lookup(i),
              throwsA(isA<RecoveryPermissionLost>()),
            );
            await expectLater(
              reader.verifyCurrent(i, r),
              throwsA(isA<RecoveryPermissionLost>()),
            );
            expect(w.posts, 1);
          } finally {
            clinical.clean(v);
          }
        });
      },
    );
    for (final status in ['unknown', 'expired', 'erased', '403', '503']) {
      test('metadata $kind $status remains honest and never sends', () async {
        final w = ClinicalReaderWire();
        await w.run(() async {
          final v = await clinical.editor(w);
          try {
            w.loseAfterCommit = true;
            await clinical.submit(v.$3, kind);
            final i = identity(v.$3.pending(kind)!, w.owner, w.role);
            final reader = ClinicalReceiptReader(api, api.sessionGeneration);
            if (int.tryParse(status) != null) {
              w.lookupStatus = int.parse(status);
              await expectLater(
                reader.lookup(i),
                status == '403'
                    ? throwsA(isA<RecoveryPermissionLost>())
                    : throwsA(anything),
              );
            } else {
              w.receiptState = status;
              final r = await reader.lookup(i);
              expect(
                r.outcome,
                status == 'unknown'
                    ? ReceiptOutcome.unknown
                    : status == 'expired'
                    ? ReceiptOutcome.expired
                    : ReceiptOutcome.committed,
              );
              if (status != 'erased') {
                expect(await reader.verifyCurrent(i, r), false);
              }
            }
            expect(w.posts, 1);
            expect(v.$3.pending(kind)!.key, i.key);
          } finally {
            clinical.clean(v);
          }
        });
      });
    }
  }
  test(
    'adherence metadata verifies immutable report and original config, not actual use/current routine',
    () async {
      final w = adherence.Wire();
      await w.run((c) async {
        await w.submit(c);
        final i = identity(
          api.integrationIntents['routine:adherence']!,
          'patient-1',
          'patient',
        );
        final reader = AdherenceReceiptReader(api, api.sessionGeneration);
        final r = await reader.lookup(i);
        expect(r.outcome, ReceiptOutcome.committed);
        expect(r.revision, 7);
        w.configuration = {...w.configuration, 'revision': 20};
        expect(await reader.verifyCurrent(i, r), true);
        w.reports = [];
        expect(await reader.verifyCurrent(i, r), false);
        expect(w.posts, 1);
        expect(
          jsonEncode(i.toJson()),
          isNot(contains('Original synthetic note')),
        );
      });
    },
  );
  for (final malformed in [
    'owner',
    'actor',
    'day basis',
    'config revision',
    'nested receipt',
  ]) {
    test('adherence metadata rejects wrong $malformed', () async {
      final w = adherence.Wire();
      await w.run((c) async {
        await w.submit(c);
        final i = identity(
          api.integrationIntents['routine:adherence']!,
          'patient-1',
          'patient',
        );
        w.change = (v) => switch (malformed) {
          'owner' => {...v, 'owner_id': 'another'},
          'actor' => {...v, 'actor_id': 'another'},
          'day basis' => {
            ...v,
            'result': {...v['result'] as Map, 'day_basis': 'local'},
          },
          'config revision' => {...v, 'configuration_revision': 99},
          _ => {
            ...v,
            'result': {
              ...v['result'] as Map,
              'receipt': {
                ...(v['result'] as Map)['receipt'] as Map,
                'actor_id': 'another',
              },
            },
          },
        };
        await expectLater(
          AdherenceReceiptReader(api, api.sessionGeneration).lookup(i),
          throwsFormatException,
        );
        expect(w.posts, 1);
      });
    });
  }
  for (final status in ['unknown', 'expired', '403', '401']) {
    test('adherence metadata $status never permits replay', () async {
      final w = adherence.Wire();
      await w.run((c) async {
        await w.submit(c);
        final i = identity(
          api.integrationIntents['routine:adherence']!,
          'patient-1',
          'patient',
        );
        final reader = AdherenceReceiptReader(api, api.sessionGeneration);
        if (status == 'unknown') w.original = null;
        if (status == 'expired') {
          w.change = (v) => {...v, 'status': 'expired', 'result': null};
        }
        if (int.tryParse(status) != null) w.lookupStatus = int.parse(status);
        if (['403', '401'].contains(status)) {
          await expectLater(
            reader.lookup(i),
            status == '403'
                ? throwsA(isA<RecoveryPermissionLost>())
                : throwsA(anything),
          );
        } else {
          final r = await reader.lookup(i);
          expect(
            r.outcome,
            status == 'unknown'
                ? ReceiptOutcome.unknown
                : ReceiptOutcome.expired,
          );
          expect(await reader.verifyCurrent(i, r), false);
        }
        expect(w.posts, 1);
      });
    });
  }
  test('late adherence receipt cannot cross a changed API session', () async {
    final w = adherence.Wire();
    await w.run((c) async {
      await w.submit(c);
      final i = identity(
        api.integrationIntents['routine:adherence']!,
        'patient-1',
        'patient',
      );
      w.delayed = Completer<http.Response>();
      final read = AdherenceReceiptReader(api, api.sessionGeneration).lookup(i);
      await w.lookupSent.future;
      await api.init();
      w.delayed!.complete(http.Response(jsonEncode(w.lookup()), 200));
      await expectLater(read, throwsA(anything));
      expect(w.posts, 1);
    });
  });
  test(
    'actual encrypted journal can retain doctor metadata and reconcile with no narrative or new send',
    () async {
      final w = ClinicalReaderWire();
      await w.run(() async {
        final v = await clinical.editor(w);
        final root = Directory.systemTemp.createTempSync(
          'dermaire-clinical-reader-',
        );
        EncryptedOperationJournal? journal;
        try {
          w.loseAfterCommit = true;
          await clinical.submit(v.$3, 'notes');
          final i = identity(v.$3.pending('notes')!, w.owner, w.role);
          final platform = disk.Keys(root);
          final ns = await JournalNamespace.resolve(
            platform,
            owner: i.owner,
            role: i.role,
          );
          journal = await EncryptedOperationJournal.open(
            platform: platform,
            namespace: ns,
            active: () => api.canReadDoctorWorkspace,
          );
          final entry = disk.record(i);
          await journal.insertDurably(entry);
          journal.close();
          journal = await EncryptedOperationJournal.open(
            platform: platform,
            namespace: ns,
            active: () => api.canReadDoctorWorkspace,
          );
          final coordinator = JournalCoordinator(
            journal,
            active: (v) =>
                api.canReadDoctorWorkspace && v.owner == api.authenticatedOwner,
            now: () => DateTime.utc(2026, 10, 19),
          );
          expect(
            await coordinator.reconcile(
              i,
              ClinicalReceiptReader(api, api.sessionGeneration),
            ),
            JournalPhase.receiptRecorded,
          );
          expect(
            (await journal.read(i))!.encode(),
            isNot(contains('Explicit clinician')),
          );
          expect(w.posts, 1);
        } finally {
          journal?.close();
          root.deleteSync(recursive: true);
          clinical.clean(v);
        }
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets('doctor retained note receipt review dark=${dark}320px200%', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final w = ClinicalReaderWire();
      await w.run(() async {
        final v = await clinical.editor(w);
        try {
          w.loseAfterCommit = true;
          await clinical.submit(v.$3, 'notes');
          final key = v.$3.pending('notes')!.key;
          w.lookupStatus = 401;
          await v.$3.refresh();
          expect(api.isAuthenticated, false);
          w.lookupStatus = 200;
          await w.login();
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
          final button = find.text('Check original clinical note receipt');
          await t.scrollUntilVisible(button, 200);
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          await t.tap(button);
          await t.pumpAndSettle();
          expect(
            find.textContaining('current clinical note verified separately'),
            findsOneWidget,
          );
          expect(w.posts, 1);
          expect(api.quarantinedOperations.single.key, key);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          clinical.clean(v);
          await api.init();
        }
      });
    });
  }
}
