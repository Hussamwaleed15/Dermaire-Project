import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/clinical/clinical_models.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/doctor/doctor_clinical_controller.dart';
import 'package:dermaire_app/doctor/doctor_clinical_ui.dart';
import 'package:dermaire_app/doctor/doctor_evidence_models.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;
import 'clinical_status_test.dart' as c;

final api = ApiService.instance;

class ClinicalWire extends f.DoctorWire {
  String mode = 'success';
  int posts = 0;
  final actions = <Map<String, dynamic>>[];
  final payloads = <Map<String, dynamic>>[];
  Completer<http.Response>? writeDelay;
  Map<String, dynamic> action(Map<String, dynamic> payload, [int? sequence]) =>
      {
        ...c.decision(owner: patient),
        'id': 'review-${sequence ?? actions.length + 1}',
        'doctor_id': owner,
        'access_id': 'grant-$patient',
        'sequence': sequence ?? actions.length + 1,
        'state': payload['state'],
        'recommendation': payload['recommendation'],
        'rationale': payload['rationale'],
        'patient_visible': payload['patient_visible'],
        'safety_at_review': c.safety(status: 'urgent'),
        'urgent_safety_preserved': true,
        'lower_than_current_safety': payload['recommendation'] == 'track',
        'diverges_from_current_safety': payload['recommendation'] == 'track',
      };
  Map<String, dynamic> get read => {
    ...c.review(
      owner: patient,
      evaluation: c.safety(status: 'urgent'),
    ),
    'current_decision': actions.lastOrNull,
    'history': actions,
    'latest_sequence': actions.lastOrNull?['sequence'] ?? 0,
    'state': actions.lastOrNull?['state'] ?? 'pending',
    'notes': saved,
  };
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    final path = request.url.path;
    if (path.endsWith('/notes') || path.endsWith('/reviews')) {
      requests.add(request);
      if (request.method == 'POST') {
        posts++;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        payloads.add(payload);
        if (writeDelay != null) return writeDelay!.future;
        if (['401', '403', '409', '422', '500'].contains(mode)) {
          return f.json({}, int.parse(mode));
        }
        if (mode == 'timeout') throw TimeoutException('synthetic');
        if (mode == 'offline') throw http.ClientException('synthetic');
        final row = path.endsWith('/notes')
            ? {
                ...note(payload['content'] as String),
                ...payload,
                'id': 'note-$posts',
              }
            : action(payload);
        if (mode == 'foreign') row['patient_id'] = 'other-patient';
        if (mode == 'wrong author') row['doctor_id'] = 'other-doctor';
        if (mode == 'wrong sequence') row['sequence'] = 999;
        if (mode == 'missing receipt') return f.json({'ok': true}, 201);
        if (path.endsWith('/notes')) {
          saved.add(row);
        } else {
          actions.add(row);
        }
        return f.json(row, 201);
      }
      if (posts > 0 && mode == 'denied readback') return f.json({}, 403);
      if (posts > 0 && mode == 'lost readback') {
        throw http.ClientException('synthetic readback');
      }
      if (mode == 'superseded' && posts > 0 && actions.length == 1) {
        actions.add(
          action({
            'state': 'in_review',
            'recommendation': null,
            'rationale': null,
            'patient_visible': false,
          }),
        );
      }
      return f.json(path.endsWith('/notes') ? saved : read);
    }
    if (path.endsWith('/doctor/patients/$patient') && mode == 'revoked') {
      return f.json({}, 403);
    }
    return super.call(request);
  }
}

Future<
  (
    DoctorWorkspaceController,
    DoctorConnectionController,
    DoctorClinicalController,
  )
>
editor(ClinicalWire wire) async {
  await wire.login();
  final parent = DoctorWorkspaceController(
    AccessSession(userId: wire.owner, role: UserRole.doctor),
  );
  await parent.refresh();
  final connection = DoctorConnectionController(parent, wire.patient);
  await connection.refresh();
  final clinical = DoctorClinicalController(connection);
  await clinical.refresh();
  return (parent, connection, clinical);
}

void clean(
  (
    DoctorWorkspaceController,
    DoctorConnectionController,
    DoctorClinicalController,
  )
  v,
) {
  v.$3.dispose();
  v.$2.dispose();
  v.$1.dispose();
}

