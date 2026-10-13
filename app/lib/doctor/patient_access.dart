import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import 'doctor_models.dart';

class PatientAccessController extends ChangeNotifier {
  PatientAccessController()
    : generation = ApiService.instance.sessionGeneration,
      owner = ApiService.instance.authenticatedOwner {
    api.addListener(_sessionChanged);
  }
  final api = ApiService.instance;
  final int generation;
  final String? owner;
  List<DoctorGrant>? grants;
  bool loading = false, saving = false;
  String? error;
  int _revision = 0;
  bool _disposed = false;
  Timer? _expiry;
  bool get current =>
      !_disposed &&
      api.isCurrentSession(generation) &&
      api.canManageDoctorGrants &&
      api.authenticatedOwner == owner;
  void _sessionChanged() {
    if (!current) clear();
  }

  void clear() {
    if (_disposed) return;
    _revision++;
    _expiry?.cancel();
    grants = null;
    loading = saving = false;
    error = null;
    notifyListeners();
  }

  Future<List<DoctorGrant>> _read() async {
    final data = (await api.patientGrantResource(generation) as List)
        .cast<Map<String, dynamic>>();
    if (!current) throw ApiException('Patient session changed.');
    final parsed = data
        .map((v) => DoctorGrant.fromApi(v, patient: owner!))
        .toList();
    if (parsed.map((v) => v.id).toSet().length != parsed.length) {
      throw const FormatException('Duplicate access grant');
    }
    for (final grant in parsed) {
      if (grant.confirmedRevoked) {
        api.uncertainGrantRevocations.remove(grant.id);
      }
    }
    return parsed;
  }

  Future<void> refresh() async {
    if (!current || loading || saving) return;
    final revision = ++_revision;
    loading = true;
    error = null;
    grants = null;
    notifyListeners();
    try {
      final rows = await _read();
      if (!current || revision != _revision) return;
      grants = List.unmodifiable(rows);
      _expiry?.cancel();
      final dates =
          rows
              .where(
                (g) =>
                    ['active', 'pending'].contains(g.status) &&
                    g.expiresAt.isAfter(DateTime.now().toUtc()),
              )
              .map((g) => g.expiresAt)
              .toList()
            ..sort();
      if (dates.isNotEmpty) {
        _expiry = Timer(dates.first.difference(DateTime.now().toUtc()), () {
          if (!current) return;
          grants = null;
          error =
              'An access expiry was reached. Refresh to confirm current sharing.';
          notifyListeners();
        });
      }
    } catch (failure) {
      if (!current || revision != _revision) return;
      error = RequestFailure.from(failure).message;
      grants = null;
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> revoke(String id) async {
    if (!current ||
        loading ||
        saving ||
        api.uncertainGrantRevocations.contains(id) ||
        grants?.any((g) => g.id == id) != true) {
      return false;
    }
    final revision = _revision;
    saving = true;
    error = null;
    notifyListeners();
    bool sent = false, acknowledged = false;
    try {
      final rows = await _read();
      final actual = rows.where((g) => g.id == id).firstOrNull;
      if (actual == null || !current || revision != _revision) {
        throw const FormatException('Grant changed');
      }
      sent = true;
      final response =
          await api.patientGrantResource(generation, revokeId: id)
              as Map<String, dynamic>;
      final receipt = DoctorGrant.fromApi(response, patient: owner!);
      if (receipt.id != id ||
          receipt.status != 'revoked' ||
          response['revoked_at'] == null ||
          response['revoked_by'] != owner) {
        throw const FormatException('Unconfirmed revocation');
      }
      acknowledged = true;
      final after = await _read();
      final verified = after.where((g) => g.id == id).firstOrNull;
      if (verified == null ||
          !verified.confirmedRevoked ||
          verified.revokedAt != receipt.revokedAt ||
          !current ||
          revision != _revision) {
        throw const FormatException('Revocation readback unavailable');
      }
      grants = List.unmodifiable(after);
      api.uncertainGrantRevocations.remove(id);
      return true;
    } catch (failure) {
      if (!current || revision != _revision) return false;
      if (sent &&
          !(!acknowledged &&
              failure is RequestFailure &&
              [
                RequestFailureKind.denied,
                RequestFailureKind.rejected,
              ].contains(failure.kind))) {
        api.uncertainGrantRevocations.add(id);
      }
      grants = null;
      error = sent
          ? 'Access revocation is not confirmed. Refresh to verify; do not resend an uncertain request.'
          : 'Access could not be verified. Refresh before revoking.';
      return false;
    } finally {
      if (!_disposed && revision == _revision) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _expiry?.cancel();
    api.removeListener(_sessionChanged);
    grants = null;
    super.dispose();
  }
}

class PatientAccessScreen extends StatefulWidget {
  const PatientAccessScreen({super.key});
  @override
  State<PatientAccessScreen> createState() => _PatientAccessScreenState();
}

class _PatientAccessScreenState extends State<PatientAccessScreen> {
  late final controller = PatientAccessController();
  @override
  void initState() {
    super.initState();
    controller.refresh();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> revoke(DoctorGrant grant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke clinician access?'),
        content: const Text(
          'The server must confirm this change before access is shown as revoked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !controller.current) return;
    final saved = await controller.revoke(grant.id);
    if (!mounted || !controller.current) return;
    if (saved) {
      showDermaireSnack(context, 'Access revocation confirmed by server.');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.current) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text(
              'Patient access management is unavailable for this session.',
            ),
          ),
        );
      }
      return DermairePage(
        eyebrow: 'Sharing permissions',
        title: 'Clinician access',
        children: [
          const Text(
            'Creating new clinician connections is unavailable. Viewing and export permissions must be confirmed separately. Export is unavailable in this app.',
          ),
          OutlinedButton(
            onPressed: controller.loading || controller.saving
                ? null
                : controller.refresh,
            child: const Text('Refresh access'),
          ),
          if (controller.loading || controller.saving)
            if (EntryMotion.reduced(context))
              const Text('Verifying access…')
            else
              const LinearProgressIndicator(
                semanticsLabel: 'Verifying clinical access',
              ),
          if (controller.error != null) Text(controller.error!),
          if (controller.api.uncertainGrantRevocations.isNotEmpty)
            const Text(
              'A revocation outcome is unconfirmed. Read current access before continuing.',
            ),
          if (!controller.loading &&
              controller.error == null &&
              controller.grants?.isEmpty == true)
            const Text('The server returned no clinician access grants.'),
          for (final grant in controller.grants ?? <DoctorGrant>[])
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grant.doctorIdValue == null
                        ? 'Unclaimed clinician access'
                        : 'Linked clinician access',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('Server status: ${grant.status}'),
                  Text(
                    'Expires: ${grant.expiresAt.toUtc().toIso8601String()} (UTC)',
                  ),
                  const Text(
                    'Detailed viewing and export permission scopes are unavailable.',
                  ),
                  if (['active', 'pending'].contains(grant.status))
                    OutlinedButton(
                      onPressed:
                          controller.saving ||
                              controller.api.uncertainGrantRevocations.contains(
                                grant.id,
                              )
                          ? null
                          : () => revoke(grant),
                      child: const Text('Revoke access'),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
