import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../dermaire_state.dart';
import '../entry/entry_motion.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../integration/private_view.dart';
import '../doctor/doctor_connection.dart';
import 'plan_models.dart';
import 'plan_controller.dart';

class ClinicalPlansScreen extends StatefulWidget {
  const ClinicalPlansScreen({super.key, this.state, this.patient});
  final DermaireState? state;
  final String? patient;
  @override
  State<ClinicalPlansScreen> createState() => _ClinicalPlansState();
}

class _ClinicalPlansState extends State<ClinicalPlansScreen> {
  late final controller = PlansController(patient: widget.patient);
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Clinician-authored care',
      title: 'Follow-ups & comparison plans',
      subtitle:
          'Only real server plans appear here. Free-text advice is not an appointment.',
      children: [
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh plans'),
        ),
        if (c.busy) const Text('Reading authorized plans…'),
        if (c.error != null) Text(c.error!),
        if (!c.busy && c.error == null && c.plans.isEmpty)
          const Text('No authorized clinical plans returned.'),
        for (final plan in c.plans)
          DermaireCard(
            onTap: () => openEntry(
              context,
              ClinicalPlanScreen(id: plan.id, state: widget.state),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.kind == 'follow_up'
                      ? 'Clinician follow-up'
                      : 'Plan-linked comparison',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(plan.purpose),
                Text(
                  'Status: ${plan.state.replaceAll('_', ' ')} · revision ${plan.revision}',
                ),
                Text('Due: ${clinicalTime(plan.due)}'),
                Text(
                  'Recorded local time: ${plan.localWallTime} · ${plan.timezone}',
                ),
              ],
            ),
          ),
        if (c.next != null)
          OutlinedButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('Load more plans'),
          ),
        if (c.role == 'doctor')
          const Text(
            'Open an authorized patient to create a new plan. Existing plans remain bound to their original grant.',
          ),
        const Text(
          'Scheduled care does not replace urgent Safety Engine guidance. Notification delivery is not confirmed.',
        ),
      ],
    ),
  );
}

class ClinicalPlanScreen extends StatefulWidget {
  const ClinicalPlanScreen({super.key, required this.id, this.state});
  final String id;
  final DermaireState? state;
  @override
  State<ClinicalPlanScreen> createState() => _ClinicalPlanState();
}

