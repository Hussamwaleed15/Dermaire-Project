import '../doctor/doctor_records_controller.dart';
import '../capture/guided_camera_screen.dart';
import '../capture/guided_capture_models.dart';
import 'plan_images.dart';
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
  late PlansController controller = PlansController(patient: widget.patient);
  @override
  void didUpdateWidget(covariant ClinicalPlansScreen old) {
    super.didUpdateWidget(old);
    if (old.patient != widget.patient) {
      controller = PlansController(patient: widget.patient);
    }
  }

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
  GuidedCaptureRecord? candidate;
  int? capturePlanRevision;
  @override
  void initState() {
    super.initState();
    controller.addListener(guardCandidate);
  }

  void guardCandidate() {
    if (!controller.authenticatedCurrent || !controller.visible) {
      candidate = null;
      capturePlanRevision = null;
    }
  }

  @override
  void dispose() {
    controller.removeListener(guardCandidate);
    super.dispose();
  }

  Future<void> takeFollowup(ClinicalPlan plan) async {
    final state = widget.state;
    if (state == null ||
        !controller.current ||
        controller.busy ||
        controller.pending != null ||
        plan.state != 'scheduled') {
      return;
    }
    final generation = controller.generation;
    final record = await openEntry<GuidedCaptureRecord>(
      context,
      GuidedCameraScreen(state: state, returnCapture: true),
    );
    if (!mounted ||
        !controller.authenticatedCurrent ||
        generation != controller.generation ||
        record == null ||
        record.owner != controller.owner ||
        record.state != 'accepted' ||
        !record.stored ||
        record.id == plan.baseline ||
        plan.acknowledged == null ||
        record.receivedAt.isBefore(plan.acknowledged!)) {
      return;
    }
    setState(() {
      candidate = record;
      capturePlanRevision = plan.revision;
    });
  }

  @override
  void didUpdateWidget(covariant ClinicalPlanScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      controller.removeListener(guardCandidate);
      controller = PlanController(widget.id);
      controller.addListener(guardCandidate);
      candidate = null;
      capturePlanRevision = null;
    }
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
              Text(
                'Plan-linked source: ${plan.source['source_type']} · ${plan.source['source_id']}',
              ),
              if (c.role == 'patient' &&
                  plan.state == 'scheduled' &&
                  widget.state != null)
                FilledButton(
                  onPressed: c.busy || c.pending != null
                      ? null
                      : () => takeFollowup(plan),
                  child: const Text('Take guided follow-up capture'),
                ),
              if (candidate != null && c.role == 'patient') ...[
                Text(
                  'Confirmed capture awaiting explicit association: ${candidate!.id}',
                ),
                if (capturePlanRevision != plan.revision)
                  const Text(
                    'The plan changed during capture. Review the current schedule and take a new follow-up for this revision.',
                  ),
                FilledButton(
                  onPressed:
                      c.busy ||
                          c.pending != null ||
                          plan.state != 'scheduled' ||
                          capturePlanRevision != plan.revision
                      ? null
                      : () async {
                          final saved = await c.mutate('capture', {
                            'capture_id': candidate!.id,
                          }, plan.revision);
                          if (saved && mounted) {
                            setState(() => candidate = null);
                          }
                        },
                  child: const Text(
                    'Associate confirmed capture with this plan',
                  ),
                ),
              ],
              PlanImagePanel(
                key: ValueKey('images:${plan.id}:${plan.revision}'),
                controller: c,
                plan: plan,
              ),
              Text('Baseline capture: ${plan.baseline}'),
              Text('Follow-up capture: ${plan.followup ?? 'Not attached'}'),
              _EvaluationActions(
                key: ValueKey('evaluation:${plan.id}:${plan.revision}'),
                controller: c,
                plan: plan,
              ),
              if (c.evaluation != null) ...[
                Text(
                  'Evaluation state: ${c.evaluation!.currentState.replaceAll('_', ' ')}',
                ),
                if (c.evaluation!.state != 'not_requested')
                  Text(
                    'Evaluation event revision: ${c.evaluation!.wire['plan_revision']}',
                  ),
                if (c.evaluation!.wire['human_review'] is Map)
                  Text(
                    'Clinician inference review: ${(c.evaluation!.wire['human_review'] as Map)['assessment']}',
                  ),
                const Text(
                  'A queued job is a processing request. A clinician plan review is separate from a review of inference evidence.',
                ),
              ],
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
                    Text(
                      'Recorded state: ${event.snapshot?.state ?? event.evaluation?.state}',
                    ),
                    if (event.evaluation != null) ...[
                      Text(
                        'Historical evaluation job: ${event.evaluation!.wire['id']}',
                      ),
                      const Text(
                        'This saved job event is not current processing consent or proof of completed inference.',
                      ),
                    ],
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
  const CreateClinicalPlanScreen({
    super.key,
    required this.connection,
    this.comparison = false,
  });
  final DoctorConnectionController connection;
  final bool comparison;
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
      title: widget.comparison
          ? 'Create comparison plan'
          : 'Create follow-up plan',
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
          _NewFollowupForm(controller: c, comparison: widget.comparison),
      ],
    ),
  );
}

class _NewFollowupForm extends StatefulWidget {
  const _NewFollowupForm({required this.controller, required this.comparison});
  final CreatePlanController controller;
  final bool comparison;
  @override
  State<_NewFollowupForm> createState() => _NewFollowupFormState();
}

class _NewFollowupFormState extends State<_NewFollowupForm> {
  late final records = DoctorRecordsController(widget.controller.connection);
  String? baseline, source;
  @override
  void initState() {
    super.initState();
    if (widget.comparison) {
      records.addListener(changed);
      records.refresh();
    }
  }

