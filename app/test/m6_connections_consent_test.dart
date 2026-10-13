import 'dart:async';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/doctor/patient_access.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

final api = ApiService.instance;

class GrantWire extends f.DoctorWire {
  GrantWire() {
    owner = 'patient-1';
    role = 'patient';
  }
  String mode = 'success', status = 'active';
  int deletes = 0;
  bool readbackFailure = false;
  Completer<http.Response>? delayed;
  Completer<http.Response>? deleteDelay;
  Map<String, dynamic> get access => {
    'id': 'grant-a',
    'patient_id': owner,
    'doctor_id': 'doctor-1',
    'granted_by': owner,
    'status': status,
    'created_at': '2026-10-01T00:00:00Z',
    'expires_at': '2090-10-01T00:00:00Z',
    'claimed_at': '2026-10-01T01:00:00Z',
    'revoked_at': status == 'revoked' ? '2026-10-14T01:00:00Z' : null,
    'revoked_by': status == 'revoked' ? owner : null,
  };
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    if (request.url.path.endsWith('/doctor/access')) {
      requests.add(request);
      if (delayed != null) return delayed!.future;
      if (mode == 'denied readback' && deletes > 0) return f.json({}, 403);
      if (readbackFailure) {
        throw http.ClientException('synthetic readback loss');
      }
      final row = access;
      if (mode == 'foreign read') row['patient_id'] = 'other-patient';
      if (mode == 'unknown status') row['status'] = 'unknown';
      if (mode == 'bad expiry') row['expires_at'] = 'invalid';
      if (mode == 'view only') row['export_consent'] = false;
      return f.json([row]);
    }
    if (request.url.path.endsWith('/doctor/access/grant-a')) {
      requests.add(request);
      deletes++;
      if (deleteDelay != null) return deleteDelay!.future;
      if (mode == 'denied') return f.json({}, 403);
      if (mode == 'timeout unknown') throw TimeoutException('synthetic');
      status = 'revoked';
      if (mode == 'timeout persisted') {
        throw TimeoutException('synthetic after commit');
      }
      if (mode == 'missing receipt') return f.json({'success': true});
      if (mode == 'foreign receipt') {
        final row = access;
        row['patient_id'] = 'other-patient';
        return f.json(row);
      }
      if (mode == 'lost readback') readbackFailure = true;
      return f.json(access);
    }
    return super.call(request);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final action in ['generate', 'claim']) {
    test('unsafe $action never calls a network route', () async {
      final wire = GrantWire();
      await wire.run(() async {
        await wire.login();
        final before = wire.requests.length;
        await expectLater(
          action == 'generate'
              ? api.generateDoctorQr()
              : api.claimDoctorAccess('opaque-token'),
          throwsA(isA<ApiException>()),
        );
        expect(wire.requests.length, before);
      });
    });
  }
  for (final mode in [
    'success',
    'view only',
    'foreign read',
    'unknown status',
    'bad expiry',
  ]) {
    test('actual grants $mode are honest', () async {
      final wire = GrantWire()..mode = mode;
      await wire.run(() async {
        await wire.login();
        final c = PatientAccessController();
        await c.refresh();
        expect(c.grants != null, ['success', 'view only'].contains(mode));
        expect(wire.deletes, 0);
        c.dispose();
      });
    });
  }
  for (final mode in [
    'success',
    'denied',
    'timeout unknown',
    'timeout persisted',
    'missing receipt',
    'foreign receipt',
    'lost readback',
    'denied readback',
  ]) {
    test('revocation $mode requires receipt and current GET', () async {
      final wire = GrantWire()..mode = mode;
      await wire.run(() async {
        await wire.login();
        final c = PatientAccessController();
        await c.refresh();
        expect(await c.revoke('grant-a'), mode == 'success');
        expect(wire.deletes, 1);
        if (mode != 'success') expect(c.grants, isNull);
        expect(
          api.uncertainGrantRevocations.contains('grant-a'),
          !['success', 'denied'].contains(mode),
        );
        if (mode == 'timeout unknown') {
          await c.refresh();
          expect(await c.revoke('grant-a'), false);
          expect(wire.deletes, 1);
        }
        if (mode == 'timeout persisted' || mode == 'lost readback') {
          wire.readbackFailure = false;
          await c.refresh();
          expect(c.grants!.single.confirmedRevoked, true);
          expect(api.uncertainGrantRevocations, isEmpty);
          expect(wire.deletes, 1);
        }
        c.dispose();
      });
    });
  }
  test('note201 followed by denied GET remains an uncertain write', () async {
    final wire = f.DoctorWire()..noteMode = 'readback denied';
    await wire.run(() async {
      await wire.login();
      const session = AccessSession(userId: 'doctor-1', role: UserRole.doctor);
      final parent = DoctorWorkspaceController(session);
      await parent.refresh();
      expect(
        await parent.addNote(
          parent.visible.single,
          'A confirmed receipt still needs readback.',
        ),
        false,
      );
      expect(api.uncertainDoctorWrites, contains('patient-1:notes'));
      expect(parent.patients, isEmpty);
      expect(wire.writes, 1);
      parent.dispose();
    });
  });
  for (final mode in [
    'duplicate',
    'logout during revoke',
    'switch during revoke',
  ]) {
    test('pending revocation $mode is isolated', () async {
      final wire = GrantWire();
      await wire.run(() async {
        await wire.login();
        final c = PatientAccessController();
        await c.refresh();
        wire.deleteDelay = Completer();
        final write = c.revoke('grant-a');
        await Future<void>.delayed(Duration.zero);
        expect(wire.deletes, 1);
        expect(await c.revoke('grant-a'), false);
        if (mode == 'logout during revoke') await api.logout();
        if (mode == 'switch during revoke') {
          await api.init();
          wire.owner = 'patient-b';
          await wire.login();
        }
        wire.status = 'revoked';
        wire.deleteDelay!.complete(f.json(wire.access));
        expect(await write, mode == 'duplicate');
        expect(wire.deletes, 1);
        if (mode != 'duplicate') {
          expect(c.grants, isNull);
          expect(api.uncertainGrantRevocations, isEmpty);
        }
        if (mode == 'switch during revoke') {
          expect(api.authenticatedOwner, 'patient-b');
        }
        c.dispose();
      });
    });
  }
  for (final mode in [
    'logout',
    'account switch',
    'old401',
    'current401',
    'revoke consent',
  ]) {
    test('grant read $mode cannot resurrect access', () async {
      final wire = GrantWire();
      await wire.run(() async {
        await wire.login();
        final c = PatientAccessController();
        wire.delayed = Completer();
        final read = c.refresh();
        await Future<void>.delayed(Duration.zero);
        if (mode == 'logout') await api.logout();
        if (mode == 'account switch' || mode == 'old401') {
          await api.init();
          wire.owner = 'patient-b';
          await wire.login();
        }
        if (mode == 'revoke consent') {
          wire.accepted = false;
          await api.readSafetyAcceptance();
        }
        wire.delayed!.complete(
          f.json([wire.access], mode.contains('401') ? 401 : 200),
        );
        await read;
        expect(c.grants, isNull);
        if (mode == 'old401' || mode == 'account switch') {
          expect(api.authenticatedOwner, 'patient-b');
        }
        c.dispose();
      });
    });
  }
  for (final mode in [
    'success',
    'denied',
    'expired',
    'wrong patient',
    'logout',
    'switch doctor',
  ]) {
    test('patient selection fresh authorization $mode', () async {
      final wire = f.DoctorWire();
      await wire.run(() async {
        await wire.login();
        const session = AccessSession(
          userId: 'doctor-1',
          role: UserRole.doctor,
        );
        final parent = DoctorWorkspaceController(session);
        await parent.refresh();
        final c = DoctorConnectionController(parent, 'patient-1');
        wire.pending = Completer();
        final read = c.refresh();
        await Future<void>.delayed(Duration.zero);
        if (mode == 'logout') await api.logout();
        if (mode == 'switch doctor') {
          await api.init();
          wire.owner = 'doctor-b';
          await wire.login();
        }
        final grant = wire.grant();
        if (mode == 'expired') {
          grant['status'] = 'expired';
          grant['expires_at'] = '2020-01-01T00:00:00Z';
        }
        wire.pending!.complete(
          f.json({
            'patient_id': mode == 'wrong patient' ? 'other' : 'patient-1',
            'full_name': 'Selected patient',
            'access': grant,
          }, mode == 'denied' ? 403 : 200),
        );
        await read;
        expect(c.confirmed, mode == 'success');
        expect(c.record != null, mode == 'success');
        if (mode == 'switch doctor') expect(api.doctorOwner, 'doctor-b');
        c.dispose();
        parent.dispose();
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets('real patient sharing dark=$dark has no QR/export fiction', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final wire = GrantWire();
      await wire.run(() async {
        await wire.login();
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const PatientAccessScreen(),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Clinician access'), findsOneWidget);
        expect(find.text('Export report'), findsNothing);
        expect(find.text('Valid for 7 days'), findsNothing);
        expect(find.text('Expires Apr 29, 2025'), findsNothing);
        expect(
          find.text('The previous link can no longer be used.'),
          findsNothing,
        );
        await t.scrollUntilVisible(
          find.text('Revoke access'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(find.text('Server status: active'), findsOneWidget);
        expect(t.takeException(), isNull);
        final semantics = t.ensureSemantics();
        expect(t, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
        await api.init();
        await t.pumpAndSettle();
        expect(
          find.text(
            'Patient access management is unavailable for this session.',
          ),
          findsOneWidget,
        );
        await t.pumpWidget(const SizedBox());
      });
    });
  }
}
