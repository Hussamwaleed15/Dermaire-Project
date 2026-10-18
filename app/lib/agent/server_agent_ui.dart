import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../integration/private_view.dart';
import 'server_agent_controller.dart';
import 'server_agent_models.dart';
import 'agent_workspace_summary.dart';

class ServerAgentScreen extends StatefulWidget {
  const ServerAgentScreen({super.key});
  @override
  State<ServerAgentScreen> createState() => _ServerAgentState();
}

class _ServerAgentState extends State<ServerAgentScreen> {
  final controller = ServerAgentController();
  BrokerActionStage? actionFilter;
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    unavailableBuilder: (context, c) => DermairePage(
      eyebrow: 'Consent withdrawal',
      title: 'Agent access unavailable',
      children: [
        const Text(
          'Verify current safety policy before reading context or requests. You may revoke the selected session and erase its memory.',
        ),
        if (c.error != null) Text(c.error!),
        if (c.outcome != null) Text(c.outcome!),
        OutlinedButton(
          onPressed: c.busy || c.selected == null ? null : () => c.revoke(),
          child: const Text('Revoke selected session and memory'),
        ),
      ],
    ),
    builder: (context, c) {
      final s = c.session;
      return DermairePage(
        eyebrow: 'Your consented workspace',
        title: 'Agent sessions & requests',
        subtitle:
            'Model inference is unavailable. These are explicit server-backed workflows, not autonomous medical care.',
        children: [
          AgentWorkspaceSummary(
            session: s,
            actions: c.actions,
            selected: c.selected,
            busy: c.busy,
            failed: c.error != null,
          ),
          OutlinedButton(
            onPressed: c.busy ? null : c.refresh,
            child: const Text('Refresh server state'),
          ),
          if (c.busy) const Text('Verifying Agent state…'),
          if (c.error != null)
            Semantics(liveRegion: true, child: Text(c.error!)),
          if (c.outcome != null)
            Semantics(liveRegion: true, child: Text(c.outcome!)),
          if (c.pending != null)
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'An original operation is unresolved. Unknown does not mean failed. No replacement is submitted automatically.',
                  ),
                  if (c.pending!.path != 'agent/sessions' &&
                      !c.pending!.path.endsWith('/turns'))
                    OutlinedButton(
                      onPressed: c.busy ? null : c.reconcileCurrent,
                      child: const Text('Reconcile current operation state'),
                    ),
                  if (c.pending!.attemptPath.isNotEmpty)
                    OutlinedButton(
                      onPressed: c.busy ? null : c.reconcilePreview,
                      child: const Text('Check original preview attempt'),
                    ),
                  OutlinedButton(
                    onPressed: c.busy ? null : c.retryOriginal,
                    child: const Text('Retry exact original operation'),
                  ),
                ],
              ),
            ),
          if (c.knownSessions.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in c.knownSessions)
                  ChoiceChip(
                    label: Text('Session $id'),
                    selected: id == c.selected,
                    onSelected: c.busy || c.pending != null
                        ? null
                        : (_) => c.select(id),
                  ),
              ],
            ),
          if (s != null) ...[
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Consented session',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('Expires: ${clinicalTime(s.expires)}'),
                  Text(
                    'Server revision: ${s.revision} · tool calls ${s.toolCalls}/8',
                  ),
                  Text('Scopes: ${s.scopes.join(', ')}'),
                  Text('Context read: ${clinicalTime(s.contextAt)}'),
                  Text(
                    s.fresh
                        ? 'Context is within its five-minute freshness window.'
                        : 'Context freshness expired. Refresh before another preview.',
                  ),
                  const Text(
                    'Context uses owner-locked multiple reads, not an atomic clinical snapshot. Server evidence changes can invalidate a preview sooner.',
                  ),
                  OutlinedButton(
                    onPressed: c.busy || c.pending != null || s.toolCalls >= 8
                        ? null
                        : c.refreshContext,
                    child: const Text('Refresh consented context'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy ? null : () => c.revoke(),
                    child: const Text('Revoke selected session and memory'),
                  ),
                ],
              ),
            ),
            const Text(
              'Bounded context evidence',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Safety state from this context read: ${s.safety.level.label}. Use current Safety & clinician guidance for care decisions.',
            ),
            for (final unknown in s.unknowns) Text('Unknown: $unknown'),
            for (final fact in s.facts.take(12))
              DermaireCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${fact.source} · ${fact.field}'),
                    Text('${fact.category} · ${fact.freshness}'),
                    Text(
                      'Recorded: ${fact.recordedAt == null ? 'Unknown' : clinicalTime(fact.recordedAt!)}',
                    ),
                    Text(fact.valueJson),
                  ],
                ),
              ),
            if (s.facts.length > 12)
              Text('Showing 12 of ${s.facts.length} bounded context facts.'),
            const Text(
              'Saved conversation history',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Saved user text is untrusted input. It does not invoke actions. No generated assistant replies are available.',
            ),
            if (c.turns.isEmpty)
              const Text('No saved user messages in this session.'),
            for (final turn in c.turns)
              DermaireCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('You · saved on server'),
                    Text(turn.message),
                    Text(clinicalTime(turn.created)),
                  ],
                ),
              ),
            _SavedTurnForm(
              key: ValueKey('turn:${s.id}:${c.turns.length}'),
              controller: c,
            ),
            if (s.scopes.contains('proposal_actions')) ...[
              OutlinedButton(
                onPressed: c.busy || c.pending != null ? null : c.loadChoices,
                child: const Text('Read authorized action choices'),
              ),
              _ActionPreviewForm(
                key: ValueKey('preview:${s.id}:${s.revision}'),
                controller: c,
              ),
              const Text(
                'Proposals, requests & actual outcomes',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All requests'),
                    selected: actionFilter == null,
                    onSelected: (_) => setState(() => actionFilter = null),
                  ),
                  for (final stage in BrokerActionStage.values)
                    if (c.actions.any((a) => a.stage == stage))
                      ChoiceChip(
                        label: Text(stage.label),
                        selected: actionFilter == stage,
                        onSelected: (_) => setState(() => actionFilter = stage),
                      ),
                ],
              ),
              if (c.actions.isEmpty)
                const Text('No proposals or requests saved in this session.'),
              if (actionFilter != null &&
                  !c.actions.any((a) => a.stage == actionFilter))
                const Text('No current requests match this filter.'),
              for (final action in c.actions.where(
                (a) => actionFilter == null || a.stage == actionFilter,
              ))
                _BrokerActionCard(
                  key: ValueKey('${s.id}:${action.id}:${action.revision}'),
                  controller: c,
                  action: action,
                ),
            ],
          ],
          if (c.capabilities != null && c.pending == null)
            _AgentConsentForm(controller: c),
          if (s == null && c.selected != null)
            OutlinedButton(
              onPressed: c.busy ? null : () => c.revoke(),
              child: const Text('Revoke selected session and memory'),
            ),
          const Text(
            'Agent requests never replace urgent clinical guidance. A confirmed check-in request does not create a check-in; a clinician accepting a request does not change treatment. Device delivery remains unconfirmed.',
          ),
        ],
      );
    },
  );
}

