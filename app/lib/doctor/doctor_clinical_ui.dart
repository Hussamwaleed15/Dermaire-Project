import '../messaging/messaging_ui.dart';
import 'doctor_context_page.dart';
import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../entry/entry_motion.dart';
import 'doctor_connection.dart';
import 'doctor_clinical_controller.dart';
import 'doctor_evidence_ui.dart';
import 'doctor_view_lifecycle.dart';

class DoctorClinicalScreen extends StatefulWidget {
  const DoctorClinicalScreen({super.key, required this.connection});
  final DoctorConnectionController connection;
  @override
  State<DoctorClinicalScreen> createState() => _DoctorClinicalScreenState();
}

class _DoctorClinicalScreenState extends State<DoctorClinicalScreen>
    with DoctorViewLifecycle<DoctorClinicalScreen> {
  @override
  void pauseDoctorView({required bool background}) {
    clearDrafts();
    clinical.clear();
    if (background) widget.connection.invalidate();
  }

  @override
  Future<void> resumeDoctorView() async {
    if (await widget.connection.resumeAccess(
          active: () => mounted && doctorViewVisible,
        ) &&
        mounted &&
        doctorViewVisible) {
      await clinical.refresh();
    }
  }

  late DoctorClinicalController clinical;
  final note = TextEditingController(),
      follow = TextEditingController(),
      category = TextEditingController(),
      rationale = TextEditingController();
  String priority = 'routine', state = 'in_review', recommendation = 'none';
  bool noteVisible = false, reviewVisible = false, ended = false;
  bool attached = true, clearOnActivate = false;
  String? validation;
  @override
  void initState() {
    super.initState();
    bindClinical();
  }

  void bindClinical() {
    clinical = DoctorClinicalController(widget.connection)
      ..addListener(changed);
    clinical.refresh();
  }

  @override
  void didUpdateWidget(covariant DoctorClinicalScreen old) {
    super.didUpdateWidget(old);
    if (old.connection != widget.connection) {
      clinical.removeListener(changed);
      clinical.dispose();
      clearDrafts();
      bindClinical();
    }
  }

  void clearDrafts() {
    note.clear();
    follow.clear();
    category.clear();
    rationale.clear();
    noteVisible = reviewVisible = false;
    validation = null;
  }

  void changed() {
    if (ended) return;
    if (!attached) {
      clearOnActivate = true;
      return;
    }
    if (!clinical.connection.confirmed) clearDrafts();
    if (mounted) setState(() {});
  }

  @override
  void deactivate() {
    attached = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    attached = true;
    if (clearOnActivate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !attached || ended) return;
        clearDrafts();
        setState(() => clearOnActivate = false);
      });
    }
  }

  bool get current =>
      mounted &&
      doctorViewVisible &&
      !ended &&
      widget.connection.confirmed &&
      ModalRoute.of(context)?.isCurrent == true;
  Future<void> save(bool review) async {
    if (!current || !clinical.confirmed) return;
    final sequence = clinical.review!.sequence;
    setState(
      () => validation = review
          ? clinical.validateReview(
              state,
              recommendation == 'none' ? null : recommendation,
              rationale.text.trim().isEmpty ? null : rationale.text,
            )
          : clinical.validateNote(
              note.text,
              priority,
              follow.text.trim().isEmpty ? null : follow.text,
              category.text.trim().isEmpty ? null : category.text,
            ),
    );
    if (validation != null) return;
    final saved = review
        ? await clinical.recordReview(
            state: state,
            expectedSequence: sequence,
            recommendation: recommendation == 'none' ? null : recommendation,
            rationale: rationale.text.trim().isEmpty ? null : rationale.text,
            visible: reviewVisible,
          )
        : await clinical.addNote(
            content: note.text,
            priority: priority,
            visible: noteVisible,
            followUp: follow.text.trim().isEmpty ? null : follow.text,
            category: category.text.trim().isEmpty ? null : category.text,
          );
    if (!current || !saved) return;
    setState(() {
      if (review) {
        rationale.clear();
        reviewVisible = false;
      } else {
        note.clear();
        follow.clear();
        category.clear();
        noteVisible = false;
      }
    });
  }

  Widget choice(
    String label,
    String value,
    List<String> options,
    void Function(String) change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options
            .map(
              (v) => ChoiceChip(
                label: Text(v.replaceAll('_', ' ')),
                selected: value == v,
                onSelected: clinical.saving
                    ? null
                    : (_) => setState(() => change(v)),
              ),
            )
            .toList(),
      ),
    ],
  );
  @override
  void dispose() {
    ended = true;
    clinical.removeListener(changed);
    clinical.dispose();
    note.dispose();
    follow.dispose();
    category.dispose();
    rationale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!doctorViewVisible || clearOnActivate) return pausedDoctorView();
    if (!widget.connection.confirmed) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('Patient access ended. Return and verify access.'),
        ),
      );
    }
    final busy = clinical.loading || clinical.saving;
    return DermairePage(
      eyebrow: 'Clinician-authored records',
      title: 'Notes & reviews',
      children: [
        Text(
          'Selected patient: ${widget.connection.record!["full_name"]} · ${widget.connection.patientId}',
        ),
        const Text(
          'Saved records are append-only. A review does not replace Safety Engine guidance or verify a medical license.',
        ),
        OutlinedButton(
          onPressed: busy ? null : clinical.refresh,
          child: const Text('Refresh notes and reviews'),
        ),
        if (busy)
          if (EntryMotion.reduced(context))
            const Text('Confirming clinical records…')
          else
            const LinearProgressIndicator(
              semanticsLabel: 'Confirming clinical records',
            ),
        if (clinical.error != null)
          Semantics(liveRegion: true, child: Text(clinical.error!)),
        if (clinical.outcome != null)
          Semantics(liveRegion: true, child: Text(clinical.outcome!)),
        if (validation != null)
          Semantics(liveRegion: true, child: Text(validation!)),
        if (clinical.confirmed) ...[
          DoctorReviewSnapshot(
            data: clinical.review!.wire,
            patient: widget.connection.patientId,
          ),
          Text(
            'Recorded clinical notes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (clinical.notes.isEmpty) const Text('No clinical notes returned.'),
          for (final n in clinical.notes)
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.content),
                  Text(
                    'Clinician author: ${n.doctor} · ${clinicalTime(n.createdAt)}',
                  ),
                  Text('Priority: ${n.priority}'),
                  Text(
                    n.visible
                        ? 'Patient-visible record; delivery/read status unavailable'
                        : 'Not patient-visible',
                  ),
                  if (n.followUp != null)
                    Text('Follow-up guidance: ${n.followUp}'),
                  const Text(
                    'Text guidance is not an appointment or reminder.',
                  ),
                ],
              ),
            ),
        ],
        Text(
          'Append a clinical note',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        TextField(
          key: const Key('clinicalNote'),
          controller: note,
          enabled: !busy,
          maxLength: 1500,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Clinical context',
            helperText: '10–1500 characters; no automatic diagnosis',
          ),
        ),
        choice('Note priority', priority, [
          'routine',
          'review',
          'urgent',
        ], (v) => priority = v),
        TextField(
          controller: category,
          enabled: !busy,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'Category (optional)'),
        ),
        TextField(
          key: const Key('clinicalFollowUp'),
          controller: follow,
          enabled: !busy,
          maxLength: 100,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Follow-up guidance (optional)',
            helperText: 'Text only; no scheduled appointment or reminder',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: noteVisible,
          onChanged: busy
              ? null
              : (v) => setState(() => noteVisible = v == true),
          title: const Text('Make this note patient-visible'),
          subtitle: const Text(
            'Not a message, delivery receipt or export consent',
          ),
        ),
        if (clinical.uncertain('notes'))
          const Text(
            'Previous note outcome is unconfirmed. Refresh; do not resend it.',
          ),
        FilledButton(
          key: const Key('addClinicalNote'),
          onPressed: busy || !clinical.confirmed || clinical.uncertain('notes')
              ? null
              : () => save(false),
          child: const Text('Record clinical note'),
        ),
        Text(
          'Record a new review action',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Re-read current sequence before submitting. Historical reviews are preserved.',
        ),
        choice('Review state', state, [
          'pending',
          'in_review',
          'reviewed',
          'follow_up_needed',
        ], (v) => state = v),
        choice('Recommendation (optional)', recommendation, [
          'none',
          'track',
          'low_risk_self_care',
          'doctor_review',
          'urgent',
        ], (v) => recommendation = v),
        TextField(
          key: const Key('clinicalRationale'),
          controller: rationale,
          enabled: !busy,
          maxLength: 1500,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Clinician rationale',
            helperText: 'Required for a recommendation; 10–1500 characters',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: reviewVisible,
          onChanged: busy
              ? null
              : (v) => setState(() => reviewVisible = v == true),
          title: const Text('Make this review patient-visible'),
          subtitle: const Text(
            'Latest private reviews are never replaced by older visible decisions',
          ),
        ),
        const Text(
          'Follow-up needed is a review state. No appointment, reminder or comparison is automatically scheduled.',
        ),
        if (clinical.uncertain('reviews'))
          const Text(
            'Previous review outcome is unconfirmed. Refresh; do not resend it.',
          ),
        FilledButton(
          key: const Key('recordClinicalReview'),
          onPressed:
              busy || !clinical.confirmed || clinical.uncertain('reviews')
              ? null
              : () => save(true),
          child: const Text('Record review action'),
        ),
        OutlinedButton(
          onPressed: () => openPage(
            context,
            DoctorContextPage(
              connection: widget.connection,
              child: CareThreadsScreen(patient: widget.connection.patientId),
            ),
          ),
          child: const Text('Open this patient’s care conversations'),
        ),
        const Text(
          'Care conversations require separate messaging consent. Export is not enabled. This is not an emergency messaging service.',
        ),
      ],
    );
  }
}
