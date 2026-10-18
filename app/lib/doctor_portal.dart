import 'agent/server_agent_ui.dart';
import 'notifications/inbox_ui.dart';
import 'plans/plan_ui.dart';
import 'messaging/messaging_ui.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'access_control.dart';
import 'dermaire_state.dart';
import 'dermaire_widgets.dart';
import 'entry/entry_motion.dart';
import 'onboarding_screens.dart';
import 'services/api_service.dart';
import 'doctor/doctor_models.dart';
import 'doctor/doctor_controller.dart';
import 'doctor/doctor_connection.dart';
import 'doctor/doctor_evidence_ui.dart';
import 'doctor/doctor_clinical_ui.dart';
import 'doctor/doctor_view_lifecycle.dart';
import 'clinical/clinical_models.dart' show object;
export 'doctor/doctor_models.dart';
export 'doctor/doctor_controller.dart';

class DoctorSignInScreen extends StatefulWidget {
  const DoctorSignInScreen({super.key, this.state});
  final DermaireState? state;
  @override
  State<DoctorSignInScreen> createState() => _DoctorSignInScreenState();
}

class _DoctorSignInScreenState extends State<DoctorSignInScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  bool loading = false;
  String? error;
  Future<void> submit() async {
    if (loading || !form.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
    });
    final api = ApiService.instance;
    try {
      final login = api.login(
        email: email.text.trim(),
        password: password.text,
        requiredRole: 'doctor',
      );
      final generation = api.sessionGeneration;
      await login;
      if (!mounted || !api.isCurrentSession(generation)) return;
      password.clear();
      await openEntry(context, _DoctorEntryHost(state: widget.state));
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Doctor sign-in could not be confirmed. Use a provisioned doctor account and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Clinician workspace',
    title: 'Doctor sign in',
    subtitle:
        'Use your provisioned doctor account. Clinical license verification is not shown by this app.',
    children: [
      const Text(
        'Accounts are provisioned by trusted staff. Patient registration does not create a doctor role.',
      ),
      Form(
        key: form,
        child: Column(
          children: [
            TextFormField(
              key: const Key('doctorEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Professional email',
              ),
              validator: (v) => (v ?? '').contains('@')
                  ? null
                  : 'Enter a valid professional email',
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('doctorPassword'),
              controller: password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) =>
                  (v ?? '').isNotEmpty ? null : 'Enter your password',
            ),
          ],
        ),
      ),
      if (error != null) Text(error!),
      if (loading)
        if (EntryMotion.reduced(context))
          const Text('Signing in…')
        else
          const LinearProgressIndicator(semanticsLabel: 'Signing in'),
      const SizedBox(height: 14),
      FilledButton(
        key: const Key('doctorSignIn'),
        onPressed: loading ? null : submit,
        child: Text(loading ? 'Please wait…' : 'Sign in'),
      ),
    ],
  );
}

class _DoctorEntryHost extends StatefulWidget {
  const _DoctorEntryHost({this.state});
  final DermaireState? state;
  @override
  State<_DoctorEntryHost> createState() => _DoctorEntryHostState();
}

class _DoctorEntryHostState extends State<_DoctorEntryHost> {
  late final state = widget.state ?? DermaireState();
  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PatientEntryGate(
    state: state,
    onExit: () {
      if (mounted) Navigator.of(context).pop();
    },
  );
}

class DoctorPortalScreen extends StatefulWidget {
  const DoctorPortalScreen({
    super.key,
    required this.session,
    this.patientData = const [],
  });
  final AccessSession session;
  final List<Map<String, dynamic>> patientData;
  @override
  State<DoctorPortalScreen> createState() => _DoctorPortalScreenState();
}