class _AgentConsentForm extends StatefulWidget {
  const _AgentConsentForm({required this.controller});
  final ServerAgentController controller;
  @override
  State<_AgentConsentForm> createState() => _AgentConsentFormState();
}

class _AgentConsentFormState extends State<_AgentConsentForm> {
  bool read = false, actions = false;
  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Start a new consented session',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Sessions expire within one hour and remain bound to this login. At most five can be active. This device remembers session references only for the current login; it does not save clinical context on disk.',
        ),
        CheckboxListTile(
          key: const Key('agentReadConsent'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I consent to read my bounded longitudinal evidence for this session.',
          ),
          value: read,
          onChanged: widget.controller.busy
              ? null
              : (v) => setState(() => read = v!),
        ),
        CheckboxListTile(
          key: const Key('agentProposalConsent'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I also consent to preview proposals and explicitly confirm supported actions.',
          ),
          value: actions,
          onChanged: widget.controller.busy
              ? null
              : (v) => setState(() => actions = v!),
        ),
        FilledButton(
          onPressed: widget.controller.busy || !read
              ? null
              : () async {
                  final agreedRead = read, agreedActions = actions;
                  setState(() {
                    read = false;
                    actions = false;
                  });
                  await widget.controller.start(
                    readConsent: agreedRead,
                    actionConsent: agreedActions,
                  );
                },
          child: const Text('Create consented session'),
        ),
      ],
    ),
  );
}