Future<bool> submit(DoctorClinicalController editor, String kind) =>
    kind == 'notes'
    ? editor.addNote(
        content: 'Explicit clinician follow-up context.',
        priority: 'review',
        visible: true,
        followUp: 'Review after three weeks',
        category: 'follow-up',
      )
    : editor.recordReview(
        state: 'follow_up_needed',
        expectedSequence: 0,
        recommendation: 'track',
        rationale: 'Clinician review remains separate from urgent safety.',
        visible: true,
      );
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final kind in ['notes', 'reviews']) {
    for (final mode in [
      'success',
      '403',
      '409',
      '422',
      '500',
      'timeout',
      'offline',
      'foreign',
      'wrong author',
      'missing receipt',
      'denied readback',
      'lost readback',
    ]) {
      test('$kind write $mode requires actual receipt and GET', () async {
        final wire = ClinicalWire();
        await wire.run(() async {
          final v = await editor(wire);
          wire.mode = mode;
          expect(await submit(v.$3, kind), mode == 'success');
          expect(wire.posts, 1);
          expect(
            api.uncertainDoctorWrites.contains('patient-1:$kind'),
            !['success', '403', '409', '422'].contains(mode),
          );
          if (mode == 'success') {
            expect(v.$3.confirmed, true);
            expect(wire.payloads.single['patient_visible'], true);
            if (kind == 'notes') {
              expect(v.$3.notes.single.followUp, 'Review after three weeks');
              expect(
                wire.payloads.single.keys,
                unorderedEquals([
                  'content',
                  'priority',
                  'patient_visible',
                  'follow_up',
                  'category',
                ]),
              );
            } else {
              expect(v.$3.review!.sequence, 1);
              expect(v.$3.review!.safety.rawStatus, 'urgent');
              expect(v.$3.review!.decision!.lower, true);
              expect(wire.payloads.single['expected_sequence'], 0);
            }
          }
          if ([
            'timeout',
            'offline',
            'foreign',
            'missing receipt',
          ].contains(mode)) {
            wire.mode = 'success';
            await v.$3.refresh();
            expect(await submit(v.$3, kind), false);
            expect(wire.posts, 1);
          }
          if (mode == 'lost readback') {
            wire.mode = 'success';
            expect(await v.$3.refresh(), true);
            expect(api.uncertainDoctorWrites, isEmpty);
            expect(api.pendingDoctorReceipts, isEmpty);
            expect(wire.posts, 1);
          }
          clean(v);
        });
      });
    }
  }
  for (final mode in ['current401', 'old401']) {
    test('clinical $mode is scoped to the original session', () async {
      final wire = ClinicalWire();
      await wire.run(() async {
        final v = await editor(wire);
        if (mode == 'current401') {
          wire.mode = '401';
          expect(await submit(v.$3, 'notes'), false);
          expect(api.isAuthenticated, false);
        } else {
          wire.writeDelay = Completer();
          final pending = submit(v.$3, 'notes');
          await Future<void>.delayed(Duration.zero);
          await api.init();
          wire.owner = 'doctor-b';
          await wire.login();
          wire.writeDelay!.complete(f.json({}, 401));
          expect(await pending, false);
          expect(api.authenticatedOwner, 'doctor-b');
          expect(api.isAuthenticated, true);
        }
        expect(v.$3.notes, isEmpty);
        expect(api.uncertainDoctorWrites, isEmpty);
        clean(v);
      });
    });
  }
  test('stale editor sequence is rejected before POST', () async {
    final wire = ClinicalWire();
    await wire.run(() async {
      final v = await editor(wire);
      wire.actions.add(
        wire.action({'state': 'reviewed', 'patient_visible': false}),
      );
      expect(await submit(v.$3, 'reviews'), false);
      expect(wire.posts, 0);
      expect(v.$3.error, contains('changed elsewhere'));
      expect(v.$3.review, isNull);
      clean(v);
    });
  });
  test(
    'sequenced receipt mismatch is uncertain and cannot be replayed',
    () async {
      final wire = ClinicalWire();
      await wire.run(() async {
        final v = await editor(wire);
        wire.mode = 'wrong sequence';
        expect(await submit(v.$3, 'reviews'), false);
        expect(api.uncertainDoctorWrites, contains('patient-1:reviews'));
        clean(v);
      });
    },
  );
  test(
    'confirmed action superseded during readback is historical, never current',
    () async {
      final wire = ClinicalWire();
      await wire.run(() async {
        final v = await editor(wire);
        wire.mode = 'superseded';
        expect(await submit(v.$3, 'reviews'), true);
        expect(v.$3.review!.sequence, 2);
        expect(v.$3.review!.decision!.visible, false);
        expect(v.$3.outcome, contains('newer review'));
        expect(v.$3.review!.history.last.visible, true);
        clean(v);
      });
    },
  );
  for (final mode in [
    'duplicate',
    'patient switch',
    'logout',
    'doctor switch',
    'revoked',
    'role invalidation',
  ]) {
    test('clinical session $mode never publishes an old draft', () async {
      final wire = ClinicalWire();
      await wire.run(() async {
        final v = await editor(wire);
        if (mode == 'revoked') {
          wire.mode = 'revoked';
          expect(await submit(v.$3, 'notes'), false);
          expect(wire.posts, 0);
          clean(v);
          return;
        }
        wire.writeDelay = Completer();
        final write = submit(v.$3, 'notes');
        await Future<void>.delayed(Duration.zero);
        expect(wire.posts, 1);
        expect(await submit(v.$3, 'notes'), false);
        if (mode == 'patient switch') v.$1.selectPatient('not-authorized');
        if (mode == 'logout') await api.logout();
        if (mode == 'doctor switch') {
          await api.init();
          wire.owner = 'doctor-b';
          await wire.login();
        }
        if (mode == 'role invalidation') {
          wire.role = 'patient';
          await api.readSafetyAcceptance();
        }
        final row = {
          ...wire.note('Explicit clinician follow-up context.'),
          ...wire.payloads.single,
          'id': 'note-1',
          'doctor_id': 'doctor-1',
        };
        wire.saved.add(row);
        wire.writeDelay!.complete(f.json(row, 201));
        expect(await write, mode == 'duplicate');
        if (mode != 'duplicate') expect(v.$3.notes, isEmpty);
        if (mode == 'patient switch') {
          expect(api.uncertainDoctorWrites, contains('patient-1:notes'));
        }
        if (['logout', 'doctor switch'].contains(mode)) {
          expect(api.uncertainDoctorWrites, isEmpty);
        }
        expect(wire.posts, 1);
        clean(v);
      });
    });
  }
  for (final type in [
    'content',
    'priority',
    'follow-up',
    'category',
    'rationale',
    'recommendation',
    'state',
  ]) {
    test('clinical invalid $type makes no mutation', () async {
      final wire = ClinicalWire();
      await wire.run(() async {
        final v = await editor(wire);
        final result = switch (type) {
          'content' => await v.$3.addNote(content: 'short'),
          'priority' => await v.$3.addNote(
            content: 'Sufficient clinical context',
            priority: 'unknown',
          ),
          'follow-up' => await v.$3.addNote(
            content: 'Sufficient clinical context',
            followUp: 'x' * 101,
          ),
          'category' => await v.$3.addNote(
            content: 'Sufficient clinical context',
            category: 'x' * 51,
          ),
          'rationale' => await v.$3.recordReview(
            state: 'reviewed',
            expectedSequence: 0,
            recommendation: 'track',
          ),
          'recommendation' => await v.$3.recordReview(
            state: 'reviewed',
            expectedSequence: 0,
            recommendation: 'diagnosis',
            rationale: 'Enough rationale',
          ),
          _ => await v.$3.recordReview(state: 'approved', expectedSequence: 0),
        };
        expect(result, false);
        expect(wire.posts, 0);
        clean(v);
      });
    });
  }
  test(
    'doctor private current review can never fall back to older visible action',
    () {
      final wire = ClinicalWire();
      wire.actions.add(
        wire.action({'state': 'reviewed', 'patient_visible': true}),
      );
      wire.actions.add(
        wire.action({'state': 'in_review', 'patient_visible': false}),
      );
      expect(
        DoctorReviewRead.fromApi(wire.read, wire.patient).decision!.visible,
        false,
      );
      final value = wire.read..['current_decision'] = wire.actions.first;
      expect(
        () => DoctorReviewRead.fromApi(value, wire.patient),
        throwsFormatException,
      );
    },
  );
  for (final mode in ['visible', 'private', 'foreign']) {
    test('patient notes $mode cannot replace or leak a current decision', () {
      final wire = ClinicalWire();
      final value = wire.read;
      final note = {
        ...wire.note('Patient-visible recorded clinician guidance.'),
        'patient_visible': mode != 'private',
        'follow_up': 'Review after three weeks',
      };
      if (mode == 'foreign') note['patient_id'] = 'foreign';
      value['notes'] = [note];
      final read = ClinicianReview.fromApi(value, owner: wire.patient);
      expect(read.supported, true);
      expect(read.decision, isNull);
      expect(read.notes?.length, mode == 'visible' ? 1 : null);
      expect(read.safety.rawStatus, 'urgent');
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'clinical editor light/dark=$dark large/reduced offers text, not scheduling',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final wire = ClinicalWire();
        await wire.run(() async {
          final v = await editor(wire);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              home: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: DoctorClinicalScreen(connection: v.$2),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('clinicalFollowUp')),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.textContaining('Text only;'), findsWidgets);
          await tester.scrollUntilVisible(
            find.byKey(const Key('recordClinicalReview')),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Record review action'), findsOneWidget);
          expect(wire.posts, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          clean(v);
          await api.logout();
        });
      },
    );
  }
}
