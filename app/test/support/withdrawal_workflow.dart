import 'contract_assertions.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/integration/private_view.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/consent/clinician_withdrawal.dart';
import '../wave_selective_withdrawal_test.dart' as grants;
import '../wave_plan_withdrawal_test.dart' as plans;

/// Reused unchanged by deterministic host widget and device integration entry.
/// ALL requests are intercepted; even a production URL is rejected before I/O.
Future<void> withdrawalWorkflow(
  WidgetTester t, {
  required bool dark,
  required bool large,
  bool device = false,
}) async {
  if (!device) {
    await t.binding.setSurfaceSize(Size(large ? 320 : 390, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }
  SharedPreferences.setMockInitialValues({});
  final api = ApiService.instance, oldBase = ApiService.instance.baseUrl;
  api.baseUrl = 'https://flutter-tests.invalid/api/v1';
  await api.init();
  final g = grants.Wire()..lose = false;
  final p = plans.Wire()..plan['kind'] = 'comparison';
  var evaluationDeletes = 0, loggedOut = 0;
  var job = <String, dynamic>{
    'schema_version': 'comparison-job-1',
    'id': 'original-job',
    'input': {'plan_id': 'plan-1'},
    'plan_revision': 1,
    'state': 'queued',
    'medical_resources_modified': false,
    'clinical_clearance': false,
  };
  DermaireState? state;
  Future<void> waitFor(bool Function() ready, String description) async {
    for (var frame = 0; frame < 100 && !ready(); frame++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), true, reason: description);
  }

  Future<void> tapVisible(Finder finder) async {
    bool found() {
      try {
        return finder.evaluate().isNotEmpty;
      } on StateError {
        return false;
      } // A lazy .first finder has no row yet.
    }

    for (var frame = 0; frame < 60 && !found(); frame++) {
      await t.pump(const Duration(milliseconds: 100));
      if (!found() &&
          find.byType(Scrollable).hitTestable().evaluate().isNotEmpty) {
        await t.drag(
          find.byType(Scrollable).hitTestable().first,
          const Offset(0, -180),
        );
      }
    }
    final selective = find
        .byWidgetPredicate(
          (w) =>
              w is PrivateView && w.controller is SelectiveWithdrawalController,
        )
        .evaluate();
    final c = selective.isEmpty
        ? null
        : (selective.first.widget as PrivateView).controller
              as SelectiveWithdrawalController;
    expect(
      found(),
      true,
      reason:
          'Authorized control missing; lifecycle=${t.binding.lifecycleState}; selective=${selective.length}; visible=${c?.visible}; busy=${c?.busy}; authenticated=${c?.authenticatedCurrent}; grants=${c?.grants.length}; error=${c?.error}',
    );
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Widget app(DermaireState s) => MaterialApp(
    theme: dark ? DermaireTheme.dark : DermaireTheme.light,
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(
        textScaler: TextScaler.linear(large ? 2 : 1),
        disableAnimations: large,
      ),
      child: child!,
    ),
    home: PatientEntryGate(key: ValueKey(g.owner), state: s),
  );
  await api.withSyntheticTransport(
    () async {
      try {
        await g.login();
        state = DermaireState();
        await t.pumpWidget(app(state!));
        await t.pumpAndSettle();
        expect(find.byType(AppShell), findsNothing);
        expect(api.hasConfirmedSafetyAcceptance, false);
        await waitFor(
          () => find.byType(SafetyResponsibilityScreen).evaluate().isNotEmpty,
          'Server consent read must resolve to the actual safety screen',
        );
        await tapVisible(find.text('Manage clinician access'));
        await tapVisible(find.text('Choose one clinician grant'));
        await tapVisible(find.text('Select this grant').first);
        await tapVisible(find.byType(Checkbox));
        await tapVisible(find.text('Revoke selected grant'));
        await waitFor(
          () => g.deletes == 1 && api.integrationIntents.isEmpty,
          'Original selective withdrawal must be confirmed before checking its result',
        );
        expect(g.deletes, 1);
        expect(g.rows.first['status'], 'revoked');
        expect(g.rows.last['status'], 'pending');
        Navigator.of(t.element(find.byType(SelectiveWithdrawalScreen))).pop();
        await t.pumpAndSettle();
        await tapVisible(find.text('Manage plan withdrawal'));
        await tapVisible(find.text('Withdraw from this plan'));
        await tapVisible(find.byType(Checkbox));
        await tapVisible(find.text('Cancel plan'));
        await waitFor(
          () =>
              p.plan['state'] == 'cancelled' && api.integrationIntents.isEmpty,
          'Original plan cancellation must complete server readback',
        );
        expect(p.plan['state'], 'cancelled');
        expect(p.sends.length, 1);
        await tapVisible(find.text('Manage evaluation withdrawal'));
        await tapVisible(find.byType(Checkbox));
        await tapVisible(find.text('Cancel evaluation job'));
        await waitFor(
          () => evaluationDeletes == 1 && api.integrationIntents.isEmpty,
          'Original evaluation cancellation must complete readback',
        );
        expect(evaluationDeletes, 1);
        expect(job['state'], 'cancelled');
        expect(p.plan['state'], 'cancelled');
        expect(find.byType(Image), findsNothing);
        expect(find.text(p.plan['purpose']), findsNothing);
        expect(api.integrationIntents, isEmpty);
        expect(api.hasConfirmedSafetyAcceptance, false);
        expect(g.accepts, 0);
        await api.logout();
        await t.pumpAndSettle();
        expect(loggedOut, 1);
        expect(api.integrationIntents, isEmpty);
        expect(find.text('First clinician'), findsNothing);
        await t.pumpWidget(const SizedBox());
        state!.dispose();
        state = null;
        g.owner = 'patient-2';
        g.rows.clear();
        await g.login();
        state = DermaireState();
        await t.pumpWidget(app(state!));
        await t.pumpAndSettle();
        expect(find.byType(AppShell), findsNothing);
        await waitFor(
          () => find.byType(SafetyResponsibilityScreen).evaluate().isNotEmpty,
          'New account must resolve its own safety state',
        );
        await tapVisible(find.text('Manage clinician access'));
        await tapVisible(find.text('Choose one clinician grant'));
        expect(find.text('No clinician grants returned.'), findsOneWidget);
        expect(find.text('First clinician'), findsNothing);
        expect(api.integrationIntents, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        state?.dispose();
        await api.init();
        api.baseUrl = oldBase;
      }
    },
    () => MockClient((r) async {
      expectContract(r.url.host, 'flutter-tests.invalid');
      if (r.url.path.endsWith('/auth/logout')) {
        loggedOut++;
        return http.Response('{}', 200);
      }
      if (r.url.path.endsWith('/evaluation')) {
        if (r.method == 'DELETE') {
          expectContract(r.headers['Idempotency-Key'], isNull);
          expectContract(
            r.url.queryParameters['expected_revision'],
            '${p.plan['revision']}',
          );
          evaluationDeletes++;
          p.plan['revision'] = (p.plan['revision'] as int) + 1;
          job = {
            ...job,
            'state': 'cancelled',
            'plan_revision': p.plan['revision'],
          };
        }
        return http.Response(jsonEncode(job), 200);
      }
      if (r.url.path.contains('/clinical-plans')) return p.call(r);
      return g.call(r);
    }),
  );
}
