import '../integration/contract.dart';
import '../integration/operation_identity.dart';
import '../entry/server_entry_metadata.dart';
import 'dart:convert';
import 'api_exception.dart';
import 'request_failure.dart';
export 'api_exception.dart';
import 'dart:async';
import 'dart:typed_data';
import '../account/account_profile.dart';
import '../clinical/clinical_models.dart';
import '../observations/observation_models.dart';
import '../capture/photo_preparation.dart';
import '../capture/guided_capture_models.dart';
import '../capture/capture_history_models.dart';
import '../psm/psm_models.dart';
import '../assistance/assistance_models.dart';
import '../assistance/assistance_controller.dart' show AssistanceReadException;
import '../psm/psm_controller.dart' show PsmReadException;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService extends ChangeNotifier {
  ApiService._();
  static final ApiService instance = ApiService._();

  Future<Map<String, dynamic>> submitCapture(
    Uint8List bytes,
    String filename,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/captures'),
    );
    request.headers.addAll(_headers(false));
    request.fields.addAll({'source': 'upload', 'view': 'front'});
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    request.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: isPng ? 'capture.png' : 'capture.jpg',
        contentType: MediaType.parse(isPng ? 'image/png' : 'image/jpeg'),
      ),
    );
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201) {
      throw ApiException('Capture quality checking failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getCaptureHistory() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/captures'), headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ApiException('Capture history unavailable');
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  void _guardGuidedCapture(int generation) {
    if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
      throw ApiException(
        'Your session changed. Reopen the photo flow after sign-in.',
      );
    }
  }

  Future<GuidedCaptureRecord> submitGuidedCapture({
    required PreparedPhoto photo,
    required String source,
    required String attemptKey,
    required int generation,
  }) async {
    _guardGuidedCapture(generation);
    final owner = _sessionUserId!;
    if (!['camera', 'upload'].contains(source) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(attemptKey) ||
        photo.bytes.length > maxPhotoBytes) {
      throw ArgumentError('Invalid prepared upload');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/captures'),
    );
    request.headers.addAll(_headers(false));
    request.headers['Idempotency-Key'] = attemptKey;
    request.fields.addAll({'source': source, 'view': 'front'});
    request.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        Uint8List.fromList(photo.bytes),
        filename: photo.filename,
        contentType: MediaType.parse(photo.mime),
      ),
    );
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
    _guardGuidedCapture(generation);
    if ([400, 403, 409, 413, 415, 422].contains(response.statusCode)) {
      throw const GuidedCaptureWriteException(CaptureWriteFailure.rejected);
    }
    if (response.statusCode != 201) {
      throw const GuidedCaptureWriteException(CaptureWriteFailure.uncertain);
    }
    String? candidate;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ref = data['image_reference'];
      if (data['id'] is String &&
          RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(data['id'] as String) &&
          (ref == null ||
              ref is String &&
                  ref.startsWith('skin_photos/$owner/${owner}_'))) {
        candidate = data['id'] as String;
      }
      return GuidedCaptureRecord.fromApi(data, owner: owner);
    } catch (_) {
      throw GuidedCaptureWriteException(
        CaptureWriteFailure.uncertain,
        candidateId: candidate,
      );
    }
  }

  Future<Map<String, dynamic>> _readCaptureResource(
    String path,
    int generation,
  ) async {
    _guardGuidedCapture(generation);
    final response = await _client
        .get(Uri.parse('$baseUrl/$path'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    _guardGuidedCapture(generation);
    if (response.statusCode != 200) {
      throw PrivateCaptureException(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<GuidedCaptureRecord> readGuidedCapture({
    required String id,
    required int generation,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid capture identity');
    }
    final data = await _readCaptureResource('captures/$id', generation);
    final record = GuidedCaptureRecord.fromApi(
      data,
      owner: _sessionUserId!,
      readback: true,
    );
    if (record.id != id) {
      throw const FormatException('Capture identity mismatch');
    }
    return record;
  }

  Future<CaptureMeasurement> readCaptureMeasurement({
    required String id,
    required int generation,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid capture identity');
    }
    return CaptureMeasurement.fromApi(
      await _readCaptureResource('measurements/$id', generation),
      captureId: id,
    );
  }

  Future<List<GuidedCaptureRecord>> readPrivateCaptureHistory(
    int generation,
  ) async {
    _guardGuidedCapture(generation);
    final owner = _sessionUserId!;
    final response = await _client
        .get(Uri.parse('$baseUrl/captures?limit=100'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    _guardGuidedCapture(generation);
    if (response.statusCode != 200) {
      throw PrivateCaptureException(response.statusCode);
    }
    return parseCaptureHistory(jsonDecode(response.body), owner);
  }

  Future<PrivateImageBytes> readPrivateCaptureImage(
    String id,
    int generation,
  ) async {
    _guardGuidedCapture(generation);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid capture identity');
    }
    final request = _PrivateImageRequest(
      Uri.parse('$baseUrl/captures/$id/image'),
    );
    request.headers.addAll(_headers(false));
    final response = await _client.send(request);
    _guardGuidedCapture(generation);
    if (response.statusCode != 200) {
      throw PrivateCaptureException(response.statusCode);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    _guardGuidedCapture(generation);
    return PrivateImageBytes(bytes, response.headers['content-type'] ?? '');
  }

  Future<PrivateImageBytes> readDoctorCaptureImage(
    String id,
    int generation, {
    required Listenable scope,
    required bool Function() active,
  }) async {
    void guard() {
      if (!isCurrentSession(generation) ||
          !canReadDoctorWorkspace ||
          !active()) {
        throw ApiException('Doctor image access ended.');
      }
    }

    guard();
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid capture identity');
    }
    final request = _DoctorImageRequest(
      Uri.parse('$baseUrl/captures/$id/image'),
      scope,
      active,
    )..headers.addAll(_headers(false));
    final response = await _client.send(request);
    guard();
    if (response.statusCode != 200) {
      throw PrivateCaptureException(response.statusCode);
    }
    final bytes = await response.stream.toBytes();
    guard();
    return PrivateImageBytes(bytes, response.headers['content-type'] ?? '');
  }

  Future<PersonalSkinModel> readPersonalSkinModel(int generation) async {
    void guard() {
      if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
        throw ApiException(
          'Session changed. Reopen your skin evidence after sign-in.',
        );
      }
    }

    guard();
    final owner = _sessionUserId!;
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/personal-skin-model'),
    );
    request.headers.addAll(_headers(false));
    request.followRedirects = false;
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    guard();
    if (response.statusCode != 200) throw PsmReadException(response.statusCode);
    return PersonalSkinModel.fromApi(
      jsonDecode(response.body) as Map<String, dynamic>,
      owner: owner,
    );
  }

  static const String _tokenKey = 'dermaire_jwt_token';
  static const String _userKey = 'dermaire_user_data';

  String get defaultBaseUrl {
    return 'https://dermaire-api.azurewebsites.net/api/v1';
  }

  late String baseUrl = defaultBaseUrl;
  final http.Client _client = _SessionClient();
  Timer? _expiryTimer;
  DateTime? _expiresAt;
  String? _authToken;
  Map<String, dynamic>? _currentUser;
  int _sessionGeneration = 0;
  String? _sessionUserId;
  int? _consentGeneration;
  bool? _confirmedSafetyAcceptance;
  String? _sessionRole;
  Map<String, dynamic>? _consentUser;
  ServerEntryMetadata? _entryMetadata;
  final Map<String, PendingIntent> integrationIntents = {};
  final Map<String, String> integrationReferences = {};
  final Map<String, OperationIdentity> _quarantinedOperations = {};
  List<OperationIdentity> get quarantinedOperations => isAuthenticated
      ? List.unmodifiable(
          _quarantinedOperations.values.where(
            (v) => v.owner == authenticatedOwner && v.role == authenticatedRole,
          ),
        )
      : const [];
  void _guardQuarantinedMutation(http.BaseRequest request) {
    if (['GET', 'HEAD', 'OPTIONS'].contains(request.method)) return;
    final root = Uri.parse(baseUrl).path;
    final path = request.url.path.startsWith('$root/')
        ? request.url.path.substring(root.length + 1)
        : '';
    if (quarantinedOperations.any((v) => v.path == path)) {
      // These replacement intents never reached HTTP. Retain only the original
      // quarantine rather than minting another uncertain identity.
      final originals = quarantinedOperations.map((v) => v.key).toSet();
      integrationIntents.removeWhere(
        (_, op) => op.path == path && !originals.contains(op.key),
      );
      throw QuarantinedOperationFailure();
    }
  }

  String? get requiredSafetyPolicyVersion => _entryMetadata?.requiredPolicy;
  bool get profileReviewRequired =>
      hasConfirmedSafetyAcceptance &&
      _entryMetadata?.profileReviewRequired == true;
  int _profileRevision = 0;
  int? _consentProfileRevision;

  int get sessionGeneration => _sessionGeneration;
  bool isCurrentSession(int generation) =>
      generation == _sessionGeneration && isAuthenticated;
  bool get hasConfirmedSafetyAcceptance =>
      isCurrentSession(_consentGeneration ?? -1) &&
      _confirmedSafetyAcceptance == true;

  // Presentation guard only; the server still authorizes every patient read.
  bool get canReadPatientClinicalStatus =>
      isAuthenticated &&
      hasConfirmedSafetyAcceptance &&
      _sessionRole == 'patient';

  /// Profile receipt and token identity must agree. This is account role, not
  /// proof of a medical license. The backend still authorizes each operation.
  bool get canReadDoctorWorkspace =>
      isAuthenticated &&
      hasConfirmedSafetyAcceptance &&
      _sessionRole == 'doctor' &&
      _consentUser?['role'] == 'doctor' &&
      _consentUser?['id'] == _sessionUserId;
  String? get doctorOwner => canReadDoctorWorkspace ? _sessionUserId : null;
  String? get authenticatedOwner => isAuthenticated ? _sessionUserId : null;
  String? get authenticatedRole => isAuthenticated ? _sessionRole : null;
  final Set<String> uncertainDoctorWrites = {};
  final Set<String> inFlightDoctorWrites = {};
  final Map<String, Map<String, dynamic>> pendingDoctorReceipts = {};

  Future<Object?> doctorResource(
    String path,
    int generation, {
    String method = 'GET',
    Map<String, dynamic>? payload,
  }) async {
    void guard() {
      if (!isCurrentSession(generation) || !canReadDoctorWorkspace) {
        throw ApiException(
          'Doctor session changed. Sign in and verify your account again.',
        );
      }
    }

    guard();
    if (!RegExp(
          r'^patients(/[A-Za-z0-9_-]+)?(/(notes|reviews|timeline))?(\?offset=[0-9]+&limit=[0-9]+)?$',
        ).hasMatch(path) ||
        !(method == 'GET' ||
            method == 'POST' &&
                RegExp(
                  r'^patients/[A-Za-z0-9_-]+/(notes|reviews)$',
                ).hasMatch(path))) {
      throw ArgumentError('Invalid doctor resource');
    }
    final request = http.Request(method, Uri.parse('$baseUrl/doctor/$path'))
      ..followRedirects = false;
    request.headers.addAll(_headers(payload != null));
    if (payload != null) request.body = jsonEncode(payload);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    guard();
    if (response.statusCode != (method == 'POST' ? 201 : 200)) {
      throw RequestFailure.http(response.statusCode);
    }
    return jsonDecode(response.body);
  }

  Future<IntegrationResponse> integrationResource(
    String path,
    int generation, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? key,
    Map<String, String> preconditions = const {},
    bool withdrawal = false,
  }) async {
    void guard() {
      if (!isCurrentSession(generation) ||
          !['patient', 'doctor'].contains(authenticatedRole) ||
          (!withdrawal &&
              !(canReadPatientClinicalStatus || canReadDoctorWorkspace))) {
        throw IntegrationFailure(401);
      }
    }

    guard();
    if (!RegExp(r'^[A-Za-z0-9_/-]+$').hasMatch(path) ||
        path.contains('//') ||
        ![
          'messaging',
          'clinical-plans',
          'clinical-snapshot',
          'notifications',
          'agent',
          'doctor',
          'users',
        ].contains(path.split('/').first) ||
        !['GET', 'POST', 'PUT', 'DELETE'].contains(method) ||
        (path.split('/').first == 'clinical-snapshot' &&
            (method != 'GET' ||
                !RegExp(
                  r'^clinical-snapshot(/patients/[A-Za-z0-9_-]+)?$',
                ).hasMatch(path))) ||
        (withdrawal &&
            !(method == 'DELETE' &&
                    (path.startsWith('agent/') ||
                        path.startsWith('notifications/') ||
                        path.startsWith('messaging/') ||
                        path.startsWith('doctor/access/') ||
                        RegExp(
                              r'^doctor/revoke/[A-Za-z0-9_-]+$',
                            ).hasMatch(path) &&
                            authenticatedRole == 'patient' ||
                        RegExp(
                          r'^clinical-plans/[A-Za-z0-9_-]+/evaluation$',
                        ).hasMatch(path)) ||
                method == 'GET' &&
                    authenticatedRole == 'patient' &&
                    (path == 'doctor/access' ||
                        RegExp(
                          r'^doctor/consent-attempts/(revoke|revoke_all)/[A-Za-z0-9_-]{16,128}$',
                        ).hasMatch(path))))) {
      throw ArgumentError('Invalid integration resource');
    }
    if (key != null && !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(key)) {
      throw ArgumentError('Invalid operation key');
    }
    final request = http.Request(
      method,
      Uri.parse('$baseUrl/$path').replace(queryParameters: query),
    )..followRedirects = false;
    request.headers.addAll(_headers(body != null));
    request.headers.addAll(preconditions);
    if (key != null) request.headers['Idempotency-Key'] = key;
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    guard();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationFailure(response.statusCode);
    }
    return IntegrationResponse(
      response.body.isEmpty ? null : jsonDecode(response.body),
      Map.unmodifiable(response.headers),
      response.statusCode,
    );
  }

  /// Withdrawal-only patient adapter. Clinical content is discarded at this
  /// boundary; ordinary integration reads still require current safety consent.
  Future<Map<String, dynamic>> planWithdrawalMetadata(
    String path,
    int generation, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? key,
    Map<String, String>? query,
  }) async {
    void guard() {
      if (!isCurrentSession(generation) ||
          authenticatedRole != 'patient' ||
          authenticatedOwner == null) {
        throw IntegrationFailure(401);
      }
    }

    guard();
    final detail = RegExp(r'^clinical-plans/[A-Za-z0-9_-]+$').hasMatch(path);
    final attempt = RegExp(
      r'^clinical-plans/[A-Za-z0-9_-]+/attempts/cancel/[A-Za-z0-9_-]{16,128}$',
    ).hasMatch(path);
    final evaluation = RegExp(
      r'^clinical-plans/[A-Za-z0-9_-]+/evaluation$',
    ).hasMatch(path);
    final history = RegExp(
      r'^clinical-plans/[A-Za-z0-9_-]+/history$',
    ).hasMatch(path);
    if (!(method == 'GET' &&
            (path == 'clinical-plans' ||
                detail ||
                attempt ||
                evaluation ||
                history) ||
        method == 'DELETE' &&
            evaluation &&
            query?['expected_revision'] != null &&
            RegExp(r'^[1-9][0-9]*$').hasMatch(query!['expected_revision']!) ||
        method == 'POST' &&
            RegExp(r'^clinical-plans/[A-Za-z0-9_-]+/cancel$').hasMatch(path) &&
            key != null &&
            RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(key))) {
      throw ArgumentError('Invalid plan withdrawal resource');
    }
    final request = http.Request(
      method,
      Uri.parse('$baseUrl/$path').replace(queryParameters: query),
    )..followRedirects = false;
    request.headers.addAll(_headers(body != null));
    if (body != null) request.body = jsonEncode(body);
    if (key != null) request.headers['Idempotency-Key'] = key;
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    guard();
    if (response.statusCode != 200) {
      throw IntegrationFailure(response.statusCode);
    }
    Map<String, dynamic> meta(Object? raw) {
      if (raw is! Map ||
          raw['schema_version'] != 'clinical-plan-1' ||
          raw['patient_id'] != authenticatedOwner ||
          raw['revision'] is! int ||
          raw['revision'] < 1 ||
          raw['clinical_clearance'] != false ||
          !['follow_up', 'comparison'].contains(raw['kind']) ||
          ![
            'proposed',
            'scheduled',
            'captured',
            'reviewed',
            'cancelled',
          ].contains(raw['state'])) {
        throw const FormatException('Invalid withdrawal metadata');
      }
      for (final field in ['id', 'patient_id', 'doctor_id', 'access_id']) {
        if (raw[field] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw[field])) {
          throw const FormatException('Invalid plan scope');
        }
      }
      return {
        for (final field in [
          'id',
          'patient_id',
          'doctor_id',
          'access_id',
          'kind',
          'revision',
          'state',
        ])
          field: raw[field],
      };
    }

    final raw = jsonDecode(response.body);
    if (raw is! Map) throw const FormatException('Invalid withdrawal response');
    Map<String, dynamic> jobMeta(Object? source) {
      if (source is! Map) {
        throw const FormatException('Invalid evaluation history');
      }
      final value = source;
      final input = value['input'];
      if (value['schema_version'] != 'comparison-job-1' ||
          value['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value['id']) ||
          input is! Map ||
          input['plan_id'] != path.split('/')[1] ||
          value['plan_revision'] is! int ||
          value['plan_revision'] < 1 ||
          ![
            'queued',
            'running',
            'unavailable',
            'pending_human_review',
            'cancelled',
            'reviewed',
            'rejected',
          ].contains(value['state']) ||
          value['clinical_clearance'] != false ||
          value['medical_resources_modified'] != false ||
          (value['effective_state'] != null &&
              value['effective_state'] != 'cancelled')) {
        throw const FormatException('Invalid evaluation withdrawal metadata');
      }
      return {
        'id': value['id'],
        'plan_id': input['plan_id'],
        'plan_revision': value['plan_revision'],
        'state': value['state'],
        'effective_state': value['effective_state'],
      };
    }

    if (evaluation) {
      if (raw['state'] == 'not_requested' && method == 'GET') {
        return {'state': 'not_requested'};
      }
      return jobMeta(raw);
    }
    if (history) {
      final after = int.tryParse(query?['after_revision'] ?? '0') ?? -1;
      if (after < 0 ||
          raw['items'] is! List ||
          (raw['items'] as List).length > 100 ||
          raw['numeric_comparison_metrics'] != null) {
        throw const FormatException('Invalid evaluation history page');
      }
      var last = after;
      final events = <Map<String, dynamic>>[];
      for (final event in raw['items'] as List) {
        if (event is! Map ||
            event['revision'] is! int ||
            event['revision'] <= last ||
            event['actor_id'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(event['actor_id']) ||
            event['recorded_at'] is! String ||
            DateTime.tryParse(event['recorded_at'])?.isUtc != true) {
          throw const FormatException('Unordered evaluation history');
        }
        last = event['revision'];
        if (event['operation'] == 'evaluation') {
          final job = jobMeta(event['snapshot']);
          if (job['plan_revision'] != last) {
            throw const FormatException('Wrong evaluation event revision');
          }
          events.add({
            'revision': last,
            'actor_id': event['actor_id'],
            'recorded_at': event['recorded_at'],
            'job': job,
          });
        } else {
          final snapshot = event['snapshot'];
          if (snapshot is! Map) {
            throw const FormatException('Invalid plan event');
          }
          final plan = meta(snapshot['plan']);
          if (plan['id'] != path.split('/')[1] || plan['revision'] != last) {
            throw const FormatException('Wrong historical plan');
          }
        }
      }
      final next = raw['next_after_revision'];
      if (next != null && (next is! int || next != last || last == after)) {
        throw const FormatException('Invalid evaluation history cursor');
      }
      return {
        'events': events,
        'scanned_through': last,
        'next_after_revision': next,
      };
    }
    if (path == 'clinical-plans') {
      if (raw['items'] is! List ||
          (raw['next_after'] != null &&
              (raw['next_after'] is! String ||
                  !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw['next_after'])))) {
        throw const FormatException('Invalid plan page');
      }
      return {
        'items': (raw['items'] as List).map(meta).toList(),
        'next_after': raw['next_after'],
      };
    }
    if (attempt) {
      if (!['unknown', 'expired', 'committed'].contains(raw['status']) ||
          raw['attempt_id'] is! String ||
          (raw['status'] != 'committed' && raw['result'] != null)) {
        throw const FormatException('Invalid cancellation receipt');
      }
      return {
        'status': raw['status'],
        'result': raw['result'] == null ? null : meta(raw['result']),
      };
    }
    final result = meta(raw);
    if (result['id'] != path.split('/')[1]) {
      throw const FormatException('Wrong plan identity');
    }
    return result;
  }

  Future<void> completeProfileReview() async {
    final generation = sessionGeneration;
    await integrationResource(
      'users/profile-review',
      generation,
      method: 'POST',
      body: {'reviewed': true},
    );
    if (!isCurrentSession(generation)) throw IntegrationFailure(401);
    await readSafetyAcceptance();
    if (profileReviewRequired) {
      throw const FormatException('Profile review not confirmed');
    }
  }

  Future<Map<String, dynamic>> _readClinical(
    String path,
    int generation,
  ) async {
    if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
      throw ClinicalRequestException(
        'Sign in and confirm safety acceptance to view clinical information.',
      );
    }
    final response = await _client
        .get(Uri.parse('$baseUrl/$path'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
      throw ClinicalRequestException(
        'Your session changed. Please sign in again.',
      );
    }
    if (response.statusCode == 403) {
      throw ClinicalRequestException(
        'Access to this clinical information was denied. Refresh or sign in again.',
        status: 403,
      );
    }
    if (response.statusCode != 200) {
      throw ClinicalRequestException(
        'Clinical information is unavailable. Refresh to confirm the latest information.',
      );
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ClinicalRequestException(
        'The clinical response could not be verified. Please refresh.',
      );
    }
  }

  Future<SafetyAssessment> getPatientSafety({required int generation}) async =>
      SafetyAssessment.fromApi(await _readClinical('safety', generation));

  Future<ClinicianReview> getPatientClinicalReview({
    required int generation,
  }) async {
    final owner = _sessionUserId;
    final value = await _readClinical('doctor/review-status', generation);
    if (owner == null || !isCurrentSession(generation)) {
      throw ClinicalRequestException(
        'Your session changed. Please sign in again.',
      );
    }
    return ClinicianReview.fromApi(value, owner: owner);
  }

  String? get observationOwner =>
      canReadPatientClinicalStatus ? _sessionUserId : null;

  void _guardObservation(int generation) {
    if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
      throw ApiException(
        'Sign in and confirm safety acceptance to use your observations.',
      );
    }
  }

  Future<List<ObservationRecord>> getPatientObservations({
    required int generation,
  }) async {
    _guardObservation(generation);
    final owner = _sessionUserId!;
    final response = await _client
        .get(Uri.parse('$baseUrl/checkins'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    _guardObservation(generation);
    if (response.statusCode != 200) {
      throw RequestFailure.http(response.statusCode);
    }
    final list = jsonDecode(response.body) as List;
    return List.unmodifiable(
      list.map(
        (row) => ObservationRecord.fromApi(
          row as Map<String, dynamic>,
          owner: owner,
        ),
      ),
    );
  }

  Future<ObservationRecord> submitPatientObservation({
    required ObservationDraft draft,
    required int generation,
  }) async {
    _guardObservation(generation);
    if (draft.validation != null) {
      throw ArgumentError('Invalid observation fields');
    }
    final owner = _sessionUserId!;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/checkins'),
    );
    request.headers.addAll(_headers(false));
    request.fields['time_of_day'] = draft.moment!;
    request.fields['report'] = jsonEncode(draft.report);
    if (draft.submittedNotes != null) {
      request.fields['notes'] = draft.submittedNotes!;
    }
    // Report-only writes have no server idempotency guarantee. Send once only.
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    _guardObservation(generation);
    if ([400, 403, 404, 409, 422].contains(response.statusCode)) {
      throw const ObservationWriteException(ObservationFailure.rejected);
    }
    if (response.statusCode != 201) {
      throw const ObservationWriteException(ObservationFailure.uncertain);
    }
    String? candidate;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['user_id'] == owner &&
          data['id'] is String &&
          (data['id'] as String).isNotEmpty) {
        candidate = data['id'] as String;
      }
      final record = ObservationRecord.fromApi(data, owner: owner);
      if (!record.matches(draft)) {
        throw const FormatException('Observation fields unconfirmed');
      }
      return record;
    } catch (_) {
      throw ObservationWriteException(
        ObservationFailure.uncertain,
        candidateId: candidate,
      );
    }
  }

  // Invalidate earlier auth attempts before sending another request. Logout
  // increments the same generation even when no token has arrived yet.
  Future<int> _beginAuthentication() async {
    final cleanup = _clearSession(preserveOperationIdentity: true);
    final generation = _sessionGeneration;
    await cleanup;
    if (generation != _sessionGeneration) {
      throw ApiException('Session changed. Please sign in again');
    }
    return generation;
  }

  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated =>
      _authToken != null &&
      _expiresAt != null &&
      DateTime.now().isBefore(_expiresAt!);

  Future<void> init() async {
    // Sessions are memory-only. Never restore legacy plaintext credentials.
    await _clearSession();
  }

  Map<String, String> _headers([bool isJson = true]) {
    final headers = <String, String>{};
    if (isJson) headers['Content-Type'] = 'application/json';
    if (_authToken != null && !isAuthenticated) {
      unawaited(_clearSession(preserveOperationIdentity: true));
      throw ApiException('Session expired. Please sign in again');
    }
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String fullName,
    bool acceptSafety = true,
  }) async {
    final generation = await _beginAuthentication();
    final res = await _client
        .post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'full_name': fullName,
            'accept_safety': acceptSafety,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _persistAuth(data, generation);
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Registration failed',
      data,
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? requiredRole,
  }) async {
    final generation = await _beginAuthentication();
    final res = await _client
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (requiredRole != null &&
          (data['role'] != requiredRole ||
              data['user_id'] is! String ||
              (data['user_id'] as String).trim().isEmpty ||
              data['expires_in'] is! int ||
              (data['expires_in'] as int) <= 0)) {
        throw ApiException(
          'This account is not authorized for the clinician workspace',
        );
      }
      await _persistAuth(data, generation);
      return data;
    }
    throw ApiException(data['message']?.toString() ?? 'Login failed', data);
  }

  /// Verifies a real Google ID token (from google_sign_in) with our backend
  /// and signs the user in, creating an account automatically on first use.
  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
  }) async {
    final generation = await _beginAuthentication();
    final res = await _client
        .post(
          Uri.parse('$baseUrl/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id_token': idToken}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _persistAuth(data, generation);
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Google sign-in failed',
      data,
    );
  }

  /// Starts the password-reset flow. The backend emails a reset code when
  /// an account exists for the supplied email address.
  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    throw ApiException(data['message']?.toString() ?? 'Request failed', data);
  }

  /// Completes a password reset using the code sent to the user's email.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'token': token,
        'new_password': newPassword,
      }),
    );
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _clearSession();
      return;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Password reset failed',
      data,
    );
  }

  Future<void> _persistAuth(Map<String, dynamic> data, int generation) async {
    final token = data['access_token'];
    final ttl = data['expires_in'];
    if (token is! String || token.trim().isEmpty || ttl is! int || ttl <= 0) {
      throw ApiException('Invalid authentication response from server');
    }
    if (generation != _sessionGeneration) {
      throw ApiException('Session changed. Please sign in again');
    }
    _authToken = token;
    _sessionUserId = data['user_id'] is String
        ? data['user_id'] as String
        : null;
    _sessionRole = data['role'] is String ? data['role'] as String : null;
    _currentUser = Map.of(data)..remove('access_token');
    _expiresAt = DateTime.now().add(Duration(seconds: ttl));
    _expiryTimer = Timer(
      Duration(seconds: ttl),
      () => unawaited(_clearSession(preserveOperationIdentity: true)),
    );
  }

  Future<void> _clearSession({bool preserveOperationIdentity = false}) async {
    if (preserveOperationIdentity) {
      final owner = _sessionUserId, role = _sessionRole;
      if (owner != null && role != null) {
        for (final op in integrationIntents.values) {
          final identity = OperationIdentity(
            owner: owner,
            role: role,
            path: op.path,
            receiptPath: op.attemptPath,
            key: op.key,
            fingerprint: OperationIdentity.digest(op.body),
            scope: op.recoveryScope,
          );
          _quarantinedOperations['$owner:$role:${op.key}'] = identity;
        }
      }
    } else {
      _quarantinedOperations.clear();
    }
    final hadSession = _authToken != null;
    _sessionGeneration++;
    uncertainDoctorWrites.clear();
    inFlightDoctorWrites.clear();
    pendingDoctorReceipts.clear();
    integrationIntents.clear();
    integrationReferences.clear();
    _entryMetadata = null;
    uncertainGrantRevocations.clear();
    _sessionUserId = null;
    _sessionRole = null;
    _consentUser = null;
    _consentProfileRevision = null;
    _profileRevision++;
    _consentGeneration = null;
    _confirmedSafetyAcceptance = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiresAt = null;
    _authToken = null;
    _currentUser = null;
    if (hadSession) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        _tokenKey,
        _userKey,
        'dermaire_products_v2',
        'dermaire_safety_accepted',
      ]) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Legacy storage is never restored, even when platform cleanup fails.
    }
  }

  Future<void> logout() async {
    final headers = isAuthenticated ? _headers() : null;
    await _clearSession();
    if (headers == null) return;
    try {
      await _client
          .post(Uri.parse('$baseUrl/auth/logout'), headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline logout still clears this device; server expiry remains bounded.
    }
  }

  Future<bool> deleteAccount() async {
    try {
      final res = await _client.delete(
        Uri.parse('$baseUrl/users/me'),
        headers: _headers(false),
      );
      if (res.statusCode != 204) return false;
      await _clearSession();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Patient entry receipt. Only an owner-matched GET establishes acceptance.
  Future<bool> readSafetyAcceptance() async {
    final wasAccepted = _confirmedSafetyAcceptance == true;
    final wasDoctor = canReadDoctorWorkspace;
    final wasPatientGrant = canManageDoctorGrants;
    final revision = ++_profileRevision;
    _consentUser = null;
    _entryMetadata = null;
    final generation = _sessionGeneration;
    final owner = _sessionUserId;
    _consentGeneration = null;
    _confirmedSafetyAcceptance = null;
    if (!isCurrentSession(generation) || owner == null || owner.isEmpty) {
      throw ApiException('Please sign in again to confirm safety acceptance.');
    }
    final res = await _client
        .get(Uri.parse('$baseUrl/users/me'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    _checkConsentResponse(res);
    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      throw ApiException(
        'Safety acceptance could not be verified. Please retry.',
      );
    }
    if (!isCurrentSession(generation)) {
      throw ApiException('Session changed. Please sign in again');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] != owner ||
        decoded['safety_accepted'] is! bool) {
      throw ApiException(
        'Safety acceptance could not be verified. Please retry.',
      );
    }
    _currentUser = decoded;
    // A private deep copy; never hydrate from token/currentUser/draft maps.
    _consentUser = jsonDecode(jsonEncode(decoded)) as Map<String, dynamic>;
    _consentProfileRevision = revision;
    _consentGeneration = generation;
    _entryMetadata = ServerEntryMetadata.fromApi(decoded);
    final accepted = _entryMetadata!.accepted;
    _confirmedSafetyAcceptance = accepted;
    if ((!accepted && wasAccepted) ||
        (wasDoctor && decoded['role'] != 'doctor') ||
        (wasPatientGrant && decoded['role'] != 'patient')) {
      notifyListeners();
    }
    return accepted;
  }

  /// Acknowledges the write only. Call readSafetyAcceptance before entry.
  Future<void> acceptSafetyTerms() async {
    final policy = requiredSafetyPolicyVersion;
    final generation = _sessionGeneration;
    _consentGeneration = null;
    _confirmedSafetyAcceptance = null;
    if (!isCurrentSession(generation)) {
      throw ApiException('Please sign in again to accept safety terms.');
    }
    final res = await _client
        .post(
          Uri.parse('$baseUrl/auth/accept-safety'),
          headers: _headers(),
          // Exact required version from this session's GET; legacy servers retain their default.
          body: jsonEncode({'accepted': true, 'policy_version': ?policy}),
        )
        .timeout(const Duration(seconds: 20));
    if (!isCurrentSession(generation)) {
      throw ApiException('Session changed. Please sign in again');
    }
    _checkConsentResponse(res);
  }

  void _checkConsentResponse(http.Response response) {
    if (response.statusCode == 200) return;
    if (response.statusCode == 403) {
      throw ApiException(
        'Safety acceptance access was denied. Retry or sign in again.',
      );
    }
    throw ApiException('Safety acceptance is unavailable. Please retry.');
  }

  AccountProfile _accountProfile(Map<String, dynamic> data, int generation) {
    if (!isCurrentSession(generation) || !hasConfirmedSafetyAcceptance) {
      throw ProfileRequestException(
        'Please sign in and verify safety acceptance.',
        unauthorized: true,
      );
    }
    final owner = _sessionUserId;
    final role = _sessionRole;
    if (owner == null || role == null) {
      throw ProfileRequestException(
        'Account identity could not be verified. Please sign in again.',
      );
    }
    final AccountProfile profile;
    try {
      profile = AccountProfile.fromApi(data, owner: owner, role: role);
    } catch (_) {
      throw ProfileRequestException(
        'Account profile could not be verified. Please retry.',
      );
    }
    if (data['safety_accepted'] != true) {
      _confirmedSafetyAcceptance = false;
      _consentUser = null;
      notifyListeners();
      throw ProfileRequestException(
        'Please verify safety acceptance again.',
        unauthorized: true,
      );
    }
    return profile;
  }

  Future<AccountProfile> readAccountProfile({bool reuseConsent = true}) async {
    final generation = _sessionGeneration;
    if (reuseConsent &&
        _consentUser != null &&
        _consentProfileRevision == _profileRevision) {
      return _accountProfile(_consentUser!, generation);
    }
    if (!isCurrentSession(generation) || !hasConfirmedSafetyAcceptance) {
      throw ProfileRequestException(
        'Please sign in and verify safety acceptance.',
        unauthorized: true,
      );
    }
    final revision = ++_profileRevision;
    final response = await _client
        .get(Uri.parse('$baseUrl/users/me'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    if (revision != _profileRevision || !isCurrentSession(generation)) {
      throw ProfileRequestException(
        'A newer account request replaced this response.',
      );
    }
    if (response.statusCode != 200) {
      throw ProfileRequestException(
        response.statusCode == 403
            ? 'Profile access was denied. Retry or sign in again.'
            : 'Account profile is unavailable. Please retry.',
      );
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ProfileRequestException(
        'Account profile could not be verified. Please retry.',
      );
    }
    final profile = _accountProfile(data, generation);
    _currentUser = data;
    return profile;
  }

  Future<AccountProfile> updateAccountProfile(
    Map<String, dynamic> fields,
  ) async {
    final generation = _sessionGeneration;
    final data = await updateSkinProfile(fields: fields, validateAccount: true);
    return _accountProfile(data, generation);
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers(false),
    );
    if (res.statusCode == 200 && res.body.isNotEmpty) {
      final user = jsonDecode(res.body) as Map<String, dynamic>;
      _currentUser = user;
      return user;
    }
    return null;
  }

  Future<Map<String, dynamic>> updateSkinProfile({
    String? skinType,
    String? selectedGoal,
    List<String>? skinConcerns,
    Map<String, dynamic>? fields,
    bool validateAccount = false,
  }) async {
    final generation = _sessionGeneration;
    final revision = validateAccount ? ++_profileRevision : _profileRevision;
    if (validateAccount &&
        (!isCurrentSession(generation) || !hasConfirmedSafetyAcceptance)) {
      throw ProfileRequestException(
        'Please sign in and verify safety acceptance.',
        unauthorized: true,
      );
    }
    final bodyMap = <String, dynamic>{...?fields};
    if (skinType != null) bodyMap['skin_type'] = skinType;
    if (selectedGoal != null) bodyMap['selected_goal'] = selectedGoal;
    if (skinConcerns != null) bodyMap['skin_concerns'] = skinConcerns;

    final pending = _client.patch(
      Uri.parse('$baseUrl/users/skin-profile'),
      headers: _headers(),
      body: jsonEncode(bodyMap),
    );
    final res = validateAccount
        ? await pending.timeout(const Duration(seconds: 20))
        : await pending;
    if (validateAccount &&
        (revision != _profileRevision || !isCurrentSession(generation))) {
      throw ProfileRequestException(
        'A newer account request replaced this response.',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 &&
        data['skin_concerns'] is List &&
        (data['skin_concerns'] as List).every((v) => v is String) &&
        data.containsKey('profile_context') &&
        (data['profile_context'] == null || data['profile_context'] is Map)) {
      if (validateAccount) _accountProfile(data, generation);
      _currentUser = data;
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Failed to update skin profile',
      data,
    );
  }

  Future<AssistanceResponse> requestPatientAssistance(
    String message,
    int generation,
  ) async {
    final owner = observationOwner;
    final data = await patientInformationalPost(
      'assistance',
      message,
      generation,
    );
    if (!isCurrentSession(generation) ||
        owner == null ||
        observationOwner != owner) {
      throw ApiException('Session changed. Reopen assistance.');
    }
    return AssistanceResponse.fromApi(data, owner: owner);
  }

  Future<Map<String, dynamic>> patientInformationalPost(
    String route,
    String message,
    int generation,
  ) async {
    void guard() {
      if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
        throw ApiException('Session changed. Reopen assistance after sign-in.');
      }
    }

    guard();
    if (!['assistance', 'chat'].contains(route) ||
        message.trim().isEmpty ||
        message.trim().runes.length > 1000) {
      throw ArgumentError('Invalid assistance request');
    }
    final request = http.Request('POST', Uri.parse('$baseUrl/$route'));
    request.followRedirects = false;
    request.headers.addAll(_headers());
    request.body = jsonEncode({'message': message.trim()});
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 60));
    guard();
    if (response.statusCode != 200) {
      throw AssistanceReadException(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestAssistance(String message) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/assistance'),
          headers: _headers(),
          body: jsonEncode({'message': message}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw ApiException(
        'Assistance unavailable (status ${response.statusCode})',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['schema_version'] != 'contextual-ai-1.0' ||
        data['message'] is! String ||
        data['metadata'] is! Map) {
      throw ApiException('Invalid assistance response');
    }
    return data;
  }

  Future<Map<String, dynamic>> sendChatMessage(String message) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/chat'),
      headers: _headers(),
      body: jsonEncode({'message': message}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    throw ApiException(data['message']?.toString() ?? 'Chat failed', data);
  }

  Future<dynamic> experimentRequest(
    String resource, {
    String method = 'GET',
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/experiments${resource.isEmpty ? '' : '/$resource'}',
    );
    final response =
        await (method == 'GET'
                ? _client.get(uri, headers: _headers(false))
                : _client.post(
                    uri,
                    headers: _headers(),
                    body: jsonEncode(payload),
                  ))
            .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Experiment request failed (status ${response.statusCode})',
      );
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> routineRequest(
    String resource, {
    String method = 'GET',
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse('$baseUrl/routine/$resource');
    final response =
        await (method == 'GET'
                ? _client.get(uri, headers: _headers(false))
                : method == 'PATCH'
                ? _client.patch(
                    uri,
                    headers: _headers(),
                    body: jsonEncode(payload),
                  )
                : _client.post(
                    uri,
                    headers: _headers(),
                    body: jsonEncode(payload),
                  ))
            .timeout(const Duration(seconds: 20));
    if (response.statusCode != (method == 'POST' ? 201 : 200)) {
      throw ApiException(
        'Routine request failed (status ${response.statusCode})',
      );
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getProductIntelligence(String id) async {
    final token = authToken;
    final responses = await Future.wait([
      _client.get(
        Uri.parse('$baseUrl/products/${Uri.encodeComponent(id)}/intelligence'),
        headers: _headers(false),
      ),
      _client.get(
        Uri.parse('$baseUrl/routine/intelligence'),
        headers: _headers(false),
      ),
    ]).timeout(const Duration(seconds: 20));
    if (token != authToken || responses.any((r) => r.statusCode != 200)) {
      throw ApiException(
        'Product intelligence unavailable. Refresh and retry.',
      );
    }
    final product = jsonDecode(responses[0].body) as Map<String, dynamic>;
    final routine = jsonDecode(responses[1].body) as Map<String, dynamic>;
    if (product['product_id'] != id ||
        product['ingredients'] is! List ||
        product['facts'] is! Map ||
        routine['warnings'] is! List ||
        product['warnings'] is! List) {
      throw ApiException('Invalid product intelligence response');
    }
    product['routine_warnings'] = (routine['warnings'] as List)
        .where((w) => (w['evidence'] as List).any((e) => e['product_id'] == id))
        .toList();
    return product;
  }

  Future<Object?> patientResource(
    String path,
    int generation, {
    String method = 'GET',
    Map<String, dynamic>? payload,
    int? expectedRevision,
    int? expectedRoutineRevision,
    String? idempotencyKey,
  }) async {
    void guard() {
      if (!isCurrentSession(generation) || !canReadPatientClinicalStatus) {
        throw ApiException('Session changed. Reopen this workflow.');
      }
    }

    guard();
    if (!RegExp(
              r'^(products|routine/(entries|adherence)|experiments)(/[A-Za-z0-9_-]+){0,2}(\?[A-Za-z0-9_=&-]+)?$',
            ).hasMatch(path) &&
            !(method == 'GET' &&
                RegExp(
                  r'^products/[A-Za-z0-9_-]+/operation-attempts/(patch|delete)/[A-Za-z0-9_-]{16,128}$',
                ).hasMatch(path)) &&
            !(method == 'GET' &&
                RegExp(
                  r'^(routine/configuration-attempts/(create|update|stop)|experiments/operation-attempts/(create|edit|activate|finish|cancel|evaluate|legacy_pause))/[A-Za-z0-9_-]{16,128}(\?resource_id=[A-Za-z0-9_-]+)?$',
                ).hasMatch(path)) ||
        !['GET', 'POST', 'PATCH', 'DELETE'].contains(method)) {
      throw ArgumentError('Invalid patient resource');
    }
    if (expectedRevision != null &&
        (!(RegExp(r'^products/[A-Za-z0-9_-]+$').hasMatch(path) &&
                    ['PATCH', 'DELETE'].contains(method) ||
                RegExp(r'^routine/entries/[A-Za-z0-9_-]+$').hasMatch(path) &&
                    method == 'PATCH' ||
                RegExp(r'^experiments/[A-Za-z0-9_-]+$').hasMatch(path) &&
                    ['PATCH', 'DELETE'].contains(method) ||
                RegExp(
                      r'^experiments/[A-Za-z0-9_-]+/(activate|finish|evaluate)$',
                    ).hasMatch(path) &&
                    method == 'POST' ||
                RegExp(
                      r'^experiments/[A-Za-z0-9_-]+/toggle-pause$',
                    ).hasMatch(path) &&
                    method == 'PATCH') ||
            expectedRevision < 1 ||
            expectedRevision > 2147483647)) {
      throw ArgumentError('Invalid configuration revision precondition');
    }
    if (expectedRoutineRevision != null &&
        (!RegExp(r'^experiments/[A-Za-z0-9_-]+/activate$').hasMatch(path) ||
            method != 'POST' ||
            expectedRoutineRevision < 1 ||
            expectedRoutineRevision > 2147483647)) {
      throw ArgumentError('Invalid linked routine precondition');
    }
    if (idempotencyKey != null &&
        (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(idempotencyKey) ||
            !(path == 'products' && method == 'POST' ||
                RegExp(r'^products/[A-Za-z0-9_-]+$').hasMatch(path) &&
                    ['PATCH', 'DELETE'].contains(method) ||
                ['routine/entries', 'routine/adherence'].contains(path) &&
                    method == 'POST' ||
                RegExp(r'^routine/entries/[A-Za-z0-9_-]+$').hasMatch(path) &&
                    ['PATCH', 'DELETE'].contains(method) ||
                path == 'experiments' && method == 'POST' ||
                RegExp(r'^experiments/[A-Za-z0-9_-]+$').hasMatch(path) &&
                    ['PATCH', 'DELETE'].contains(method) ||
                RegExp(
                      r'^experiments/[A-Za-z0-9_-]+/(activate|finish|evaluate)$',
                    ).hasMatch(path) &&
                    method == 'POST'))) {
      throw ArgumentError('Invalid foundation operation identity');
    }
    final request = http.Request(method, Uri.parse('$baseUrl/$path'));
    request.followRedirects = false;
    request.headers.addAll(_headers(payload != null));
    if (expectedRevision != null) {
      request.headers['If-Match'] = '"$expectedRevision"';
    }
    if (expectedRoutineRevision != null) {
      request.headers['Routine-If-Match'] = '"$expectedRoutineRevision"';
    }
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    if (payload != null) request.body = jsonEncode(payload);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    guard();
    if (response.statusCode == 404 && method == 'GET') {
      throw PatientResourceMissing();
    }
    if (![200, 201, 204].contains(response.statusCode)) {
      if (idempotencyKey != null) throw IntegrationFailure(response.statusCode);
      throw RequestFailure.http(response.statusCode);
    }
    return response.statusCode == 204 ? null : jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> getProducts({
    String? category,
    bool? inRoutine,
    bool? inExperiment,
  }) async {
    final qp = <String, String>{};
    if (category != null) qp['category'] = category;
    if (inRoutine != null) qp['in_routine'] = inRoutine.toString();
    if (inExperiment != null) qp['in_experiment'] = inExperiment.toString();
    final uri = Uri.parse(
      '$baseUrl/products',
    ).replace(queryParameters: qp.isNotEmpty ? qp : null);
    final res = await _client.get(uri, headers: _headers(false));
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    throw ApiException('Could not load products (status ${res.statusCode})');
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> product,
  ) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/products'),
      headers: _headers(),
      body: jsonEncode(product),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Failed to add product',
      data,
    );
  }

  Future<Map<String, dynamic>> updateProduct(
    String id,
    Map<String, dynamic> product,
  ) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/products/$id'),
      headers: _headers(),
      body: jsonEncode(product),
    );
    if (res.statusCode != 200) {
      throw ApiException('Could not update product (status ${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteProduct(String id) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/products/$id'),
      headers: _headers(false),
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(
        data['message']?.toString() ?? 'Failed to delete product',
        data,
      );
    }
  }

  Future<Map<String, dynamic>> checkInteractions(
    List<String> ingredients,
  ) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/products/check-interactions'),
      headers: _headers(),
      body: jsonEncode({'ingredients': ingredients}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> getCurrentExperiment() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/experiments/current'),
      headers: _headers(false),
    );
    if (res.statusCode == 200 && res.body.isNotEmpty && res.body != 'null') {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<Map<String, dynamic>> togglePauseExperiment(
    String experimentId,
  ) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/experiments/$experimentId/toggle-pause'),
      headers: _headers(),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getBaseline() async {
    final generation = sessionGeneration;
    final res = await _client
        .get(Uri.parse('$baseUrl/baseline'), headers: _headers(false))
        .timeout(const Duration(seconds: 20));
    if (generation != sessionGeneration) throw ApiException('Session changed.');
    if (res.statusCode != 200) {
      throw ApiException('Could not load baseline (status ${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDailyContext(String day) async {
    final res = await _client
        .get(Uri.parse('$baseUrl/context/$day'), headers: _headers(false))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Context unavailable');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveDailyContext(
    String day,
    bool? unusual,
    int? cycleDay,
  ) async {
    final res = await _client
        .put(
          Uri.parse('$baseUrl/context/$day'),
          headers: _headers(),
          body: jsonEncode({
            'unusual_conditions': unusual,
            'cycle_day': cycleDay,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Context save unconfirmed');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getHome() async {
    final generation = sessionGeneration;
    final res = await _client
        .get(Uri.parse('$baseUrl/home'), headers: _headers(false))
        .timeout(const Duration(seconds: 15));
    if (generation != sessionGeneration) throw ApiException('Session changed.');
    if (res.statusCode != 200) throw RequestFailure.http(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getCheckIns() async {
    final res = await _client
        .get(Uri.parse('$baseUrl/checkins'), headers: _headers(false))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Skin history unavailable');
    final list = jsonDecode(res.body) as List<dynamic>;
    final rows = list.cast<Map<String, dynamic>>();
    for (final row in rows) {
      _validateCheckIn(row);
    }
    return rows;
  }

  void _validateCheckIn(Map<String, dynamic> data) {
    if (data['id'] is! String ||
        (data['id'] as String).isEmpty ||
        data['created_at'] is! String ||
        DateTime.tryParse(data['created_at'] as String) == null) {
      throw ApiException(
        'Invalid check-in confirmation. Refresh before retrying',
      );
    }
    final report = data['observation'] is Map
        ? data['observation']['user_reported']
        : null;
    if (data['observation'] != null &&
        (data['observation'] is! Map ||
            data['observation']['schema_version'] != 1 ||
            data['observation']['provenance'] is! Map ||
            data['observation']['daily_context_date'] is! String)) {
      throw ApiException('Invalid observation evidence');
    }
    if (report != null &&
        (report is! Map ||
            !['better', 'same', 'worse'].contains(report['overall_change']) ||
            report['symptoms'] is! List)) {
      throw ApiException('Invalid structured report');
    }
    final analysis = data['ai_vision_analysis'];
    final source = analysis is Map ? analysis['measurement_source'] : null;
    if (source == 'none' && report != null) {
      if ([
        'hydration_score',
        'texture_score',
        'redness_score',
      ].any((key) => data[key] != null)) {
        throw ApiException('Unexpected check-in measurements');
      }
      return;
    }
    if (!['manual', 'image_proxy'].contains(source)) {
      throw ApiException('Unknown measurement source');
    }
    for (final key in ['hydration_score', 'texture_score', 'redness_score']) {
      final value = data[key];
      if (value is! num || !value.isFinite || value < 0 || value > 100) {
        throw ApiException('Invalid check-in measurements');
      }
    }
  }

  Future<Map<String, dynamic>> submitCheckIn({
    required String timeOfDay,
    double? hydration,
    double? texture,
    double? redness,
    String? notes,
    String? experimentId,
    List<int>? photoBytes,
    String? photoFilename,
    Map<String, dynamic>? report,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/checkins'),
    );
    request.headers.addAll(_headers(false));
    request.fields['time_of_day'] = timeOfDay;
    if (report != null) request.fields['report'] = jsonEncode(report);
    if (hydration != null) {
      request.fields['hydration_score'] = hydration.toString();
    }
    if (texture != null) request.fields['texture_score'] = texture.toString();
    if (redness != null) request.fields['redness_score'] = redness.toString();
    if (notes != null) request.fields['notes'] = notes;
    if (experimentId != null) request.fields['experiment_id'] = experimentId;

    if (photoBytes != null && photoBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: photoFilename ?? 'skin_photo.jpg',
        ),
      );
    }

    final streamedRes = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamedRes);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201) {
      _validateCheckIn(data);
      if (report != null) {
        final confirmed = data['observation']?['user_reported'];
        final symptoms = (report['symptoms'] as List? ?? []).toSet().toList();
        if (confirmed is! Map ||
            confirmed['overall_change'] != report['overall_change'] ||
            confirmed['routine_status'] != report['routine_status'] ||
            !listEquals(confirmed['symptoms'] as List?, symptoms)) {
          throw ApiException('Structured report was not confirmed');
        }
      }
      return data;
    }
    throw ApiException(data['message']?.toString() ?? 'Check-in failed', data);
  }

  Future<Map<String, dynamic>> generateDoctorQr({int minutes = 60}) async {
    throw ApiException(
      'New clinician connections are unavailable until viewing and export permissions can be confirmed separately.',
    );
  }

  Future<bool> claimDoctorAccess(String token) async {
    throw ApiException(
      'New clinician connections are unavailable until consent scopes can be verified.',
    );
  }

  bool get canManageDoctorGrants =>
      canReadPatientClinicalStatus &&
      _consentUser?['role'] == 'patient' &&
      _consentUser?['id'] == _sessionUserId;
  final Set<String> uncertainGrantRevocations = {};
  Future<Object?> patientGrantResource(
    int generation, {
    String? revokeId,
  }) async {
    void guard() {
      if (!isCurrentSession(generation) || !canManageDoctorGrants) {
        throw ApiException(
          'Patient session changed. Sign in and verify access again.',
        );
      }
    }

    guard();
    if (revokeId != null && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(revokeId)) {
      throw ArgumentError('Invalid grant identity');
    }
    final request = http.Request(
      revokeId == null ? 'GET' : 'DELETE',
      Uri.parse(
        '$baseUrl/doctor/access${revokeId == null ? '' : '/$revokeId'}',
      ),
    )..followRedirects = false;
    request.headers.addAll(_headers(false));
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    guard();
    if (response.statusCode != 200) {
      throw RequestFailure.http(response.statusCode);
    }
    return jsonDecode(response.body);
  }

  Future<bool> revokeDoctorAccess(String patientId) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/doctor/revoke/$patientId'),
      headers: _headers(false),
    );
    return res.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> getDoctorPatients() async =>
      (await doctorResource('patients', sessionGeneration) as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> addClinicalNote({
    required String patientId,
    required String content,
    String priority = 'routine',
    String? followUp,
  }) async {
    final data =
        await doctorResource(
              'patients/$patientId/notes',
              sessionGeneration,
              method: 'POST',
              payload: {
                'content': content,
                'priority': priority,
                'follow_up': followUp,
              },
            )
            as Map<String, dynamic>;
    if (data['id'] is! String ||
        (data['id'] as String).isEmpty ||
        data['patient_id'] != patientId ||
        data['content'] is! String ||
        data['created_at'] is! String ||
        DateTime.tryParse(data['created_at'] as String) == null) {
      throw ApiException('Invalid clinical note confirmation');
    }
    return data;
  }
}

class _PrivateImageRequest extends http.Request {
  _PrivateImageRequest(Uri uri) : super('GET', uri) {
    followRedirects = false;
  }
}

class _DoctorImageRequest extends _PrivateImageRequest {
  _DoctorImageRequest(super.uri, this.scope, this.active);
  final Listenable scope;
  final bool Function() active;
}

class _SessionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sentToken = request.headers['Authorization'];
    final generation = ApiService.instance.sessionGeneration;
    final api = ApiService.instance;
    Future<void> validate(int status) async {
      final logout = request.url.path.endsWith('/auth/logout');
      if (sentToken != null &&
          (!api.isCurrentSession(generation) ||
              sentToken != 'Bearer ${api.authToken}') &&
          !logout) {
        throw ApiException('Session changed. Please try again');
      }
      // Logout is intentionally sent after local invalidation. Its response must
      // never invalidate a new session, even when the provider reuses a token.
      if (status == 401 &&
          !logout &&
          sentToken != null &&
          api.isCurrentSession(generation) &&
          sentToken == 'Bearer ${api.authToken}') {
        await api._clearSession(preserveOperationIdentity: true);
        throw RequestFailure.session();
      }
    }

    api._guardQuarantinedMutation(request);
    final client = http.Client();
    http.StreamedResponse response;
    try {
      if (request is _PrivateImageRequest) {
        final api = ApiService.instance;
        bool allowed() =>
            api.isCurrentSession(generation) &&
            (request is _DoctorImageRequest
                ? api.canReadDoctorWorkspace && request.active()
                : api.canReadPatientClinicalStatus);
        void sessionChanged() {
          if (!allowed()) {
            client.close();
          }
        }

        api.addListener(sessionChanged);
        if (request is _DoctorImageRequest) {
          request.scope.addListener(sessionChanged);
        }
        try {
          response = await (() async {
            final streamed = await client.send(request);
            await validate(streamed.statusCode);
            if (!allowed()) {
              throw ApiException('Session changed. Please try again');
            }
            // Errors need no body. In particular, a current 401 must invalidate
            // the session even if an error body stalls or exceeds the byte cap.
            if (streamed.statusCode != 200) {
              return http.StreamedResponse(
                const Stream.empty(),
                streamed.statusCode,
                headers: streamed.headers,
                request: request,
              );
            }
            if ((streamed.contentLength ?? 0) > maxPrivateImageBytes) {
              throw const FormatException(
                'Private image exceeds the memory limit',
              );
            }
            final builder = BytesBuilder(copy: false);
            await for (final chunk in streamed.stream) {
              if (!allowed()) {
                throw ApiException('Session changed. Please try again');
              }
              if (builder.length + chunk.length > maxPrivateImageBytes) {
                throw const FormatException(
                  'Private image exceeds the memory limit',
                );
              }
              builder.add(chunk);
            }
            return http.StreamedResponse(
              Stream.value(builder.takeBytes()),
              200,
              headers: streamed.headers,
              request: request,
            );
          })().timeout(const Duration(seconds: 20));
        } finally {
          api.removeListener(sessionChanged);
          if (request is _DoctorImageRequest) {
            request.scope.removeListener(sessionChanged);
          }
        }
      } else {
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 60));
        await validate(streamed.statusCode);
        final bytes = await streamed.stream.toBytes().timeout(
          const Duration(seconds: 60),
        );
        response = http.StreamedResponse(
          Stream.value(bytes),
          streamed.statusCode,
          headers: streamed.headers,
          request: request,
          reasonPhrase: streamed.reasonPhrase,
        );
      }
    } finally {
      client.close();
    }
    await validate(response.statusCode);
    return response;
  }
}

class PatientResourceMissing implements Exception {}

class ProfileRequestException extends ApiException {
  ProfileRequestException(super.message, {this.unauthorized = false});
  final bool unauthorized;
}

class ClinicalRequestException extends ApiException {
  ClinicalRequestException(super.message, {this.status});
  final int? status;
}
