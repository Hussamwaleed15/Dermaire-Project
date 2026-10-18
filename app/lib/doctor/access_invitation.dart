import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../dermaire_widgets.dart';
import 'doctor_models.dart';

class ScopedGrant {
  ScopedGrant(Map<String, dynamic> v, {required String patient, String? doctor})
    : grant = DoctorGrant.fromApi(v, patient: patient, doctor: doctor),
      scopes = List.unmodifiable((v['scopes'] as List).cast<String>()),
      effective = List.unmodifiable(
        (v['effective_scopes'] as List).cast<String>(),
      ),
      doctorName = v['doctor_name'] as String? {
    if (v['consent_version'] != 2 ||
        v['consent_source'] != 'explicit_patient_intent' ||
        v['view_consent'] != true ||
        v['export_consent'] is! bool ||
        !scopes.contains('VIEW') ||
        scopes.any((s) => !['VIEW', 'EXPORT'].contains(s)) ||
        scopes.toSet().length != scopes.length ||
        v['export_consent'] != scopes.contains('EXPORT') ||
        effective.toSet().length != effective.length ||
        effective.any((s) => !scopes.contains(s))) {
      throw const FormatException('Unverified consent scope');
    }
    if (grant.active(DateTime.now().toUtc())
        ? (!effective.contains('VIEW'))
        : effective.isNotEmpty) {
      throw const FormatException('Inactive scope advertised');
    }
  }
  final DoctorGrant grant;
  final List<String> scopes, effective;
  final String? doctorName;
}

class AccessInvitationController extends PrivateController {
  ScopedGrant? _grant;
  String? _token;
  List<DoctorGrant> _current = [];
  Timer? _expiry;
  String? outcome;
  @override
  bool get current => super.current && role == 'patient';
  ScopedGrant? get grant => current ? _grant : null;
  String? get token =>
      current &&
          _grant?.grant.status == 'pending' &&
          _grant!.grant.expiresAt.isAfter(DateTime.now().toUtc())
      ? _token
      : null;
  List<DoctorGrant> get grants => current ? List.unmodifiable(_current) : [];
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents['doctor:issue'] : null;
  @override
  void wipe() {
    _expiry?.cancel();
    _grant = null;
    _token = null;
    _current = [];
    outcome = null;
  }

