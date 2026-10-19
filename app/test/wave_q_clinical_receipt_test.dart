import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/doctor/doctor_clinical_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_clinical_reviews_test.dart' as c;
import 'm6_doctor_fixture.dart' as f;

class ClinicalContractWire extends c.ClinicalWire {
  bool loseAfterCommit = false;
  String receiptState = 'committed';
  int lookupStatus = 200, lookups = 0, duplicateRequests = 0;
  Map<String, dynamic> Function(Map<String, dynamic>)? changeReceipt;
  Completer<http.Response>? lookupDelay;
  final lookupStarted = Completer<void>();
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    final path = request.url.path;
    if (path.contains('/attempts/note/') ||
        path.contains('/attempts/review/')) {
      lookups++;
      if (!lookupStarted.isCompleted) lookupStarted.complete();
      if (lookupDelay != null) return lookupDelay!.future;
      if (lookupStatus != 200) return f.json({}, lookupStatus);
      var raw =
          jsonDecode(clinicalLookup(request).body) as Map<String, dynamic>;
      if (receiptState == 'unknown') {
        raw = {
          'schema_version': 1,
          'attempt_id': raw['attempt_id'],
          'status': 'unknown',
          'result': null,
          'retry_safe': false,
        };
      } else if (receiptState == 'expired') {
        raw = {...raw, 'status': 'expired', 'result': null};
      } else if (receiptState == 'erased') {
        raw = {...raw, 'result': null};
      }
      return f.json(changeReceipt?.call(raw) ?? raw);
    }
    if (request.method == 'POST' &&
        (path.endsWith('/notes') || path.endsWith('/reviews'))) {
      final key = request.headers['Idempotency-Key'];
      expect(key, matches(RegExp(r'^[a-f0-9]{48}$')));
      final previous = clinicalAttempts[key];
      if (previous != null) {
        duplicateRequests++;
        if (clinicalBodies[key] != request.body) return f.json({}, 409);
        return f.json(previous['result'], 201);
      }
      final result = await super.call(request);
      if (result.statusCode == 201 && loseAfterCommit) {
        throw TimeoutException('Synthetic response loss after commit');
      }
      return result;
    }
    return super.call(request);
  }
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
      '$kind committed but lost response resolves original receipt without second write',
      () async {
        final w = ClinicalContractWire();
        await w.run(() async {
          final v = await c.editor(w);
          try {
            w.loseAfterCommit = true;
            expect(await c.submit(v.$3, kind), false);
            final original = v.$3.pending(kind)!;
            expect(
              original.attemptPath,
              'doctor/patients/patient-1/attempts/${kind == 'notes' ? 'note' : 'review'}',
            );
            expect(original.recoveryScope['access_id'], 'grant-patient-1');
            expect(await c.submit(v.$3, kind), false);
            expect(w.posts, 1);
            expect(await v.$3.refresh(), true);
            expect(w.lookups, 1);
            expect(w.clinicalAttempts.keys.single, original.key);
            expect(api.integrationIntents, isEmpty);
            expect(api.uncertainDoctorWrites, isEmpty);
            expect(w.posts, 1);
            if (kind == 'reviews') {
              expect(v.$3.review!.safety.rawStatus, 'urgent');
            }
          } finally {
            c.clean(v);
          }
        });
      },
    );
    test(
      '$kind same frozen key/body duplicate stays one record, changed body conflicts',
      () async {
        final w = ClinicalContractWire();
        await w.run(() async {
          final v = await c.editor(w);
          try {
            w.loseAfterCommit = true;
            await c.submit(v.$3, kind);
            final original = v.$3.pending(kind)!;
            final response = await api.integrationResource(
              original.path,
              api.sessionGeneration,
              method: 'POST',
              body: original.body,
              key: original.key,
            );
            expect(
              (response.data as Map)['id'],
              w.clinicalAttempts[original.key]!['resource_id'],
            );
            await expectLater(
              api.integrationResource(
                original.path,
                api.sessionGeneration,
                method: 'POST',
                body: {
                  ...original.body,
                  if (kind == 'notes')
                    'content': 'Different explicit clinical content'
                  else
                    'state': 'reviewed',
                },
                key: original.key,
              ),
              throwsA(anything),
            );
            expect(w.posts, 1);
            expect(w.duplicateRequests, 2);
            expect(v.$3.pending(kind)!.key, original.key);
            await v.$3.refresh();
            expect(v.$3.pending(kind), isNull);
          } finally {
            c.clean(v);
          }
        });
      },
    );
    for (final state in ['unknown', 'expired', 'erased']) {
      test(
        '$kind $state receipt never unlocks replacement or claims write failed',
        () async {
          final w = ClinicalContractWire();
          await w.run(() async {
            final v = await c.editor(w);
            try {
              w.loseAfterCommit = true;
              await c.submit(v.$3, kind);
              final key = v.$3.pending(kind)!.key;
              w.receiptState = state;
              await v.$3.refresh();
              expect(v.$3.pending(kind)!.key, key);
              expect(api.uncertainDoctorWrites, contains('patient-1:$kind'));
              expect(await c.submit(v.$3, kind), false);
              expect(w.posts, 1);
              expect(
                v.$3.outcome,
                contains(
                  state == 'unknown' ? 'unknown' : 'expired or unavailable',
                ),
              );
            } finally {
              c.clean(v);
            }
          });
        },
      );
    }
    for (final field in [
      'actor_id',
      'patient_id',
      'access_id',
      'resource_id',
      'operation',
      'snapshot_basis',
    ]) {
      test('$kind rejects wrong receipt $field', () async {
        final w = ClinicalContractWire();
        await w.run(() async {
          final v = await c.editor(w);
          try {
            w.loseAfterCommit = true;
            await c.submit(v.$3, kind);
            final key = v.$3.pending(kind)!.key;
            w.changeReceipt = (v) => {...v, field: 'other'};
            await v.$3.refresh();
            expect(v.$3.notes, isEmpty);
            expect(v.$3.review, isNull);
            expect(w.posts, 1);
            expect(
              v.$3.pending(kind)?.key ?? api.quarantinedOperations.single.key,
              key,
            );
          } finally {
            c.clean(v);
          }
        });
      });
    }
    for (final status in [403, 404, 409, 503]) {
      test(
        '$kind receipt$status preserves original without unauthorized private UI',
        () async {
          final w = ClinicalContractWire();
          await w.run(() async {
            final v = await c.editor(w);
            try {
              w.loseAfterCommit = true;
              await c.submit(v.$3, kind);
              final key = v.$3.pending(kind)!.key;
              w.lookupStatus = status;
              await v.$3.refresh();
              expect(v.$3.notes, isEmpty);
              expect(v.$3.review, isNull);
              expect(
                v.$3.pending(kind)?.key ?? api.quarantinedOperations.single.key,
                key,
              );
              expect(await c.submit(v.$3, kind), false);
              expect(w.posts, 1);
            } finally {
              c.clean(v);
            }
          });
        },
      );
    }
  }
  for (final kind in ['notes', 'reviews']) {
    test('$kind rejects unsupported original schema', () async {
      final w = ClinicalContractWire();
      await w.run(() async {
        final v = await c.editor(w);
        try {
          w.loseAfterCommit = true;
          await c.submit(v.$3, kind);
          final key = v.$3.pending(kind)!.key;
          w.changeReceipt = (v) => {
            ...v,
            'result': {...v['result'] as Map, 'schema_version': 'future-99'},
          };
          await v.$3.refresh();
          expect(v.$3.notes, isEmpty);
          expect(v.$3.review, isNull);
          expect(v.$3.pending(kind)!.key, key);
          expect(w.posts, 1);
        } finally {
          c.clean(v);
        }
      });
    });
  }
  test('review receipt sequence matches original precondition', () async {
    final w = ClinicalContractWire();
    await w.run(() async {
      final v = await c.editor(w);
      try {
        w.loseAfterCommit = true;
        await c.submit(v.$3, 'reviews');
        w.changeReceipt = (v) => {
          ...v,
          'result': {...v['result'] as Map, 'sequence': 99},
        };
        await v.$3.refresh();
        expect(v.$3.review, isNull);
        expect(v.$3.pending('reviews'), isNotNull);
        expect(w.posts, 1);
      } finally {
        c.clean(v);
      }
    });
  });
  test(
    'original review receipt never overrides a newer current decision',
    () async {
      final w = ClinicalContractWire();
      await w.run(() async {
        final v = await c.editor(w);
        try {
          w.loseAfterCommit = true;
          await c.submit(v.$3, 'reviews');
          w.mode = 'superseded';
          await v.$3.refresh();
          expect(v.$3.review!.sequence, 2);
          expect(v.$3.review!.decision!.visible, false);
          expect(v.$3.outcome, contains('newer review'));
          expect(v.$3.pending('reviews'), isNull);
          expect(w.posts, 1);
        } finally {
          c.clean(v);
        }
      });
    },
  );
  test(
    'late clinical lookup after account change cannot restore original data',
    () async {
      final w = ClinicalContractWire();
      await w.run(() async {
        final v = await c.editor(w);
        try {
          w.loseAfterCommit = true;
          await c.submit(v.$3, 'notes');
          final key = v.$3.pending('notes')!.key;
          w.lookupDelay = Completer<http.Response>();
          final read = v.$3.refresh();
          await w.lookupStarted.future;
          await api.logout();
          w.owner = 'doctor-b';
          await w.login();
          w.lookupDelay!.complete(f.json(w.clinicalAttempts[key]));
          expect(await read, false);
          expect(v.$3.notes, isEmpty);
          expect(v.$3.review, isNull);
          expect(api.authenticatedOwner, 'doctor-b');
          expect(api.integrationIntents, isEmpty);
        } finally {
          c.clean(v);
        }
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'explicit clinical verification never sends duplicate dark=$dark 320px200%',
      (t) async {
        t.view.physicalSize = const Size(320, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final w = ClinicalContractWire();
        await w.run(() async {
          final v = await c.editor(w);
          try {
            w.loseAfterCommit = true;
            await c.submit(v.$3, 'notes');
            w.receiptState = 'unknown';
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
                home: DoctorClinicalScreen(connection: v.$2),
              ),
            );
            await t.pumpAndSettle();
            final verify = find.byKey(const Key('verifyClinicalnotes'));
            await t.scrollUntilVisible(
              verify,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await t.ensureVisible(verify);
            await t.pumpAndSettle();
            expect(api.integrationIntents, isNotEmpty);
            w.receiptState = 'committed';
            await t.tap(verify);
            await t.pumpAndSettle();
            expect(w.posts, 1);
            expect(api.integrationIntents, isEmpty);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
          } finally {
            c.clean(v);
            await api.init();
          }
        });
      },
    );
  }
}
