import 'dart:async';
import 'package:dermaire_app/agent/agent_domain.dart';
import 'package:dermaire_app/agent/agent_controller.dart';
import 'package:dermaire_app/agent/agent_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'assistance_evidence_test.dart' as a;
import 'private_capture_history_test.dart' as h;
import 'observation_test.dart' as o;

final api = ApiService.instance;
AgentProposal proposal({
  String owner = 'a',
  int revision = 1,
  bool fresh = true,
  AgentActionState status = AgentActionState.proposed,
  AgentConsentState consent = AgentConsentState.unknown,
  AgentAuthority authority = AgentAuthority.aiSuggestion,
  AgentActionKind kind = AgentActionKind.recordObservation,
}) => AgentProposal(
  id: 'proposal',
  owner: owner,
  revision: revision,
  kind: kind,
  authority: authority,
  status: status,
  fresh: fresh,
  parameters: {'report': 'synthetic exact draft'},
  consent: AgentConsent(
    state: consent,
    purpose: 'synthetic action purpose',
    scopes: {AgentContextScope.observations},
    receiptId: consent == AgentConsentState.serverConfirmed
        ? 'synthetic-receipt'
        : null,
  ),
  resultRecordId: status == AgentActionState.succeeded
      ? 'synthetic-server-result'
      : null,
  completedAt: status == AgentActionState.succeeded
      ? DateTime.utc(2026, 10, 13)
      : null,
  evidenceIds: ['synthetic-evidence'],
);

class FakeAgent implements AgentRepository {
  AgentProposal? value = proposal();
  Future<AgentProposal?> Function()? pending;
  int writes = 0;
  @override
  Future<AgentProposal?> readProposal(
    String id,
    AgentReadContext context,
  ) async => pending == null ? value : pending!();
  @override
  Future<void> execute(AgentProposal proposal, AgentReadContext context) async {
    writes++;
  }