class _ClinicalPlanState extends State<ClinicalPlanScreen> {
  late PlanController controller = PlanController(widget.id);
  @override
  void didUpdateWidget(covariant ClinicalPlanScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) controller = PlanController(widget.id);
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) {
      final plan = c.value;
      return DermairePage(
        eyebrow: 'Current clinical plan',
        title: 'Plan details',
        children: [
          OutlinedButton(
            onPressed: c.busy ? null : c.refresh,
            child: const Text('Refresh current plan'),
          ),
          if (c.busy) const Text('Confirming plan state…'),
          if (c.error != null)
            Semantics(liveRegion: true, child: Text(c.error!)),
          if (c.outcome != null)
            Semantics(liveRegion: true, child: Text(c.outcome!)),
          if (plan != null) ...[
            Text(plan.purpose, style: Theme.of(context).textTheme.titleLarge),
            StatusPill(
              plan.state.replaceAll('_', ' '),
              kind: StatusKind.neutral,
            ),
            Text('Patient: ${plan.patient} · Clinician author: ${plan.doctor}'),
            Text('Current revision: ${plan.revision}'),
            Text('Fixed due instant: ${clinicalTime(plan.due)}'),
            Text(
              'Recorded wall time: ${plan.localWallTime} · ${plan.timezone}',
            ),
            Text(
              'Device local display: ${plan.due.toLocal()} (${plan.due.toLocal().timeZoneName})',
            ),
            Text(
              'Clock occurrence: ${plan.schedule['fold'] == 0 ? 'first' : 'second'}. Travel does not change the saved UTC appointment.',
            ),
            const Text(
              'The server resolves the recorded IANA zone. Nonexistent local times are rejected; repeated clock times require an explicit occurrence.',
            ),
            if (plan.acknowledged != null)
              Text(
                'Patient acknowledgment: ${clinicalTime(plan.acknowledged!)}',
              ),
            const Text(
              'A plan is not medical clearance. Follow current safety guidance; this is not an emergency service.',
            ),
            if (plan.kind == 'comparison') ...[
              Text('Baseline capture: ${plan.baseline}'),
              Text('Follow-up capture: ${plan.followup ?? 'Not attached'}'),
              const Text(
                'Comparison inference is unavailable unless a real current result is separately returned. No improvement percentage or diagnosis is inferred.',
              ),
            ],
            _PlanActions(
              key: ValueKey('${plan.id}:${plan.revision}'),
              controller: c,
              plan: plan,
            ),
            Text(
              'Recorded plan history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Current detail and immutable history are separate reads. Historical snapshots never replace current state.',
            ),
            for (final event in c.history)
              DermaireCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revision ${event.revision} · ${event.operation.replaceAll('_', ' ')}',
                    ),
                    Text(
                      'Author account: ${event.actor} · ${clinicalTime(event.recorded)}',
                    ),
                    Text('Recorded state: ${event.snapshot.state}'),
                    if (event.details['assessment'] is String)
                      Text(
                        'Clinician-authored assessment: ${event.details['assessment']}',
                      ),
                    if (event.details['reason'] is String)
                      Text('Recorded reason: ${event.details['reason']}'),
                    if (event.details['early_capture'] == true)
                      const Text(
                        'Capture was early; this does not prove adequate treatment exposure or clinical validity.',
                      ),
                  ],
                ),
              ),
            if (c.nextHistory != null)
              OutlinedButton(
                onPressed: c.busy ? null : c.moreHistory,
                child: const Text('Load next history page'),
              ),
          ],
          if (c.pending != null) ...[
            const Text(
              'A change is unresolved. Keep its original body, key and revision.',
            ),
            OutlinedButton(
              onPressed: c.busy ? null : () => c.reconcile(),
              child: const Text('Check original plan attempt'),
            ),
            OutlinedButton(
              onPressed: c.busy ? null : () => c.reconcile(retryOriginal: true),
              child: const Text(
                'Reconcile, then retry original change if unknown',
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _PlanActions extends StatefulWidget {
  const _PlanActions({super.key, required this.controller, required this.plan});
  final PlanController controller;
  final ClinicalPlan plan;
  @override
  State<_PlanActions> createState() => _PlanActionsState();
}

class _PlanActionsState extends State<_PlanActions> {
  final reason = TextEditingController(), assessment = TextEditingController();
  bool accepted = false;
  @override
  void dispose() {
    reason.dispose();
    assessment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = widget.plan;
    final disabled = c.busy || c.pending != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.role == 'patient' && p.state == 'proposed') ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: accepted,
            onChanged: disabled
                ? null
                : (v) => setState(() => accepted = v == true),
            title: const Text(
              'I accept this clinician-authored plan and its recorded due time',
            ),
            subtitle: const Text(
              'Separate from messaging, notification and image-processing consent',
            ),
          ),
          FilledButton(
            key: const Key('acceptClinicalPlan'),
            onPressed: disabled || !accepted
                ? null
                : () => c.mutate('acknowledge', {'consent': true}, p.revision),
            child: const Text('Accept plan'),
          ),
          OutlinedButton(
            onPressed: disabled
                ? null
                : () => c.mutate('cancel', {
                    'reason': 'Patient declined this proposed plan',
                  }, p.revision),
            child: const Text('Decline plan (records cancellation)'),
          ),
        ],
        if (c.role == 'doctor' && p.canReschedule)
          _ScheduleEditor(
            key: ValueKey('schedule:${p.revision}'),
            initialLocal: p.localWallTime,
            initialZone: p.timezone,
            busy: disabled,
            onSubmit: (local, zone, fold) => c.mutate('reschedule', {
              'local_due': local,
              'timezone': zone,
              'fold': fold,
            }, p.revision),
            label: 'Reschedule; patient must accept again',
          ),
        if (p.canCancel) ...[
          TextField(
            key: const Key('planCancelReason'),
            controller: reason,
            enabled: !disabled,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Reason for cancellation (at least 3 characters)',
            ),
          ),
          OutlinedButton(
            onPressed: disabled
                ? null
                : () {
                    if (reason.text.trim().length >= 3) {
                      c.mutate('cancel', {
                        'reason': reason.text.trim(),
                      }, p.revision);
                    }
                  },
            child: const Text('Cancel current plan'),
          ),
        ],
        if (c.role == 'doctor' &&
            (p.kind == 'follow_up' && p.state == 'scheduled' ||
                p.kind == 'comparison' && p.state == 'captured')) ...[
          TextField(
            controller: assessment,
            enabled: !disabled,
            maxLength: 1500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Clinician assessment (10–1500 characters)',
            ),
          ),
          FilledButton(
            onPressed: disabled
                ? null
                : () {
                    if (assessment.text.trim().length >= 10) {
                      c.mutate('review', {
                        'assessment': assessment.text.trim(),
                      }, p.revision);
                    }
                  },
            child: const Text('Record clinician plan review'),
          ),
        ],
      ],
    );
  }
}

class CreateClinicalPlanScreen extends StatefulWidget {
  const CreateClinicalPlanScreen({super.key, required this.connection});
  final DoctorConnectionController connection;
  @override
  State<CreateClinicalPlanScreen> createState() => _CreateClinicalPlanState();
}

