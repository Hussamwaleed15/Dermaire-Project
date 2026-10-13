import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'clinical_status_test.dart' as c;

class DoctorWire {
  String owner = 'doctor-1', role = 'doctor', patient = 'patient-1';
  bool accepted = true;
  String noteMode = 'success';
  int? listStatus;
  int? profileStatus;
  bool malformedList = false;
  int writes = 0;
  final requests = <http.Request>[];
  final saved = <Map<String, dynamic>>[];
  Completer<http.Response>? pending;
  Map<String, dynamic> get profile => {
    'id': owner,
    'role': role,
    'safety_accepted': accepted,
    'full_name': 'Synthetic clinician',
    'email': 'doctor@example.invalid',
    'skin_concerns': [],
  };
  Map<String, dynamic> grant([String status = 'active']) => {
    'id': 'grant-$patient',
    'patient_id': patient,
    'doctor_id': owner,
    'granted_by': patient,
    'status': status,
    'created_at': '2026-10-01T00:00:00Z',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String(),
    'claimed_at': '2026-10-01T01:00:00Z',
    'revoked_at': null,
    'revoked_by': null,
  };
  Map<String, dynamic> note(String content) => {
    'id': 'note-1',
    'patient_id': patient,
    'doctor_id': owner,
    'content': content,
    'priority': 'routine',
    'patient_visible': false,
    'follow_up': null,
    'provenance': 'clinician_authored',
    'created_at': '2026-10-01T10:00:00Z',
    'updated_at': '2026-10-01T10:00:00Z',
  };
  Map<String, dynamic> get row => {
    'patient_id': patient,
    'full_name': 'Real Patient',
    'last_check_in': '2026-10-01',
    'active_experiment': null,
    'priority': 'urgent',
    'active_products_count': 0,
    'access': [grant()],
    'safety': c.safety(status: 'urgent'),
    'review_state': 'not_requested',
    'notes': saved,
  };
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/auth/login')) {
      return json({
        'access_token': 'reused-doctor-token',
        'user_id': owner,
        'role': role,
        'expires_in': 3600,
      });
    }
    if (path.endsWith('/auth/logout')) return http.Response('', 204);
    if (path.endsWith('/users/me')) return json(profile, profileStatus ?? 200);
    if (path.endsWith('/auth/accept-safety')) {
      accepted = true;
      return json({'accepted': true});
    }
    if (pending != null) return pending!.future;
    if (path.endsWith('/doctor/patients')) {
      return json(malformedList ? [{}] : [row], listStatus ?? 200);
    }
    if (path.endsWith('/doctor/patients/$patient')) {
      return json({
        'patient_id': patient,
        'full_name': 'Real Patient',
        'access': grant(),
        'review': c.review(owner: patient),
      });
    }
    if (path.endsWith('/notes')) {
      if (request.method == 'POST') {
        writes++;
        if (noteMode == 'network') {
          throw http.ClientException('Synthetic offline');
        }
        if (noteMode == 'failure') return json({}, 403);
        final data = note(
          (jsonDecode(request.body) as Map)['content'] as String,
        );
        if (noteMode == 'malformed') data['created_at'] = 'invalid';
        saved.add(data);
        return json(data, 201);
      }
      if (noteMode == 'readback denied' && writes > 0) return json({}, 403);
      return json(saved);
    }
    return json({}, 404);
  }

  void expectHost(http.Request request) {
    if (request.url.host != 'flutter-tests.invalid') {
      throw StateError('Test HTTP host denied');
    }
  }

  Future<void> login() async {
    await ApiService.instance.login(
      email: 'doctor@example.invalid',
      password: 'synthetic',
      requiredRole: role == 'doctor' ? 'doctor' : null,
    );
    await ApiService.instance.readSafetyAcceptance();
  }

  Future<T> run<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => MockClient(call));
}

http.Response json(Object? value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