  void changed() {
    if (mounted) {
      setState(() {
        if (!records.confirmed) {
          baseline = null;
          source = null;
        }
      });
    }
  }

  final purpose = TextEditingController();
  String? error;
  @override
  void dispose() {
    records.removeListener(changed);
    records.dispose();
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
      if (widget.comparison) ...[
        const Text(
          'Choose a real intervention and an accepted private baseline from the currently authorized patient timeline. No arbitrary photo pairing.',
        ),
        OutlinedButton(
          onPressed: records.loading ? null : records.refresh,
          child: const Text('Refresh authorized evidence'),
        ),
        if (records.loading) const Text('Reading authorized evidence…'),
        if (records.error != null) Text(records.error!),
        if (records.hasMore)
          OutlinedButton(
            onPressed: records.loadingMore ? null : records.loadMore,
            child: const Text('Load more evidence'),
          ),
        const Text('Intervention or observation'),
        for (final item in records.items.where(
          (i) =>
              i.field == 'record' &&
              ['routine', 'experiment', 'checkin'].contains(i.source),
        ))
          ChoiceChip(
            label: Text('${item.source} · ${item.sourceId}'),
            selected: source == item.id,
            onSelected: widget.controller.busy
                ? null
                : (_) => setState(() => source = item.id),
          ),
        const Text('Private baseline'),
        for (final item in records.items.where((i) => i.storedCapture))
          ChoiceChip(
            label: Text('Capture ${item.sourceId}'),
            selected: baseline == item.sourceId,
            onSelected: widget.controller.busy
                ? null
                : (_) => setState(() => baseline = item.sourceId),
          ),
        if (!records.loading &&
            records.items.where((i) => i.storedCapture).isEmpty)
          const Text(
            'No accepted stored baseline in the loaded authorized evidence.',
          ),
      ],
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
          final selected = records.items
              .where((i) => i.id == source)
              .firstOrNull;
          if (widget.comparison &&
              (!records.confirmed ||
                  selected == null ||
                  !records.canReadCapture(baseline ?? ''))) {
            setState(
              () => error =
                  'Choose an authorized source and accepted stored baseline.',
            );
            return false;
          }
          return widget.controller.create({
            'kind': widget.comparison ? 'comparison' : 'follow_up',
            if (widget.comparison) ...{
              'source_type': selected!.source == 'checkin'
                  ? 'observation'
                  : selected.source,
              'source_id': selected.sourceId,
              'baseline_capture_id': baseline,
            },
            'purpose': purpose.text.trim(),
            'local_due': local,
            'timezone': zone,
            'fold': fold,
          });
        },
        label: widget.comparison
            ? 'Propose this comparison plan'
            : 'Create proposed follow-up',
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

class _EvaluationActions extends StatefulWidget {
  const _EvaluationActions({
    super.key,
    required this.controller,
    required this.plan,
  });
  final PlanController controller;
  final ClinicalPlan plan;
  @override
  State<_EvaluationActions> createState() => _EvaluationActionsState();
}

class _EvaluationActionsState extends State<_EvaluationActions> {
  bool processingConsent = false, reviewConsent = false;
  final assessment = TextEditingController();
  @override
  void dispose() {
    assessment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = widget.plan, job = c.evaluation;
    final disabled = c.busy || c.pending != null;
    final inference = job?.wire['inference'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.role == 'patient' &&
            p.state == 'captured' &&
            job != null &&
            [
              'not_requested',
              'unavailable',
              'cancelled',
            ].contains(job.currentState)) ...[
          const Text(
            'A validated clinical comparison model is unavailable. You can explicitly request the supported processing workflow; a queued request does not mean analysis has run.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I consent to process these two plan-linked private images for this evaluation request.',
            ),
            value: processingConsent,
            onChanged: disabled
                ? null
                : (v) => setState(() => processingConsent = v!),
          ),
          FilledButton(
            onPressed: disabled || !processingConsent
                ? null
                : () => c.mutate('evaluation', {
                    'image_processing_consent': true,
                  }, p.revision),
            child: const Text('Request plan evaluation'),
          ),
        ],
        if (job != null &&
            ![
              'not_requested',
              'cancelled',
              'reviewed',
              'rejected',
            ].contains(job.currentState))
          OutlinedButton(
            onPressed: disabled ? null : c.cancelEvaluation,
            child: const Text('Cancel evaluation request'),
          ),
        if (inference is Map && inference['result'] is Map) ...[
          Text('Model version: ${inference['model_version']}'),
          Text('Artifact SHA-256: ${inference['artifact_sha256']}'),
          const Text(
            'Nonclinical image-quality evidence only. Accuracy is not clinically validated.',
          ),
          for (final flag
              in (inference['result'] as Map)['quality_flags'] as List)
            Text('Image-quality flag: $flag'),
        ],
        if (c.role == 'doctor' &&
            job?.currentState == 'pending_human_review') ...[
          TextField(
            controller: assessment,
            enabled: !disabled,
            maxLength: 1500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText:
                  'Assessment of this inference evidence · 10–1500 characters',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I have reviewed the exact job and artifact above. This does not certify model accuracy or clinical clearance.',
            ),
            value: reviewConsent,
            onChanged: disabled
                ? null
                : (v) => setState(() => reviewConsent = v!),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final decision in ['reviewed', 'rejected'])
                OutlinedButton(
                  onPressed: disabled || !reviewConsent
                      ? null
                      : () {
                          if (assessment.text.trim().length >= 10) {
                            c.mutate('evaluation/review', {
                              'job_id': job!.wire['id'],
                              'decision': decision,
                              'assessment': assessment.text.trim(),
                            }, p.revision);
                          }
                        },
                  child: Text(
                    decision == 'reviewed'
                        ? 'Record inference review'
                        : 'Reject inference evidence',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