  @override
  Future<void> cancel(AgentProposal proposal, AgentReadContext context) async {
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final state in AgentConsentState.values) {
    test(
      'consent $state cannot enable execution or context expansion',
      () async {
        final f = a.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeAgent()..value = proposal(consent: state);
          final ctrl = AgentController(
            api,
            proposalId: 'proposal',
            repository: repo,
          );
          await ctrl.refresh();
          ctrl.selectLocally({AgentContextScope.imageReferences});
          ctrl.reviewLocally();
          expect(ctrl.locallyReviewed, true);
          expect(ctrl.canExecute, false);
          expect(ctrl.canTransmitExpandedContext, false);
          await expectLater(ctrl.execute(), throwsA(isA<AgentUnsupported>()));
          await expectLater(ctrl.cancel(), throwsA(isA<AgentUnsupported>()));
          expect(repo.writes, 0);
          ctrl.dispose();
          await f.done();
        });
      },
    );
  }
  for (final authority in AgentAuthority.values) {
    test('authority $authority stays distinct', () {
      final p = proposal(authority: authority);
      expect(p.authority, authority);
      expect(() => p.parameters['new'] = 'fake', throwsUnsupportedError);
      expect(() => p.consent.scopes.clear(), throwsUnsupportedError);
    });
  }
  for (final status in AgentActionState.values) {
    test(
      'future status $status can be represented without fabricating IDs or execution',
      () {
        final p = proposal(status: status);
        expect(p.status, status);
        if (status == AgentActionState.succeeded) {
          expect(p.resultRecordId, 'synthetic-server-result');
        } else {
          expect(p.resultRecordId, isNull);
        }
      },
    );
  }
  test(
    'successful status and server-confirmed consent need provided records',
    () {
      expect(
        () => AgentConsent(
          state: AgentConsentState.serverConfirmed,
          purpose: 'p',
          scopes: {},
        ),
        throwsFormatException,
      );
      expect(
        () => AgentProposal(
          id: 'p',
          owner: 'a',
          revision: 1,
          kind: AgentActionKind.recordObservation,
          authority: AgentAuthority.aiSuggestion,
          status: AgentActionState.succeeded,
          fresh: true,
          parameters: {},
          consent: AgentConsent(
            state: AgentConsentState.unknown,
            purpose: 'p',
            scopes: {},
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'default unsupported repository makes zero speculative HTTP or fake empty history',
    () async {
      final f = a.Fixture();
      await f.run(() async {
        await f.login();
        final n = f.requests.length;
        const repo = UnsupportedAgentRepository();
        final context = AgentReadContext('a', api.sessionGeneration);
        await expectLater(
          repo.readProposal('proposal', context),
          throwsA(isA<AgentUnsupported>()),
        );
        await expectLater(
          repo.execute(proposal(), context),
          throwsA(isA<AgentUnsupported>()),
        );
        await expectLater(
          repo.cancel(proposal(), context),
          throwsA(isA<AgentUnsupported>()),
        );
        final ctrl = AgentController(api, proposalId: 'proposal');
        await ctrl.refresh();
        expect(ctrl.state, AgentReadState.unavailable);
        expect(ctrl.durableMemoryAvailable, false);
        expect(f.requests.length, n);
        ctrl.dispose();
        await f.done();
      });
    },
  );
  for (final status in [
    AgentActionState.superseded,
    AgentActionState.cancelled,
  ]) {
    test('$status and older proposal cannot restore confirmation', () async {
      final f = a.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeAgent()..value = proposal(revision: 2, status: status);
        final ctrl = AgentController(
          api,
          proposalId: 'proposal',
          repository: repo,
        );
        await ctrl.refresh();
        expect(ctrl.state, AgentReadState.stale);
        repo.value = proposal();
        await ctrl.refresh();
        expect(ctrl.state, AgentReadState.failed);
        expect(ctrl.proposal, isNull);
        ctrl.dispose();
        await f.done();
      });
    });
  }
  test('stale/foreign proposal is not presented as active', () async {
    final f = a.Fixture();
    await f.run(() async {
      await f.login();
      final repo = FakeAgent()..value = proposal(fresh: false);
      final ctrl = AgentController(
        api,
        proposalId: 'proposal',
        repository: repo,
      );
      await ctrl.refresh();
      expect(ctrl.state, AgentReadState.stale);
      repo.value = proposal(owner: 'b');
      await ctrl.refresh();
      expect(ctrl.state, AgentReadState.failed);
      ctrl.dispose();
      await f.done();
    });
  });
  for (final action in ['switch', 'logout', 'revoke', 'dispose']) {
    test('$action rejects late proposals/local choices', () async {
      final f = a.Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<AgentProposal?>();
        final repo = FakeAgent()..pending = () => pending.future;
        final ctrl = AgentController(
          api,
          proposalId: 'proposal',
          repository: repo,
        );
        ctrl.selectLocally({AgentContextScope.profile});
        final read = ctrl.refresh();
        if (action == 'switch') {
          await f.login('b');
        } else if (action == 'logout') {
          await api.logout();
        } else if (action == 'revoke') {
          f.noConsent = true;
          await f.state.account.hydrate(reuseConsent: false);
        } else {
          ctrl.dispose();
        }
        pending.complete(proposal());
        await read;
        expect(ctrl.proposal, isNull);
        expect(ctrl.locallySelectedScopes, isEmpty);
        if (action != 'dispose') ctrl.dispose();
        await f.done();
      });
    });
  }
  test(
    'concurrent newest read wins and repeated execution attempts never write',
    () async {
      final f = a.Fixture();
      await f.run(() async {
        await f.login();
        final first = Completer<AgentProposal?>(),
            second = Completer<AgentProposal?>();
        int reads = 0;
        final repo = FakeAgent()
          ..pending = () => reads++ == 0 ? first.future : second.future;
        final ctrl = AgentController(
          api,
          proposalId: 'proposal',
          repository: repo,
        );
        final p = ctrl.refresh(), q = ctrl.refresh();
        second.complete(proposal(revision: 2));
        await q;
        first.complete(proposal());
        await p;
        expect(ctrl.proposal!.revision, 2);
        await expectLater(ctrl.execute(), throwsA(isA<AgentUnsupported>()));
        await expectLater(ctrl.execute(), throwsA(isA<AgentUnsupported>()));
        expect(repo.writes, 0);
        ctrl.dispose();
        await f.done();
      });
    },
  );
  test('timeout and old401 do not expose a proposal or expire B', () async {
    final f = a.Fixture()..pendingResponse = Completer();
    await f.run(() async {
      await f.login();
      final repo = FakeAgent()
        ..pending = () async {
          await api.patientInformationalPost(
            'assistance',
            'synthetic question',
            api.sessionGeneration,
          );
          return proposal();
        };
      final ctrl = AgentController(
        api,
        proposalId: 'proposal',
        repository: repo,
      );
      final p = ctrl.refresh();
      await Future<void>.delayed(Duration.zero);
      await f.login('b');
      f.pendingResponse!.complete(o.jsonResponse({}, 401));
      await p;
      expect(api.observationOwner, 'b');
      expect(ctrl.proposal, isNull);
      ctrl.dispose();
      final pending = Completer<AgentProposal?>();
      final next = AgentController(
        api,
        proposalId: 'proposal',
        repository: FakeAgent()..pending = () => pending.future,
        timeout: Duration.zero,
      );
      await next.refresh();
      expect(next.state, AgentReadState.failed);
      pending.complete(proposal(owner: 'b'));
      next.dispose();
      await f.done();
    });
  });
  test(
    'same revision cannot replace superseded status with active proposal',
    () async {
      final f = a.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeAgent()
          ..value = proposal(revision: 2, status: AgentActionState.superseded);
        final ctrl = AgentController(
          api,
          proposalId: 'proposal',
          repository: repo,
        );
        await ctrl.refresh();
        repo.value = proposal(revision: 2);
        await ctrl.refresh();
        expect(ctrl.state, AgentReadState.failed);
        expect(ctrl.proposal, isNull);
        expect(ctrl.canExecute, false);
        ctrl.dispose();
        await f.done();
      });
    },
  );
  for (final theme in ['light', 'dark', 'large light', 'large dark']) {
    testWidgets(
      'prepared card $theme is capability-aware, English, not an execution button',
      (t) async {
        final f = a.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeAgent()
            ..value = proposal(
              consent: AgentConsentState.serverConfirmed,
              kind: AgentActionKind.medicalTreatmentChange,
            );
          final ctrl = AgentController(
            api,
            proposalId: 'proposal',
            repository: repo,
          );
          await ctrl.refresh();
          await h.mount(
            t,
            f,
            Scaffold(
              body: SingleChildScrollView(
                child: AgentProposalCard(controller: ctrl),
              ),
            ),
            dark: theme.contains('dark'),
            reduced: true,
            scale: theme.contains('large') ? 2 : 1,
            width: theme.contains('large') ? 320 : 390,
          );
          await t.pumpAndSettle();
          expect(
            find.text('AI suggestion is not a clinician instruction.'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Clinician/backend review is required'),
            findsOneWidget,
          );
          expect(
            t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          expect(
            find.text('Provider: not provided · Version: not provided'),
            findsOneWidget,
          );
          await t.ensureVisible(find.text('Review parameters on this device'));
          await t.pumpAndSettle();
          await t.tap(find.text('Review parameters on this device'));
          await t.pumpAndSettle();
          expect(ctrl.locallyReviewed, true);
          expect(ctrl.canExecute, false);
          expect(repo.writes, 0);
          expect(t.takeException(), isNull);
          ctrl.dispose();
          await f.done(t);
        });
      },
    );
  }
}