class _SavedTurnForm extends StatefulWidget {
  const _SavedTurnForm({super.key, required this.controller});
  final ServerAgentController controller;
  @override
  State<_SavedTurnForm> createState() => _SavedTurnFormState();
}

class _SavedTurnFormState extends State<_SavedTurnForm> {
  final message = TextEditingController();
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: message,
        enabled: !widget.controller.busy && widget.controller.pending == null,
        maxLength: 1000,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Save a user note · no AI response',
        ),
      ),
      FilledButton(
        onPressed: widget.controller.busy || widget.controller.pending != null
            ? null
            : () => widget.controller.turn(message.text),
        child: const Text('Save user note'),
      ),
    ],
  );
}

class _ActionPreviewForm extends StatefulWidget {
  const _ActionPreviewForm({super.key, required this.controller});
  final ServerAgentController controller;
  @override
  State<_ActionPreviewForm> createState() => _ActionPreviewFormState();
}

class _ActionPreviewFormState extends State<_ActionPreviewForm> {
  final rationale = TextEditingController();
  String kind = 'request_checkin';
  String? routine, notice;
  @override
  void dispose() {
    rationale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        disabled = c.busy || c.pending != null || c.session?.fresh != true;
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Prepare an explicit proposal',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in brokerKinds)
                ChoiceChip(
                  label: Text(k.replaceAll('_', ' ')),
                  selected: kind == k,
                  onSelected: disabled ? null : (_) => setState(() => kind = k),
                ),
            ],
          ),
          if (kind == 'propose_routine_adjustment') ...[
            const Text(
              'Choose a current active routine and its server revision.',
            ),
            for (final r in c.routines)
              ChoiceChip(
                label: Text('${r['product_name']} · revision ${r['revision']}'),
                selected: routine == r['id'],
                onSelected: disabled
                    ? null
                    : (_) => setState(() => routine = r['id'] as String),
              ),
            if (c.routines.isEmpty)
              const Text(
                'Read authorized action choices to load current routines.',
              ),
          ],
          if (kind == 'mark_notification_read') ...[
            const Text(
              'Choose an actual currently unread notification. Confirmation performs only this nonclinical app action.',
            ),
            for (final n in c.notices)
              ChoiceChip(
                label: Text('${n.kind} · ${n.id}'),
                selected: notice == n.id,
                onSelected: disabled
                    ? null
                    : (_) => setState(() => notice = n.id),
              ),
            if (c.notices.isEmpty)
              const Text('No unread notification choices loaded.'),
          ],
          TextField(
            controller: rationale,
            enabled: !disabled,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Your rationale · 3–500 characters',
            ),
          ),
          FilledButton(
            onPressed: disabled
                ? null
                : () => c.preview(
                    kind,
                    rationale.text,
                    routine: routine,
                    notice: notice,
                  ),
            child: const Text('Read action preview'),
          ),
        ],
      ),
    );
  }
}

class _BrokerActionCard extends StatefulWidget {
  const _BrokerActionCard({
    super.key,
    required this.controller,
    required this.action,
  });
  final ServerAgentController controller;
  final BrokerAction action;
  @override
  State<_BrokerActionCard> createState() => _BrokerActionCardState();
}

