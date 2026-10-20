import 'dart:io';
import 'package:dermaire_app/integration/contract.dart';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:dermaire_app/recovery/recovery_reader_catalog.dart';
import 'package:dermaire_app/recovery/secure_recovery_session.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'encrypted_operation_journal_test.dart' as disk;
import 'wave_messaging_test.dart' as messages;
import 'wave_plans_test.dart' as plans;
import 'm6_doctor_fixture.dart' as fixture;
import 'wave_q_domain_readers_test.dart' show identity;

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final doctor in [false, true]) {
    for (final scenario in [
      'committed',
      'unknown',
      'denied',
      'persistence failure',
    ]) {
      test(
        'isolated message journal before send and restart doctor=$doctor $scenario',
        () async {
          final w = messages.MessageWire(doctor: doctor);
          final root = Directory.systemTemp.createTempSync(
            'dermaire-f7-message-',
          );
          final keys = disk.Keys(root);
          SecureRecoverySession? session;
          await w.run(() async {
            try {
              await w.login();
              final generation = api.sessionGeneration;
              bool active() =>
                  api.isCurrentSession(generation) &&
                  (doctor
                      ? api.canReadDoctorWorkspace
                      : api.canReadPatientClinicalStatus);
              Future<SecureRecoverySession> open() =>
                  SecureRecoverySession.open(
                    platform: keys,
                    owner: w.owner,
                    role: w.role,
                    authorized: active,
                    now: DateTime.now,
                  );
              session = await open();
              final op = PendingIntent(
                path: 'messaging/threads/thread-1/messages',
                attemptPath: 'messaging/threads/thread-1/attempts',
                body: {'body': 'Synthetic private body never journaled.'},
                identityScope: {
                  'patient_id': 'patient-1',
                  'doctor_id': 'doctor-1',
                  'access_id': 'grant-1',
                },
              );
              final i = identity(op, w.owner, w.role),
                  now = DateTime.now().toUtc();
              final entry = JournalEntry(
                identity: i,
                createdAt: now,
                reviewAt: now.add(const Duration(days: 1)),
                phase: JournalPhase.prepared,
              );
              w.mode = scenario == 'unknown' ? 'lost before' : 'lost after';
              keys.ioFailure = scenario == 'persistence failure';
              final send = session!.prepareAndSend(entry, () async {
                // Real encrypted COMMIT has completed before this synthetic send.
                expect(
                  (await session!.journal.read(i))!.phase,
                  JournalPhase.unconfirmed,
                );
                await api.integrationResource(
                  op.path,
                  generation,
                  method: op.method,
                  body: op.body,
                  key: op.key,
                );
              });
              if (keys.ioFailure) {
                await expectLater(send, throwsA(isA<JournalUnavailable>()));
                expect(w.posts, 0);
              } else {
                expect(await send, JournalPhase.unconfirmed);
                expect(w.posts, 1);
                expect(w.sends.single.headers['Idempotency-Key'], op.key);
              }
              keys.ioFailure = false;
              session!.suspend();
              session = await open();
              final restored = (await session!.restore()).single;
              expect(restored.identity.key, op.key);
              expect(
                restored.encode(),
                isNot(contains('Synthetic private body')),
              );
              expect(restored.identity.owner, w.owner);
              if (scenario == 'denied') w.closed = true;
              final catalog = RecoveryReaderCatalog(api, generation);
              expect(
                await session!.reconcile(
                  restored.identity,
                  catalog.readerFor(restored.identity)!,
                ),
                scenario == 'denied'
                    ? JournalPhase.permissionDenied
                    : ['unknown', 'persistence failure'].contains(scenario)
                    ? JournalPhase.unresolved
                    : JournalPhase.receiptRecorded,
              );
              expect(w.posts, scenario == 'persistence failure' ? 0 : 1);
              final foreign = OperationIdentity(
                owner: 'other-account',
                role: i.role,
                path: i.path,
                receiptPath: i.receiptPath,
                key: i.key,
                fingerprint: i.fingerprint,
                scope: i.scope,
              );
              expect(catalog.readerFor(foreign), isNull);
              await expectLater(
                session!.journal.read(foreign),
                throwsA(isA<RecoverySessionLost>()),
              );
              await api.logout();
              expect(catalog.readerFor(i), isNull);
              await expectLater(
                session!.restore(),
                throwsA(isA<RecoverySessionLost>()),
              );
            } finally {
              session?.suspend();
              await api.init();
              root.deleteSync(recursive: true);
            }
          });
        },
      );
    }
    for (final newer in [false, true]) {
      test(
        'isolated plan journal distinguishes original and current doctor=$doctor newer=$newer',
        () async {
          final w = plans.PlanWire(doctor: doctor);
          final root = Directory.systemTemp.createTempSync('dermaire-f7-plan-');
          final keys = disk.Keys(root);
          SecureRecoverySession? session;
          await w.run(() async {
            try {
              await w.login();
              final generation = api.sessionGeneration;
              bool active() =>
                  api.isCurrentSession(generation) &&
                  (doctor
                      ? api.canReadDoctorWorkspace
                      : api.canReadPatientClinicalStatus);
              Future<SecureRecoverySession> open() =>
                  SecureRecoverySession.open(
                    platform: keys,
                    owner: w.owner,
                    role: w.role,
                    authorized: active,
                    now: DateTime.now,
                  );
              session = await open();
              final kind = doctor ? 'reschedule' : 'acknowledge';
              final op = PendingIntent(
                path: 'clinical-plans/plan-1/$kind',
                attemptPath: 'clinical-plans/plan-1/attempts/$kind',
                body: {
                  'expected_revision': 1,
                  if (!doctor) 'consent': true,
                  if (doctor) ...{
                    'local_due': '2027-01-12T10:00',
                    'timezone': 'Africa/Cairo',
                    'fold': 0,
                  },
                },
                identityScope: {
                  'patient_id': 'patient-1',
                  'doctor_id': 'doctor-1',
                  'access_id': 'grant-patient-1',
                },
              );
              final i = identity(op, w.owner, w.role),
                  now = DateTime.now().toUtc();
              w.mode = 'lost after';
              await session!.prepareAndSend(
                JournalEntry(
                  identity: i,
                  createdAt: now,
                  reviewAt: now.add(const Duration(days: 1)),
                  phase: JournalPhase.prepared,
                ),
                () async {
                  expect(
                    (await session!.journal.read(i))!.phase,
                    JournalPhase.unconfirmed,
                  );
                  await api.integrationResource(
                    op.path,
                    generation,
                    method: op.method,
                    body: op.body,
                    key: op.key,
                  );
                },
              );
              session!.suspend();
              session = await open();
              final restored = (await session!.restore()).single.identity;
              if (newer) {
                w.plan = {...w.plan, 'revision': 3, 'state': 'cancelled'};
              }
              final catalog = RecoveryReaderCatalog(api, generation);
              expect(
                await session!.reconcile(
                  restored,
                  catalog.readerFor(restored)!,
                ),
                newer
                    ? JournalPhase.reviewRequired
                    : JournalPhase.receiptRecorded,
              );
              expect(w.sends, hasLength(1));
              expect(w.sends.single.headers['Idempotency-Key'], restored.key);
              expect(w.receipts[restored.key]!['revision'], 2);
              expect(w.plan['revision'], newer ? 3 : 2);
            } finally {
              session?.suspend();
              await api.init();
              root.deleteSync(recursive: true);
            }
          });
        },
      );
    }
    test(
      'catalog preserves unsupported contracts and session namespace doctor=$doctor',
      () async {
        final w = fixture.DoctorWire()..role = doctor ? 'doctor' : 'patient';
        await w.run(() async {
          await w.login();
          final catalog = RecoveryReaderCatalog(api, api.sessionGeneration);
          OperationIdentity i(String path, String receipt) => OperationIdentity(
            owner: w.owner,
            role: w.role,
            path: path,
            receiptPath: receipt,
            key: 'a' * 48,
            fingerprint: 'b' * 64,
          );
          for (final path in [
            'agent/requests/action-1/submit',
            'notifications/n-1/read',
            'routine/calendar-policy',
            'clinical-plans/plan-1/evaluation',
          ]) {
            expect(catalog.readerFor(i(path, '')), isNull);
          }
          final original = i(
            doctor ? 'doctor/patients/patient-1/notes' : 'products',
            doctor
                ? 'doctor/patients/patient-1/attempts/note'
                : 'products/attempts',
          );
          final scoped = OperationIdentity(
            owner: original.owner,
            role: original.role,
            path: original.path,
            receiptPath: original.receiptPath,
            key: original.key,
            fingerprint: original.fingerprint,
            scope: doctor
                ? {
                    'patient_id': 'patient-1',
                    'doctor_id': w.owner,
                    'access_id': 'grant-1',
                  }
                : {},
          );
          expect(catalog.readerFor(scoped), isNotNull);
          w.accepted = false;
          await api.readSafetyAcceptance();
          expect(catalog.readerFor(scoped), isNull);
          await api.logout();
          w.owner = 'another-owner';
          w.accepted = true;
          await w.login();
          expect(catalog.readerFor(scoped), isNull);
          expect(catalog.authorized, false);
          await api.init();
        });
      },
    );
  }
}