  Future<List<DoctorGrant>> readGrants() async {
    final list =
        (await api.integrationResource('doctor/access', generation)).data
            as List;
    final rows = list
        .map((v) => DoctorGrant.fromApi(object(v), patient: owner))
        .toList();
    if (rows.map((g) => g.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate grants');
    }
    return rows;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final rows = await readGrants();
      if (!valid(ticket)) return;
      _current = rows;
      final key = api.integrationReferences['doctor-issued-key'];
      if (key != null) await attempt(key, ticket);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> issue(String doctor, {required bool consent}) async {
    if (!current || busy || pending != null || !consent) return false;
    try {
      resourceId(doctor);
    } catch (_) {
      error = 'Enter the intended doctor account ID.';
      notifyListeners();
      return false;
    }
    final intent = PendingIntent(
      path: 'doctor/generate-qr',
      attemptPath: 'doctor/consent-attempts/issue',
      body: {
        'view_consent': true,
        'export_consent': false,
        'doctor_id': doctor,
      },
    );
    api.integrationIntents['doctor:issue'] = intent;
    return deliver(intent);
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin(), uncertain = intent.uncertain;
    bool acknowledged = false;
    try {
      intent.uncertain = true;
      final data = object(
        (await api.integrationResource(
          intent.path,
          generation,
          method: 'POST',
          query: {'minutes_valid': '60'},
          body: intent.body,
          key: intent.key,
        )).data,
      );
      acknowledged = true;
      if (!valid(ticket)) return false;
      await verify(
        data,
        intent.key,
        ticket,
        doctor: intent.body['doctor_id'] as String,
      );
      if (!valid(ticket)) return false;
      api.integrationIntents.remove('doctor:issue');
      return true;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error =
            'Invitation outcome is unconfirmed. Reconcile the original key; do not create a replacement. ${integrationError(e)}';
        if (!uncertain &&
            !acknowledged &&
            e is IntegrationFailure &&
            [403, 404, 422].contains(e.status)) {
          api.integrationIntents.remove('doctor:issue');
        }
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  Future<void> verify(
    Map<String, dynamic> data,
    String key,
    int ticket, {
    String? doctor,
  }) async {
    final raw = object(data['access']),
        receipt = ScopedGrant(raw, patient: owner, doctor: doctor),
        code = text(data['access_token']);
    if (receipt.scopes.length != 1 ||
        receipt.scopes.single != 'VIEW' ||
        receipt.grant.status != 'pending' ||
        data['qr_payload'] != 'dermaire://doctor-access?token=$code' ||
        timestamp(data['expires_at']) != receipt.grant.expiresAt) {
      throw const FormatException('Unverified invitation');
    }
    final currentRows =
        ((await api.integrationResource('doctor/access', generation)).data
                as List)
            .map(object)
            .toList();
    final rows = currentRows
        .map((v) => DoctorGrant.fromApi(v, patient: owner))
        .toList();
    if (!valid(ticket)) return;
    final latest = rows.where((g) => g.id == receipt.grant.id).firstOrNull;
    final scoped = currentRows
        .where((v) => v['id'] == receipt.grant.id)
        .firstOrNull;
    if (scoped == null ||
        ScopedGrant(
              scoped,
              patient: owner,
              doctor: receipt.grant.doctorIdValue,
            ).scopes.length !=
            1) {
      throw const FormatException('Current invitation scope changed');
    }
    if (latest == null ||
        latest.patientId != owner ||
        latest.doctorIdValue != receipt.grant.doctorIdValue ||
        latest.expiresAt != receipt.grant.expiresAt) {
      throw const FormatException('Current grant unconfirmed');
    }
    _current = rows;
    api.integrationReferences['doctor-issued-key'] = key;
    if (latest.status == 'pending' &&
        latest.expiresAt.isAfter(DateTime.now().toUtc())) {
      _grant = receipt;
      _token = code;
      _expiry?.cancel();
      _expiry = Timer(latest.expiresAt.difference(DateTime.now().toUtc()), () {
        if (!current) return;
        _grant = null;
        _token = null;
        outcome = 'The invitation expiry was reached. Refresh current access.';
        notifyListeners();
      });
      outcome =
          'Temporary VIEW invitation confirmed. Pending does not grant access; only the intended doctor can claim it.';
    } else {
      _grant = null;
      _token = null;
      outcome =
          'Original invitation recorded; current grant status: ${latest.status}. Its bearer code is no longer shown.';
    }
  }

  Future<bool> attempt(String key, int ticket) async {
    final data = object(
      (await api.integrationResource(
        'doctor/consent-attempts/issue/$key',
        generation,
      )).data,
    );
    if (!valid(ticket)) return false;
    if (data['schema_version'] != 1) {
      throw const FormatException('Invalid consent attempt');
    }
    if (data['status'] == 'unknown') {
      error =
          'Original invitation is unknown. Only the original key and consent payload may be explicitly retried.';
      return false;
    }
    if (data['actor_id'] != owner ||
        data['owner_id'] != owner ||
        data['operation'] != 'issue' ||
        data['snapshot_basis'] != 'original_committed_not_current') {
      throw const FormatException('Foreign consent receipt');
    }
    if (data['status'] == 'committed' &&
        data['result_availability'] == 'retained') {
      final result = object(data['result']);
      if (object(result['access'])['id'] != data['access_id']) {
        throw const FormatException('Consent attempt mismatch');
      }
      await verify(result, key, ticket);
      if (!valid(ticket)) return false;
      api.integrationIntents.remove('doctor:issue');
      return true;
    }
    if (!['committed', 'expired'].contains(data['status']) ||
        data['result'] != null) {
      throw const FormatException('Invalid original consent state');
    }
    final rows = await readGrants();
    if (!valid(ticket)) return false;
    _current = rows;
    _token = null;
    _grant = null;
    api.integrationIntents.remove('doctor:issue');
    api.integrationReferences.remove('doctor-issued-key');
    outcome =
        'The original invitation result is ${data['result_availability']}. No usable code is restored. Review current access before a new explicit invitation.';
    return true;
  }

  Future<void> reconcile({bool retry = false}) async {
    final intent = pending;
    if (intent == null || !current || busy) return;
    final ticket = begin();
    try {
      final resolved = await attempt(intent.key, ticket);
      if (valid(ticket) && !resolved && retry) {
        busy = false;
        await deliver(intent);
      }
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

class ClaimInvitationController extends PrivateController {
  Timer? _expiry;
  ScopedGrant? _grant;
  String? outcome;
  @override
  bool get current => super.current && role == 'doctor';
  ScopedGrant? get grant => current ? _grant : null;
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents['doctor:claim'] : null;
  @override
  void wipe() {
    _expiry?.cancel();
    _grant = null;
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (current && !busy) {
      _grant = null;
      error = null;
      notifyListeners();
    }
  }

  String? candidate(PendingIntent intent) {
    // JWT content is only an untrusted routing hint for the owned attempt lookup.
    // It never grants access or establishes the patient identity in this UI.
    try {
      final token = intent.body['access_token'] as String;
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final body =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map;
      return resourceId(body['patient_id']);
    } catch (_) {
      return null;
    }
  }

  Future<bool> claim(String input, {required bool confirmed}) async {
    if (!current || busy || pending != null || !confirmed) return false;
    final token = input.trim();
    if (token.isEmpty || token.length > 4096) return false;
    final intent = PendingIntent(
      path: 'doctor/claim',
      attemptPath: '',
      body: {'access_token': token},
    );
    api.integrationIntents['doctor:claim'] = intent;
    return deliver(intent);
  }

  Future<bool> verify(Map<String, dynamic> data, int ticket) async {
    if (data['success'] != true) {
      throw const FormatException('Claim not acknowledged');
    }
    final raw = object(data['access']),
        patient = resourceId(raw['patient_id']),
        receipt = ScopedGrant(raw, patient: patient, doctor: owner);
    if (!receipt.grant.active(DateTime.now().toUtc())) {
      throw const FormatException('Claim is not active');
    }
    final rows =
        (await api.integrationResource('doctor/patients', generation)).data
            as List;
    if (!valid(ticket)) return false;
    final row = rows
        .map(object)
        .where((r) => r['patient_id'] == patient)
        .firstOrNull;
    if (row == null) {
      throw const FormatException('Authorized patient not returned');
    }
    final found = (row['access'] as List)
        .map(object)
        .where((v) => v['id'] == receipt.grant.id)
        .firstOrNull;
    if (found == null) {
      throw const FormatException('Original claimed grant missing');
    }
    final currentGrant = ScopedGrant(found, patient: patient, doctor: owner);
    if (!currentGrant.grant.active(DateTime.now().toUtc()) ||
        currentGrant.grant.expiresAt != receipt.grant.expiresAt ||
        currentGrant.effective
            .toSet()
            .difference(receipt.effective.toSet())
            .isNotEmpty) {
      throw const FormatException('Current claimed scope unavailable');
    }
    final detail = object(
      (await api.integrationResource(
        'doctor/patients/$patient',
        generation,
      )).data,
    );
    if (!valid(ticket)) return false;
    if (detail['patient_id'] != patient) {
      throw const FormatException('Wrong current patient');
    }
    final finalRows =
        (await api.integrationResource('doctor/patients', generation)).data
            as List;
    if (!valid(ticket)) return false;
    final finalPatient = finalRows
        .map(object)
        .where((r) => r['patient_id'] == patient)
        .firstOrNull;
    final original = finalPatient == null
        ? null
        : (finalPatient['access'] as List)
              .map(object)
              .where((g) => g['id'] == receipt.grant.id)
              .firstOrNull;
    if (original == null ||
        !ScopedGrant(
          original,
          patient: patient,
          doctor: owner,
        ).grant.active(DateTime.now().toUtc()))
      throw const FormatException(
        'Original grant changed after patient readback',
      );
    _grant = ScopedGrant(original, patient: patient, doctor: owner);
    _expiry?.cancel();
    _expiry = Timer(
      currentGrant.grant.expiresAt.difference(DateTime.now().toUtc()),
      () {
        if (!current) return;
        _grant = null;
        outcome =
            'Claimed access expiry reached. Refresh current patient access.';
        notifyListeners();
      },
    );
    api.integrationIntents.remove('doctor:claim');
    outcome =
        'Original claimed VIEW access confirmed by current authorized patient readback. Account role does not certify a medical license.';
    return true;
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin(), uncertain = intent.uncertain;
    bool acknowledged = false;
    try {
      intent.uncertain = true;
      final data = object(
        (await api.integrationResource(
          'doctor/claim',
          generation,
          method: 'POST',
          body: intent.body,
          key: intent.key,
        )).data,
      );
      acknowledged = true;
      if (!valid(ticket)) return false;
      return await verify(data, ticket);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error =
            'Claim is unconfirmed. Reconcile original access before any replacement. ${integrationError(e)}';
        if (!uncertain &&
            !acknowledged &&
            e is IntegrationFailure &&
            [400, 403, 404, 422].contains(e.status)) {
          api.integrationIntents.remove('doctor:claim');
        }
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  Future<void> reconcile({bool retry = false}) async {
    final intent = pending;
    if (intent == null || !current || busy) return;
    final ticket = begin();
    try {
      final patient = candidate(intent);
      if (patient != null) {
        final data = object(
          (await api.integrationResource(
            'doctor/patients/$patient/attempts/claim/${intent.key}',
            generation,
          )).data,
        );
        if (!valid(ticket)) return;
        if (data['status'] == 'committed') {
          if (data['schema_version'] != 1 ||
              data['actor_id'] != owner ||
              data['patient_id'] != patient ||
              data['operation'] != 'claim' ||
              data['snapshot_basis'] != 'original_committed_not_current' ||
              object(object(data['result'])['access'])['id'] !=
                  data['access_id']) {
            throw const FormatException('Invalid original claim attempt');
          }
          await verify(object(data['result']), ticket);
          return;
        }
        if (data['status'] == 'expired') {
          error =
              'Original claim receipt expired. Review current patient access; no new claim is assumed.';
          return;
        }
        if (data['status'] != 'unknown') {
          throw const FormatException('Invalid claim attempt');
        }
      }
      if (retry && valid(ticket)) {
        busy = false;
        await deliver(intent);
      } else {
        error =
            'Original claim is unconfirmed. Only the same key and bearer code can be explicitly retried.';
      }
    } catch (e) {
      if (retry &&
          valid(ticket) &&
          e is IntegrationFailure &&
          [403, 404, 409, 503].contains(e.status)) {
        busy = false;
        await deliver(intent);
      } else if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }
}

class AccessInvitationScreen extends StatefulWidget {
  const AccessInvitationScreen({super.key});
  @override
  State<AccessInvitationScreen> createState() => _AccessInvitationState();
}

class _AccessInvitationState extends State<AccessInvitationScreen> {
  final controller = AccessInvitationController();
  final doctor = TextEditingController();
  bool consent = false;
  @override
  void initState() {
    super.initState();
    controller.addListener(clearHiddenEditor);
  }

  void clearHiddenEditor() {
    if (!controller.current) {
      doctor.clear();
      consent = false;
    }
  }

  @override
  void dispose() {
    controller.removeListener(clearHiddenEditor);
    doctor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Explicit patient sharing',
      title: 'Invite your clinician',
      children: [
        const Text(
          'Enter the intended doctor account ID supplied by your clinician. The server verifies the account role. This app has no clinician directory or license verification.',
        ),
        TextField(
          controller: doctor,
          enabled: !c.busy && c.pending == null,
          decoration: const InputDecoration(
            labelText: 'Intended doctor account ID',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I consent to temporary VIEW access for this doctor. This does not grant export permission or messaging consent.',
          ),
          value: consent,
          onChanged: c.busy || c.pending != null
              ? null
              : (v) => setState(() => consent = v!),
        ),
        FilledButton(
          onPressed: c.busy || c.pending != null || !consent
              ? null
              : () => c.issue(doctor.text.trim(), consent: consent),
          child: const Text('Create one-hour invitation'),
        ),
        if (c.busy) const Text('Verifying consent and current access…'),
        if (c.error != null) Text(c.error!),
        if (c.outcome != null) Text(c.outcome!),
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Read current invitation and access'),
        ),
        if (c.pending != null) ...[
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(),
            child: const Text('Read original invitation attempt'),
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(retry: true),
            child: const Text('Reconcile and retry original invitation'),
          ),
        ],
        if (c.token != null) ...[
          const Text(
            'Single-use private bearer code. Give it only to the intended clinician; anyone holding it can attempt to claim it. Logout or expiry invalidates an unclaimed invitation.',
          ),
          SelectableText(c.token!),
          Text(
            'Intended doctor: ${c.grant!.doctorName ?? c.grant!.grant.doctorIdValue}',
          ),
          Text('Expires: ${c.grant!.grant.expiresAt.toUtc()}'),
          const Text(
            'This is a copyable access code, not a rendered QR image.',
          ),
        ],
        for (final grant in c.grants)
          Text('Current grant ${grant.id}: ${grant.status}'),
        const Text(
          'Export remains unavailable. A doctor connection does not replace current safety guidance or emergency care.',
        ),
      ],
    ),
  );
}

class ClaimInvitationScreen extends StatefulWidget {
  const ClaimInvitationScreen({super.key});
  @override
  State<ClaimInvitationScreen> createState() => _ClaimInvitationState();
}

class _ClaimInvitationState extends State<ClaimInvitationScreen> {
  final controller = ClaimInvitationController();
  final token = TextEditingController();
  bool confirmed = false;
  @override
  void initState() {
    super.initState();
    controller.addListener(clearHiddenEditor);
  }

  void clearHiddenEditor() {
    if (!controller.current) {
      token.clear();
      confirmed = false;
    }
  }

  @override
  void dispose() {
    controller.removeListener(clearHiddenEditor);
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Patient-authorized access',
      title: 'Claim patient invitation',
      children: [
        Text('Your doctor account ID: ${c.owner}'),
        const Text(
          'Paste the patient’s single-use private access code. Only actual server-confirmed original access enables clinical reads.',
        ),
        TextField(
          controller: token,
          enabled: !c.busy && c.pending == null,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Private patient invitation code',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I am the intended clinician and will use only the patient-authorized scope.',
          ),
          value: confirmed,
          onChanged: c.busy || c.pending != null
              ? null
              : (v) => setState(() => confirmed = v!),
        ),
        FilledButton(
          onPressed: c.busy || c.pending != null || !confirmed
              ? null
              : () async {
                  final saved = await c.claim(token.text, confirmed: confirmed);
                  if (saved && mounted) {
                    token.clear();
                    setState(() => confirmed = false);
                  }
                },
          child: const Text('Claim original invitation'),
        ),
        if (c.busy)
          const Text('Verifying claim and authorized patient readback…'),
        if (c.error != null) Text(c.error!),
        if (c.outcome != null) Text(c.outcome!),
        if (c.pending != null) ...[
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(),
            child: const Text('Check original claim'),
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(retry: true),
            child: const Text('Reconcile and retry original claim'),
          ),
        ],
        if (c.grant != null)
          Text(
            'Current patient: ${c.grant!.grant.patientId} · effective scopes: ${c.grant!.effective.join(', ')}. Return and refresh connected patients.',
          ),
        const Text(
          'A claimed connection has a fixed expiry and can be revoked. No export function or medical-license badge is enabled.',
        ),
      ],
    ),
  );
}