class _CreateClinicalPlanState extends State<CreateClinicalPlanScreen> {
  late final controller = CreatePlanController(widget.connection);
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Clinician-authored scheduling',
      title: 'Create follow-up plan',
      children: [
        Text(
          'Selected patient: ${widget.connection.patientId}. Current original grant is rechecked before creating a plan.',
        ),
        const Text(
          'Choose a future due time case by case. Free-text guidance and routine end dates never create an appointment automatically.',
        ),
        if (c.busy) const Text('Confirming plan creation…'),
        if (c.error != null) Text(c.error!),
        if (c.created != null) ...[
          Text(
            'Current server plan: ${c.created!.state} · revision ${c.created!.revision}',
          ),
          FilledButton(
            onPressed: () =>
                openEntry(context, ClinicalPlanScreen(id: c.created!.id)),
            child: const Text('Open confirmed plan'),
          ),
        ] else if (c.pending != null) ...[
          const Text(
            'Creation is unresolved. Check the original attempt before creating any replacement.',
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(),
            child: const Text('Check original creation'),
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(retryOriginal: true),
            child: const Text(
              'Reconcile and retry original creation if unknown',
            ),
          ),
        ] else
          _NewFollowupForm(controller: c),
      ],
    ),
  );
}

class _NewFollowupForm extends StatefulWidget {
  const _NewFollowupForm({required this.controller});
  final CreatePlanController controller;
  @override
  State<_NewFollowupForm> createState() => _NewFollowupFormState();
}

class _NewFollowupFormState extends State<_NewFollowupForm> {
  final purpose = TextEditingController();
  String? error;
  @override
  void dispose() {
    purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        key: const Key('followupPurpose'),
        controller: purpose,
        enabled: !widget.controller.busy,
        maxLength: 1000,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Purpose of follow-up',
          helperText: '10–1000 characters',
          errorText: error,
        ),
      ),
      _ScheduleEditor(
        busy: widget.controller.busy,
        onSubmit: (local, zone, fold) async {
          if (purpose.text.trim().length < 10) {
            setState(
              () => error =
                  'Describe at least 10 characters of clinical context.',
            );
            return false;
          }
          return widget.controller.create({
            'kind': 'follow_up',
            'purpose': purpose.text.trim(),
            'local_due': local,
            'timezone': zone,
            'fold': fold,
          });
        },
        label: 'Create proposed follow-up',
      ),
    ],
  );
}

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({
    super.key,
    this.initialLocal = '',
    this.initialZone = 'Africa/Cairo',
    required this.busy,
    required this.onSubmit,
    required this.label,
  });
  final String initialLocal, initialZone, label;
  final bool busy;
  final Future<bool> Function(String, String, int?) onSubmit;
  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late final local = TextEditingController(
    text: widget.initialLocal
        .replaceAll('T', ' ')
        .substring(
          0,
          widget.initialLocal.length < 16 ? widget.initialLocal.length : 16,
        ),
  );
  late final zone = TextEditingController(text: widget.initialZone);
  int? fold;
  String? error;
  @override
  void dispose() {
    local.dispose();
    zone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('planLocalDue'),
        controller: local,
        enabled: !widget.busy,
        decoration: const InputDecoration(
          labelText: 'Due date and time (YYYY-MM-DD HH:mm)',
          helperText: 'Local wall time in the timezone below; no UTC offset',
        ),
      ),
      TextField(
        key: const Key('planTimezone'),
        controller: zone,
        enabled: !widget.busy,
        decoration: const InputDecoration(
          labelText: 'Timezone',
          helperText: 'IANA name, such as Africa/Cairo, Europe/London or UTC',
        ),
      ),
      const Text(
        'During a repeated clock hour, choose the first or second occurrence. For normal times leave automatic; nonexistent times are rejected by the server.',
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final entry in const <int?, String>{
            null: 'Automatic',
            0: 'First occurrence',
            1: 'Second occurrence',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: fold == entry.key,
              onSelected: widget.busy
                  ? null
                  : (_) => setState(() => fold = entry.key),
            ),
        ],
      ),
      if (error != null) Text(error!),
      FilledButton(
        key: const Key('submitPlanSchedule'),
        onPressed: widget.busy
            ? null
            : () async {
                final wall = local.text.trim().replaceAll(' ', 'T');
                setState(
                  () => error = validateWallSchedule(
                    wall,
                    zone.text.trim(),
                    fold,
                  ),
                );
                if (error != null) return;
                await widget.onSubmit(wall, zone.text.trim(), fold);
              },
        child: Text(widget.label),
      ),
    ],
  );
}
