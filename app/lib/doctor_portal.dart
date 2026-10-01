import 'package:flutter/material.dart';

import 'access_control.dart';
import 'dermaire_theme.dart';
import 'dermaire_widgets.dart';
import 'services/api_service.dart';

enum PatientPriority { routine, review, urgent }

class DoctorPatient {
  const DoctorPatient({
    required this.id,
    required this.name,
    required this.lastCheckIn,
    required this.experiment,
    required this.priority,
    required this.activeProducts,
    this.followUp,
    this.fileClosed = false,
  });
  final String id;
  final String name;
  final String lastCheckIn;
  final String experiment;
  final PatientPriority priority;
  final int activeProducts;
  final String? followUp;
  final bool fileClosed;
}

class ClinicalAuditEvent {
  const ClinicalAuditEvent(this.action, this.timestamp);
  final String action;
  final DateTime timestamp;
}

class DoctorWorkspaceController extends ChangeNotifier {
  DoctorWorkspaceController(
    this.session, {
    List<Map<String, dynamic>> patientData = const [],
  }) {
    for (final data in patientData) {
      final patient = DoctorPatient(
        id: data['patient_id'] as String,
        name: data['full_name'] as String,
        lastCheckIn: data['last_check_in'] as String,
        experiment: data['active_experiment'] as String,
        priority: PatientPriority.values.firstWhere(
          (value) => value.name == data['priority'],
        ),
        activeProducts: data['active_products_count'] as int,
      );
      patients.add(patient);
      for (final note in (data['notes'] as List<dynamic>)) {
        notes.putIfAbsent(patient.id, () => []).add(note['content'] as String);
      }
    }
  }
  final AccessSession session;
  bool loading = false;
  bool _disposed = false;
  String query = '';
  PatientPriority? filter;
  final notes = <String, List<String>>{};
  final audit = <String, List<ClinicalAuditEvent>>{};
  final patients = <DoctorPatient>[];

  List<DoctorPatient> get visible => patients.where((patient) {
    if (!AccessControl.allows(
      session,
      Permission.viewAuthorizedPatient,
      patientId: patient.id,
    )) {
      return false;
    }
    if (filter != null && patient.priority != filter) return false;
    return patient.name.toLowerCase().contains(query.trim().toLowerCase());
  }).toList();

  void search(String value) {
    query = value;
    notifyListeners();
  }

  void setFilter(PatientPriority? value) {
    filter = value;
    notifyListeners();
  }

  String? validateNote(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'Enter a clinical note';
    if (cleaned.length < 10) return 'Add enough context for the care record';
    if (cleaned.length > 1500) return 'Keep the note under 1500 characters';
    return null;
  }