class _DoctorPortalScreenState extends State<DoctorPortalScreen>
    with DoctorViewLifecycle<DoctorPortalScreen> {
  @override
  void pauseDoctorView({required bool background}) {
    if (background) controller.clear();
  }

  @override
  Future<void> resumeDoctorView() async {
    await controller.refresh();
  }

  late final controller = DoctorWorkspaceController(widget.session);
  @override
  void initState() {
    super.initState();
    unawaited(controller.refresh());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!doctorViewVisible) return pausedDoctorView();
      if (!controller.current && controller.authenticatedCurrent) {
        return DermairePage(
          eyebrow: 'Doctor workspace',
          title: 'Verify your doctor account',
          children: [
            OutlinedButton(
              onPressed: () => openEntry(context, const CareThreadsScreen()),
              child: const Text('Care conversations'),
            ),
            OutlinedButton(
              onPressed: () => openEntry(context, const ClinicalPlansScreen()),
              child: const Text('Clinical plans'),
            ),
            if (controller.loading)
              const Text(
                'Verifying doctor role and safety acceptance…',
                key: Key('doctorVerifyingProfile'),
              ),
            if (controller.error != null) Text(controller.error!),
            OutlinedButton(
              onPressed: controller.loading ? null : controller.refresh,
              child: const Text('Retry account verification'),
            ),
            TextButton(
              onPressed: () => ApiService.instance.logout(),
              child: const Text('Sign out'),
            ),
          ],
        );
      }
      if (!controller.current) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text('You are not authorized to view this workspace.'),
          ),
        );
      }
      return DermairePage(
        eyebrow: 'Doctor workspace',
        title: 'Connected patients',
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ApiService.instance.logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => openEntry(context, const CareThreadsScreen()),
                child: const Text('Care conversations'),
              ),
              OutlinedButton(
                onPressed: () =>
                    openEntry(context, const ClinicalPlansScreen()),
                child: const Text('Clinical plans'),
              ),
              OutlinedButton(
                onPressed: () =>
                    openEntry(context, const NotificationInboxScreen()),
                child: const Text('Notification inbox'),
              ),
              OutlinedButton(
                onPressed: () =>
                    openEntry(context, const ClinicianRequestsScreen()),
                child: const Text('Patient Agent requests'),
              ),
            ],
          ),
          const Text(
            'Only current server-authorized connections are shown. Account role does not certify a medical license. Export is unavailable. Care messages require separate patient consent.',
          ),
          const SizedBox(height: 12),
          SearchBar(
            hintText: 'Search connected patients',
            leading: const Icon(Icons.search),
            onChanged: controller.search,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final priority in [null, ...PatientPriority.values])
                ChoiceChip(
                  label: Text(priority == null ? 'All' : priority.name),
                  selected: controller.filter == priority,
                  onSelected: (_) => controller.setFilter(priority),
                ),
            ],
          ),
          OutlinedButton(
            onPressed: controller.loading || controller.saving
                ? null
                : controller.refresh,
            child: const Text('Refresh connections'),
          ),
          if (controller.loading)
            if (EntryMotion.reduced(context))
              const Text('Verifying connections…')
            else
              const LinearProgressIndicator(
                semanticsLabel: 'Verifying doctor connections',
              ),
          if (controller.error != null) Text(controller.error!),
          if (!controller.loading &&
              controller.error == null &&
              controller.visible.isEmpty)
            const Text('No current connections match these filters.'),
          for (final patient in controller.visible)
            DermaireCard(
              onTap: () => openEntry(
                context,
                PatientDetailScreen(controller: controller, patient: patient),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Server priority: ${patient.priority.name}'),
                  Text(patient.experiment),
                  Text('Last check-in: ${patient.lastCheckIn}'),
                  Text('${patient.activeProducts} active products'),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({
    super.key,
    required this.controller,
    required this.patient,
  });
  final DoctorWorkspaceController controller;
  final DoctorPatient patient;
  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with DoctorViewLifecycle<PatientDetailScreen> {
  @override
  void pauseDoctorView({required bool background}) {
    if (background) connection.invalidate();
  }

  @override
  Future<void> resumeDoctorView() async {
    await connection.resumeAccess(active: () => mounted && doctorViewVisible);
  }

  late DoctorConnectionController connection;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    connection = DoctorConnectionController(
      widget.controller,
      widget.patient.id,
    );
    connection.refresh();
  }

  @override
  void didUpdateWidget(covariant PatientDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patient.id != widget.patient.id ||
        oldWidget.controller != widget.controller) {
      connection.dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, connection]),
    builder: (context, _) {
      final c = widget.controller;
      if (!doctorViewVisible) return pausedDoctorView();
      if (!c.allows(widget.patient.id)) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text(
              'Patient access is unavailable. Return and refresh connections.',
            ),
          ),
        );
      }
      if (!connection.confirmed) {
        return DermairePage(
          eyebrow: 'Clinician access',
          title: 'Verify current patient access',
          children: [
            if (connection.loading) const Text('Checking current access…'),
            if (connection.error != null) Text(connection.error!),
            OutlinedButton(
              onPressed: connection.loading ? null : connection.refresh,
              child: const Text('Retry patient access'),
            ),
          ],
        );
      }
      return DermairePage(
        eyebrow: 'Connected patient',
        title: connection.record!['full_name'] as String,
        children: [
          Text('Grant status: ${connection.grant!.status}'),
          Text(
            'Grant expiry: ${connection.grant!.expiresAt.toUtc().toIso8601String()} (UTC)',
          ),
          const Text(
            'Detailed viewing and export scopes are unavailable. Export is not enabled.',
          ),
          OutlinedButton(
            onPressed: c.saving ? null : connection.refresh,
            child: const Text('Verify current access'),
          ),
          DoctorReviewSnapshot(
            data: object(connection.record!['review']),
            patient: widget.patient.id,
          ),
          OutlinedButton(
            onPressed: () => openEntry(
              context,
              DoctorEvidenceScreen(connection: connection),
            ),
            child: const Text('Review clinical evidence'),
          ),
          OutlinedButton(
            onPressed: () => openEntry(
              context,
              CreateClinicalPlanScreen(connection: connection),
            ),
            child: const Text('Create clinician follow-up'),
          ),
          OutlinedButton(
            onPressed: () => openEntry(
              context,
              CreateClinicalPlanScreen(
                connection: connection,
                comparison: true,
              ),
            ),
            child: const Text('Create plan-linked comparison'),
          ),
          OutlinedButton(
            onPressed: () => openEntry(
              context,
              ClinicalPlansScreen(patient: widget.patient.id),
            ),
            child: const Text('Patient clinical plans'),
          ),
          Text(
            'Connection list retrieved: ${c.retrievedAt?.toUtc().toIso8601String() ?? "Unknown"} (snapshot)',
          ),
          Text(
            'Priority in that list snapshot: ${widget.patient.priority.name}',
          ),
          Text(widget.patient.experiment),
          Text('Last check-in: ${widget.patient.lastCheckIn}'),
          const Text(
            'This is a connection summary, not a complete medical record.',
          ),
          OutlinedButton(
            onPressed: () => openEntry(
              context,
              DoctorClinicalScreen(connection: connection),
            ),
            child: const Text('Notes and clinical reviews'),
          ),
          const Text(
            'Open Care conversations for consented messages. This workspace is not an emergency messaging service.',
          ),
        ],
      );
    },
  );
}