class _BrokerActionCardState extends State<_BrokerActionCard> {
  bool confirm = false, routeConsent = false;
  String? grant;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        a = widget.action,
        disabled = c.busy || c.pending != null;
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            a.kind.replaceAll('_', ' '),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(a.stageLabel, style: Theme.of(context).textTheme.titleSmall),
          Text(a.outcome),
          Text('Action revision: ${a.revision}'),
          if (a.payload['rationale'] is String)
            Text('User rationale: ${a.payload['rationale']}'),
          if (a.state == 'preview') ...[
            Text('Preview expires: ${clinicalTime(a.validUntil)}'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                a.kind == 'mark_notification_read'
                    ? 'I confirm marking this specific notification read.'
                    : 'I confirm this request. It does not execute a medical change.',
              ),
              value: confirm,
              onChanged: disabled || !a.fresh
                  ? null
                  : (v) => setState(() => confirm = v!),
            ),
            FilledButton(
              onPressed: disabled || !a.fresh || !confirm
                  ? null
                  : () => c.confirm(a),
              child: const Text('Confirm this preview'),
            ),
          ],
          if (a.result != null) ...[
            Text('Server status: ${a.result!['status']}'),
            Text(
              'Notification enqueued: ${a.result!['notification_enqueued']}. Clinician delivery: unconfirmed.',
            ),
            if (a.result!['doctor_id'] != null)
              Text(
                'Original clinician: ${a.result!['doctor_id']} · grant ${a.result!['access_id']}',
              ),
          ],
          if (a.state == 'confirmed' &&
              a.revision == 2 &&
              [
                'propose_followup',
                'propose_routine_adjustment',
              ].contains(a.kind)) ...[
            const Text(
              'Choose the current doctor grant to submit this request. Routing is separate from confirmation.',
            ),
            for (final g in c.grants)
              ChoiceChip(
                label: Text('Doctor ${g.doctor} · grant ${g.id}'),
                selected: grant == g.id,
                onSelected: disabled
                    ? null
                    : (_) => setState(() => grant = g.id),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I consent to send this request to the selected clinician.',
              ),
              value: routeConsent,
              onChanged: disabled
                  ? null
                  : (v) => setState(() => routeConsent = v!),
            ),
            FilledButton(
              onPressed:
                  disabled ||
                      !routeConsent ||
                      !c.grants.any((g) => g.id == grant)
                  ? null
                  : () =>
                        c.submit(a, c.grants.firstWhere((g) => g.id == grant)),
              child: const Text('Submit clinician request'),
            ),
          ],
          if (a.state != 'revoked')
            OutlinedButton(
              onPressed: disabled ? null : () => c.revoke(action: a.id),
              child: const Text('Withdraw and erase this request'),
            ),
        ],
      ),
    );
  }
}

class ClinicianRequestsScreen extends StatefulWidget {
  const ClinicianRequestsScreen({super.key});
  @override
  State<ClinicianRequestsScreen> createState() => _ClinicianRequestsState();
}

class _ClinicianRequestsState extends State<ClinicianRequestsScreen> {
  final controller = ClinicianRequestsController();
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Consented request inbox',
      title: 'Patient Agent requests',
      subtitle:
          'Newest 100 authorized requests at most. Original patient session and grant expiry still apply.',
      children: [
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh requests'),
        ),
        if (c.busy) const Text('Reading currently authorized requests…'),
        if (c.error != null) Text(c.error!),
        if (c.outcome != null) Text(c.outcome!),
        if (c.pending != null)
          OutlinedButton(
            onPressed: c.busy ? null : c.retryOriginal,
            child: const Text('Retry original clinician decision'),
          ),
        if (!c.busy && c.error == null && c.requests.isEmpty)
          const Text('No currently authorized clinician requests.'),
        for (final request in c.requests)
          _ClinicianDecisionCard(
            key: ValueKey('${request.id}:${request.revision}'),
            controller: c,
            request: request,
          ),
        const Text(
          'Accepting or reviewing a request does not execute treatment, create a follow-up plan or certify safety. Use the actual clinical plan workflow for clinician-authored care.',
        ),
      ],
    ),
  );
}

class _ClinicianDecisionCard extends StatefulWidget {
  const _ClinicianDecisionCard({
    super.key,
    required this.controller,
    required this.request,
  });
  final ClinicianRequestsController controller;
  final BrokerAction request;
  @override
  State<_ClinicianDecisionCard> createState() => _ClinicianDecisionCardState();
}

class _ClinicianDecisionCardState extends State<_ClinicianDecisionCard> {
  bool confirmed = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.request,
        c = widget.controller,
        disabled = c.busy || c.pending != null;
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            a.kind.replaceAll('_', ' '),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(a.stageLabel, style: Theme.of(context).textTheme.titleSmall),
          Text(a.outcome),
          Text('Request ${a.id} · revision ${a.revision}'),
          Text('Original grant: ${a.result?['access_id']}'),
          Text('Expires: ${a.result?['expires_at']}'),
          Text('User rationale: ${a.payload['rationale']}'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I reviewed this request. My decision does not execute a medical change.',
            ),
            value: confirmed,
            onChanged: disabled ? null : (v) => setState(() => confirmed = v!),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final decision
                  in a.result?['status'] == 'pending_clinician_review'
                      ? ['accepted', 'rejected']
                      : a.result?['status'] == 'accepted'
                      ? ['reviewed']
                      : <String>[])
                OutlinedButton(
                  onPressed: disabled || !confirmed
                      ? null
                      : () => c.decide(a, decision),
                  child: Text('Record $decision'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
