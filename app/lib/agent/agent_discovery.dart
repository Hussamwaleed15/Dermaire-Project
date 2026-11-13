import 'package:flutter/material.dart';
import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../dermaire_widgets.dart';
import '../doctor_portal.dart';
import '../access_control.dart';

class AgentPatientController extends PrivateController {
  AgentPatientController(this.patient, this.grant);
  final String patient, grant;
  bool verified = false;
  @override
  bool get current => super.current && role == 'doctor';
  @override
  void wipe() {
    verified = false;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final value = object(
        await api.doctorResource('patients/${resourceId(patient)}', generation),
      );
      final access = DoctorGrant.fromApi(
        object(value['access']),
        patient: patient,
        doctor: owner,
      );
      if (value['patient_id'] != patient ||
          access.id != grant ||
          !access.active(DateTime.now().toUtc())) {
        throw const FormatException('Original patient authority unavailable');
      }
      if (valid(ticket)) verified = true;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }
}

class AgentPatientScreen extends StatefulWidget {
  const AgentPatientScreen({
    super.key,
    required this.patient,
    required this.grant,
  });
  final String patient, grant;
  @override
  State<AgentPatientScreen> createState() => _AgentPatientState();
}

class _AgentPatientState extends State<AgentPatientScreen> {
  bool opening = false;
  Future<void> openRecord() async {
    if (opening || !controller.current || !controller.verified) return;
    setState(() => opening = true);
    final workspace = DoctorWorkspaceController(
      AccessSession(userId: controller.owner, role: UserRole.doctor),
    );
    try {
      await workspace.refresh();
      if (!mounted || !controller.current) return;
      final rows = workspace.patients
          .where((p) => p.id == widget.patient)
          .toList();
      if (rows.length != 1 ||
          !rows.single.grants.any(
            (g) => g.id == widget.grant && g.active(DateTime.now().toUtc()),
          )) {
        throw const FormatException('Original patient access changed');
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PatientDetailScreen(
            controller: workspace,
            patient: rows.single,
            expectedGrant: widget.grant,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          controller.wipe();
          controller.error = 'Original patient access unavailable.';
        });
      }
    } finally {
      workspace.dispose();
      if (mounted) setState(() => opening = false);
    }
  }

  late final controller = AgentPatientController(widget.patient, widget.grant);
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      title: 'Authorized patient context',
      children: [
        TextButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Verify original access'),
        ),
        if (c.busy) const Text('Verifying current authorization…'),
        if (c.error != null) Text(c.error!),
        if (c.verified)
          Text(
            'Patient ${c.patient} · original access verified. Open the clinician workspace for clinical care.',
          ),
        if (c.verified)
          TextButton(
            onPressed: opening ? null : openRecord,
            child: const Text('Open clinician record'),
          ),
      ],
    ),
  );
}

class SessionSummary {
  SessionSummary(Map<String, dynamic> v)
    : id = resourceId(v['id']),
      revision = count(v['revision']),
      expires = timestamp(v['expires_at']) {
    if (revision < 1 ||
        v['model_status'] != 'unavailable' ||
        v['medical_execution_enabled'] != false ||
        v['max_tool_calls'] != 8 ||
        v['scopes'] is! List ||
        !(v['scopes'] as List).contains('longitudinal_read') ||
        (v['scopes'] as List).toSet().length != (v['scopes'] as List).length ||
        (v['scopes'] as List).any(
          (s) => !['longitudinal_read', 'proposal_actions'].contains(s),
        ) ||
        count(v['tool_calls']) > 8) {
      throw const FormatException('Unverified session summary');
    }
    timestamp(v['context_at']);
  }
  final String id;
  final int revision;
  final DateTime expires;
}

class AgentDiscovery extends PrivateController {
  final rows = <SessionSummary>[];
  final _cursors = <String>{};
  String? next;
  @override
  bool get current => super.current && role == 'patient';
  @override
  void wipe() {
    rows.clear();
    _cursors.clear();
    next = null;
  }

  @override
  Future<void> refresh() => load();
  Future<void> load({bool more = false}) async {
    if (!current || busy || more && (next == null || rows.length >= 500)) {
      return;
    }
    final cursor = more ? next : null;
    final ticket = begin();
    if (!more) wipe();
    try {
      final data = object(
        (await api.integrationResource(
          'agent/sessions',
          generation,
          query: {'limit': '20', 'before': ?cursor},
        )).data,
      );
      if (data['limit'] != 20 ||
          data['context_included'] != false ||
          data['turns_included'] != false ||
          (data['items'] as List).length > 20) {
        throw const FormatException('Unsupported session page');
      }
      final page = (data['items'] as List)
          .map((v) => SessionSummary(object(v)))
          .toList();
      final after = data['next_before'] == null
          ? null
          : resourceId(data['next_before']);
      final ids = rows.map((r) => r.id).toSet();
      final combined = [...rows, ...page];
      for (var i = 1; i < combined.length; i++) {
        final previous = combined[i - 1], current = combined[i];
        if (current.expires.isAfter(previous.expires) ||
            current.expires == previous.expires &&
                current.id.compareTo(previous.id) >= 0) {
          throw const FormatException('Unordered session page');
        }
      }
      if (page.any((r) => !ids.add(r.id)) ||
          after != null && (after == cursor || _cursors.contains(after))) {
        throw const FormatException('Session page changed; refresh');
      }
      if (!valid(ticket)) return;
      if (after != null) _cursors.add(after);
      rows.addAll(page.where((r) => r.expires.isAfter(DateTime.now().toUtc())));
      next = after;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }
}

class AgentDiscoveryScreen extends StatefulWidget {
  const AgentDiscoveryScreen({super.key, required this.onSelect});
  final Future<void> Function(String) onSelect;
  @override
  State<AgentDiscoveryScreen> createState() => _DiscoveryState();
}

class _DiscoveryState extends State<AgentDiscoveryScreen> {
  final controller = AgentDiscovery();
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      title: 'Your Agent sessions',
      children: [
        const Text(
          'Model inference unavailable. Only authorized session metadata is listed.',
        ),
        TextButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh sessions'),
        ),
        if (c.busy) const Text('Loading sessions…'),
        if (c.error != null) Text(c.error!),
        if (!c.busy && c.rows.isEmpty)
          const Text('No active sessions returned.'),
        for (final row in c.rows)
          TextButton(
            onPressed: c.busy
                ? null
                : () async {
                    if (!c.current ||
                        !row.expires.isAfter(DateTime.now().toUtc())) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await widget.onSelect(row.id);
                  },
            child: Text('Session ${row.id} · revision ${row.revision}'),
          ),
        if (c.next != null)
          TextButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('Earlier sessions'),
          ),
      ],
    ),
  );
}