  Future<bool> addNote(DoctorPatient patient, String value) async {
    if (loading ||
        patient.fileClosed ||
        validateNote(value) != null ||
        !AccessControl.allows(
          session,
          Permission.addClinicalNote,
          patientId: patient.id,
        )) {
      return false;
    }
    loading = true;
    notifyListeners();
    try {
      final saved = await ApiService.instance.addClinicalNote(
        patientId: patient.id,
        content: value.trim(),
      );
      if (_disposed) return false;
      final timestamp = DateTime.parse(saved['created_at'] as String);
      notes.putIfAbsent(patient.id, () => []).add(saved['content'] as String);
      audit
          .putIfAbsent(patient.id, () => [])
          .add(
            ClinicalAuditEvent('Clinical note confirmed by server', timestamp),
          );
      return true;
    } catch (_) {
      return false;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class DoctorSignInScreen extends StatefulWidget {
  const DoctorSignInScreen({super.key});

  @override
  State<DoctorSignInScreen> createState() => _DoctorSignInScreenState();
}

class _DoctorSignInScreenState extends State<DoctorSignInScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate() || loading) return;
    setState(() => loading = true);

    try {
      final res = await ApiService.instance.login(
        email: email.text.trim(),
        password: password.text,
        requiredRole: 'doctor',
      );
      List<Map<String, dynamic>> patientsData;
      try {
        patientsData = await ApiService.instance.getDoctorPatients();
        // Validate real server records before opening the workspace.
        DoctorWorkspaceController(
          AccessSession(
            userId: res['user_id'] as String,
            role: UserRole.doctor,
          ),
          patientData: patientsData,
        ).dispose();
      } catch (_) {
        await ApiService.instance.logout();
        rethrow;
      }
      final session = AccessSession(
        userId: res['user_id'] as String,
        role: UserRole.values.byName(res['role'] as String),
        authorizedPatientIds: patientsData
            .map((p) => p['patient_id'] as String)
            .toSet(),
        expiresAt: DateTime.now().add(
          Duration(seconds: res['expires_in'] as int),
        ),
      );
      if (!mounted) return;
      await openPage(
        context,
        DoctorPortalScreen(session: session, patientData: patientsData),
      );
    } catch (_) {
      if (mounted) {
        showDermaireSnack(
          context,
          'Doctor sign-in failed. Use a provisioned doctor account and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Clinician workspace',
    title: 'Doctor sign in',
    subtitle: 'Sign in with your verified, provisioned clinician account.',
    children: [
      const Notice(
        icon: '🔒',
        text:
            'Clinician accounts are provisioned by trusted staff after identity verification.',
        color: DermaireColors.unknownBackground,
      ),
      Form(
        key: formKey,
        child: Column(
          children: [
            TextFormField(
              key: const Key('doctorEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Professional email',
              ),
              validator: (value) => (value ?? '').contains('@')
                  ? null
                  : 'Enter a valid professional email',
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('doctorPassword'),
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) =>
                  (value ?? '').isNotEmpty ? null : 'Enter your password',
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (loading) const LinearProgressIndicator(),
      FilledButton(
        key: const Key('doctorSignIn'),
        onPressed: loading ? null : submit,
        child: Text(loading ? 'Please wait...' : 'Sign in'),
      ),
    ],
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

class _DoctorPortalScreenState extends State<DoctorPortalScreen> {
  late final DoctorWorkspaceController controller = DoctorWorkspaceController(
    widget.session,
    patientData: widget.patientData,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.role != UserRole.doctor || widget.session.isExpired) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('You are not authorized to view this workspace.'),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => DermairePage(
        showBack: false,
        eyebrow: 'Doctor dashboard',
        title: 'Patient reviews',
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await ApiService.instance.logout();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
        children: [
          const Notice(
            icon: 'ⓘ',
            text:
                'Only patients with active, consented server access are listed.',
          ),
          SearchBar(
            hintText: 'Search authorized patients',
            leading: const Icon(Icons.search_rounded),
            onChanged: controller.search,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', null),
                _filterChip('Routine', PatientPriority.routine),
                _filterChip('Needs review', PatientPriority.review),
                _filterChip('Urgent', PatientPriority.urgent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (controller.visible.isEmpty)
            const DermaireCard(
              child: Text('No authorized patients match these filters.'),
            )
          else
            ...controller.visible.map(
              (patient) => _PatientCard(
                patient: patient,
                onTap: () => openPage(
                  context,
                  PatientDetailScreen(controller: controller, patient: patient),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, PatientPriority? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: controller.filter == value,
      onSelected: (_) => controller.setFilter(value),
    ),
  );
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient, required this.onTap});
  final DoctorPatient patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DermaireCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                patient.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            StatusPill(
              patient.priority.name.toUpperCase(),
              kind: patient.priority == PatientPriority.urgent
                  ? StatusKind.conflict
                  : patient.priority == PatientPriority.review
                  ? StatusKind.warning
                  : StatusKind.safe,
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(patient.experiment),
        Text('Last check-in: ${patient.lastCheckIn}'),
        Text(
          '${patient.activeProducts} active products${patient.followUp == null ? '' : ' · Follow-up ${patient.followUp}'}',
        ),
      ],
    ),
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

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final note = TextEditingController();
  String? noteError;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => DermairePage(
      eyebrow: 'Authorized patient',
      title: widget.patient.name,
      subtitle:
          '${widget.patient.experiment} · Last activity ${widget.patient.lastCheckIn}',
      children: [
        _clinicalSection('Experiment', widget.patient.experiment),
        _clinicalSection(
          'Products',
          '${widget.patient.activeProducts} active products',
        ),
        _clinicalSection('Last check-in', widget.patient.lastCheckIn),
        _clinicalSection(
          'Clinical notes',
          (widget.controller.notes[widget.patient.id] ?? []).join('\n'),
        ),
        TextField(
          key: const Key('clinicalNote'),
          controller: note,
          maxLength: 1500,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Clinical note',
            errorText: noteError,
            helperText:
                'Notes are append-only and recorded in the audit history.',
          ),
        ),
        FilledButton(
          key: const Key('addClinicalNote'),
          onPressed: widget.controller.loading
              ? null
              : () async {
                  final error = widget.controller.validateNote(note.text);
                  setState(() => noteError = error);
                  if (error != null) return;
                  final saved = await widget.controller.addNote(
                    widget.patient,
                    note.text,
                  );
                  if (!context.mounted) return;
                  if (saved) {
                    note.clear();
                    showDermaireSnack(context, 'Clinical note saved.');
                  } else {
                    showDermaireSnack(
                      context,
                      'Clinical note was not saved. Please retry.',
                    );
                  }
                },
          child: const Text('Add clinical note'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showDermaireSnack(
            context,
            'Messaging requires a connected, consented care provider.',
          ),
          icon: const Icon(Icons.message_outlined),
          label: const Text('Message patient'),
        ),
        const SizedBox(height: 18),
        Text(
          'Confirmed activity',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...(widget.controller.audit[widget.patient.id] ??
                const <ClinicalAuditEvent>[])
            .map(
              (event) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: Text(event.action),
                subtitle: Text(event.timestamp.toIso8601String()),
              ),
            ),
      ],
    ),
  );

  Widget _clinicalSection(String title, String value) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}
