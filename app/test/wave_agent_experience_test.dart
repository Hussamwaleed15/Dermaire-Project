import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/agent/server_agent_ui.dart';
import 'package:dermaire_app/agent/server_agent_models.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'wave_agent_test.dart' as f;

BrokerAction action(
  String state, {
  String status = 'self_tracking_request',
  bool routed = false,
  bool expired = false,
}) {
  final isPreview = state == 'preview', revoked = state == 'revoked';
  return BrokerAction({
    'id': 'request-1',
    'kind': 'propose_followup',
    'state': state,
    'revision': isPreview || revoked ? 1 : 2,
    'payload': revoked
        ? <String, dynamic>{}
        : {'kind': 'propose_followup', 'rationale': 'Synthetic rationale'},
    'previewed_at': expired ? '2020-01-01T00:00:00Z' : '2070-01-01T00:00:00Z',
    'preview_valid_until': expired
        ? '2020-01-01T00:05:00Z'
        : '2070-01-01T00:05:00Z',
    'confirmed_at': isPreview || revoked ? null : '2070-01-01T00:01:00Z',
    'result': isPreview || revoked
        ? null
        : {
            'request_id': 'request-1',
            'status': status,
            'clinical_clearance': false,
            'medical_resources_modified': false,
            'clinician_notified': false,
            'notification_enqueued': routed,
            'provenance': 'user_confirmed_request',
            if (routed) ...{
              'doctor_id': 'doctor-1',
              'access_id': 'grant-1',
              'consent_version': 1,
              'expires_at': '2070-01-01T01:00:00Z',
              'submitted_at': '2070-01-01T00:01:00Z',
            },
          },
    'requires_explicit_confirmation': isPreview,
    'medical_change': false,
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  test(
    'unrouted confirmed request is not waiting for an informed clinician',
    () {
      expect(
        action('confirmed', status: 'pending_clinician_review').stage,
        BrokerActionStage.confirmedRequest,
      );
    },
  );
  test('routed request and actual clinician decision remain distinct', () {
    expect(
      action(
        'confirmed',
        status: 'pending_clinician_review',
        routed: true,
      ).stage,
      BrokerActionStage.pendingClinician,
    );
    for (final state in ['accepted', 'rejected', 'reviewed']) {
      expect(
        action('confirmed', status: state, routed: true).stage,
        BrokerActionStage.doctorDecision,
      );
    }
  });
  test('preview expiry and memory withdrawal do not imply execution', () {
    expect(action('preview').stage, BrokerActionStage.preview);
    expect(
      action('preview', expired: true).stage,
      BrokerActionStage.expiredPreview,
    );
    expect(action('revoked').stage, BrokerActionStage.withdrawn);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'Agent overview and fresh per-session consent dark=$dark 320px200%',
      (t) async {
        t.view.physicalSize = const Size(320, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final w = f.AgentWire();
        await w.run(() async {
          await w.login();
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
              home: const ServerAgentScreen(),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('No session selected'), findsOneWidget);
          for (final key in ['agentReadConsent', 'agentProposalConsent']) {
            final tile = find.byKey(Key(key));
            await t.scrollUntilVisible(
              tile,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            final checkbox = find.descendant(
              of: tile,
              matching: find.byType(Checkbox),
            );
            await t.ensureVisible(checkbox);
            await t.pumpAndSettle();
            await t.tap(checkbox);
            await t.pumpAndSettle();
          }
          await t.scrollUntilVisible(
            find.text('Create consented session'),
            180,
          );
          await t.ensureVisible(find.text('Create consented session'));
          await t.pumpAndSettle();
          await t.tap(find.text('Create consented session'));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.text('Active consented session'),
            -250,
            maxScrolls: 50,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          expect(find.text('Active consented session'), findsOneWidget);
          await t.scrollUntilVisible(
            find.text('Create consented session'),
            250,
            maxScrolls: 70,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          for (final checkbox in t.widgetList<Checkbox>(
            find.byType(Checkbox),
          )) {
            expect(checkbox.value, false);
          }
          expect(w.savedActions, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await ApiService.instance.init();
        });
      },
    );
  }
  testWidgets('action-stage filter never submits or confirms a proposal', (
    t,
  ) async {
    final w = f.AgentWire();
    await w.run(() async {
      final c = await f.start(w);
      await c.preview('request_checkin', 'Synthetic check');
      c.dispose();
      await t.pumpWidget(const MaterialApp(home: ServerAgentScreen()));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Needs your confirmation'),
        250,
        maxScrolls: 50,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      final before = w.writesAgent;
      await t.tap(find.widgetWithText(ChoiceChip, 'Needs your confirmation'));
      await t.pumpAndSettle();
      expect(w.writesAgent, before);
      expect(w.savedActions.single['state'], 'preview');
      await t.pumpWidget(const SizedBox());
      await ApiService.instance.init();
    });
  });
}
