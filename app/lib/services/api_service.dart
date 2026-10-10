import 'dart:convert';
import 'dart:async';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService extends ChangeNotifier {
  ApiService._();
  static final ApiService instance = ApiService._();

  Future<Map<String, dynamic>> submitCapture(Uint8List bytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/captures'));
    request.headers.addAll(_headers(false));
    request.fields.addAll({'source': 'upload', 'view': 'front'});
    final isPng = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71;
    request.files.add(http.MultipartFile.fromBytes('photo', bytes,
        filename: isPng ? 'capture.png' : 'capture.jpg', contentType: MediaType.parse(isPng ? 'image/png' : 'image/jpeg')));
    final response = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 60));
    if (response.statusCode != 201) throw ApiException('Capture quality checking failed');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getCaptureHistory() async {
    final response = await _client.get(Uri.parse('$baseUrl/captures'), headers: _headers()).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw ApiException('Capture history unavailable');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
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

  int get sessionGeneration => _sessionGeneration;
  bool isCurrentSession(int generation) =>
      generation == _sessionGeneration && isAuthenticated;
  bool get hasConfirmedSafetyAcceptance =>
      isCurrentSession(_consentGeneration ?? -1) &&
      _confirmedSafetyAcceptance == true;

  // Invalidate earlier auth attempts before sending another request. Logout
  // increments the same generation even when no token has arrived yet.
  Future<int> _beginAuthentication() async {
    final cleanup = _clearSession();
    final generation = _sessionGeneration;
    await cleanup;
    if (generation != _sessionGeneration) {
      throw ApiException('Session changed. Please sign in again');
    }
    return generation;
  }

  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _authToken != null &&
      _expiresAt != null && DateTime.now().isBefore(_expiresAt!);

  Future<void> init() async {
    // Sessions are memory-only. Never restore legacy plaintext credentials.
    await _clearSession();
  }

  Map<String, String> _headers([bool isJson = true]) {
    final headers = <String, String>{};
    if (isJson) headers['Content-Type'] = 'application/json';
    if (_authToken != null && !isAuthenticated) {
      unawaited(_clearSession());
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
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        'accept_safety': acceptSafety,
      }),
    ).timeout(const Duration(seconds: 20));
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
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ).timeout(const Duration(seconds: 20));
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
        throw ApiException('This account is not authorized for the clinician workspace');
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
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    ).timeout(const Duration(seconds: 20));
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
    _sessionUserId = data['user_id'] is String ? data['user_id'] as String : null;
    _currentUser = Map.of(data)..remove('access_token');
    _expiresAt = DateTime.now().add(Duration(seconds: ttl));
    _expiryTimer = Timer(Duration(seconds: ttl), () => unawaited(_clearSession()));
  }

  Future<void> _clearSession() async {
    final hadSession = _authToken != null;
    _sessionGeneration++;
    _sessionUserId = null;
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
        _tokenKey, _userKey, 'dermaire_products_v2', 'dermaire_safety_accepted',
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
      await _client.post(Uri.parse('$baseUrl/auth/logout'), headers: headers)
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
    _consentGeneration = generation;
    _confirmedSafetyAcceptance = decoded['safety_accepted'] as bool;
    return _confirmedSafetyAcceptance!;
  }

  /// Acknowledges the write only. Call readSafetyAcceptance before entry.
  Future<void> acceptSafetyTerms() async {
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
          // Use the existing server default; policy currency is not exposed.
          body: jsonEncode({'accepted': true}),
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
  }) async {
    final bodyMap = <String, dynamic>{...?fields};
    if (skinType != null) bodyMap['skin_type'] = skinType;
    if (selectedGoal != null) bodyMap['selected_goal'] = selectedGoal;
    if (skinConcerns != null) bodyMap['skin_concerns'] = skinConcerns;

    final res = await _client.patch(
      Uri.parse('$baseUrl/users/skin-profile'),
      headers: _headers(),
      body: jsonEncode(bodyMap),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 &&
        data['skin_concerns'] is List &&
        (data['skin_concerns'] as List).every((v) => v is String) &&
        data.containsKey('profile_context') &&
        (data['profile_context'] == null || data['profile_context'] is Map)) {
      _currentUser = data;
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Failed to update skin profile',
      data,
    );
  }

  Future<Map<String, dynamic>> requestAssistance(String message) async {
    final response = await _client.post(Uri.parse('$baseUrl/assistance'),
        headers: _headers(), body: jsonEncode({'message': message}))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw ApiException('Assistance unavailable (status ${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['schema_version'] != 'contextual-ai-1.0' ||
        data['message'] is! String || data['metadata'] is! Map) {
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

  Future<dynamic> routineRequest(String resource, {String method = 'GET', Map<String, dynamic>? payload}) async {
    final uri = Uri.parse('$baseUrl/routine/$resource');
    final response = await (method == 'GET' ? _client.get(uri, headers: _headers(false)) :
      method == 'PATCH' ? _client.patch(uri, headers: _headers(), body: jsonEncode(payload)) :
      _client.post(uri, headers: _headers(), body: jsonEncode(payload))).timeout(const Duration(seconds: 20));
    if (response.statusCode != (method == 'POST' ? 201 : 200)) {
      throw ApiException('Routine request failed (status ${response.statusCode})');
    }
    return jsonDecode(response.body);
  }
  Future<Map<String, dynamic>> getProductIntelligence(String id) async {
    final token = authToken;
    final responses = await Future.wait([
      _client.get(Uri.parse('$baseUrl/products/${Uri.encodeComponent(id)}/intelligence'), headers: _headers(false)),
      _client.get(Uri.parse('$baseUrl/routine/intelligence'), headers: _headers(false)),
    ]).timeout(const Duration(seconds: 20));
    if (token != authToken || responses.any((r) => r.statusCode != 200)) {
      throw ApiException('Product intelligence unavailable. Refresh and retry.');
    }
    final product = jsonDecode(responses[0].body) as Map<String, dynamic>;
    final routine = jsonDecode(responses[1].body) as Map<String, dynamic>;
    if (product['product_id'] != id || product['ingredients'] is! List ||
        product['facts'] is! Map || routine['warnings'] is! List || product['warnings'] is! List) {
      throw ApiException('Invalid product intelligence response');
    }
    product['routine_warnings'] = (routine['warnings'] as List).where((w) =>
      (w['evidence'] as List).any((e) => e['product_id'] == id)).toList();
    return product;
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

  Future<Map<String, dynamic>> updateProduct(String id, Map<String, dynamic> product) async {
    final res = await _client.patch(Uri.parse('$baseUrl/products/$id'),
        headers: _headers(), body: jsonEncode(product));
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
    final res = await _client.get(Uri.parse('$baseUrl/baseline'),
        headers: _headers(false)).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw ApiException('Could not load baseline (status ${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDailyContext(String day) async {
    final res = await _client.get(Uri.parse('$baseUrl/context/$day'),
        headers: _headers(false)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Context unavailable');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveDailyContext(String day, bool? unusual, int? cycleDay) async {
    final res = await _client.put(Uri.parse('$baseUrl/context/$day'), headers: _headers(),
        body: jsonEncode({'unusual_conditions': unusual, 'cycle_day': cycleDay}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Context save unconfirmed');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getHome() async {
    final res = await _client.get(Uri.parse('$baseUrl/home'), headers: _headers(false))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Home unavailable');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getCheckIns() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/checkins'),
      headers: _headers(false),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw ApiException('Skin history unavailable');
    final list = jsonDecode(res.body) as List<dynamic>;
    final rows = list.cast<Map<String, dynamic>>();
    for (final row in rows) {
      _validateCheckIn(row);
    }
    return rows;
  }

  void _validateCheckIn(Map<String, dynamic> data) {
    if (data['id'] is! String || (data['id'] as String).isEmpty ||
        data['created_at'] is! String || DateTime.tryParse(data['created_at'] as String) == null) {
      throw ApiException('Invalid check-in confirmation. Refresh before retrying');
    }
    final report = data['observation'] is Map ? data['observation']['user_reported'] : null;
    if (data['observation'] != null && (data['observation'] is! Map ||
        data['observation']['schema_version'] != 1 || data['observation']['provenance'] is! Map ||
        data['observation']['daily_context_date'] is! String)) {
      throw ApiException('Invalid observation evidence');
    }
    if (report != null && (report is! Map ||
        !['better', 'same', 'worse'].contains(report['overall_change']) || report['symptoms'] is! List)) {
      throw ApiException('Invalid structured report');
    }
    final analysis = data['ai_vision_analysis'];
    final source = analysis is Map ? analysis['measurement_source'] : null;
    if (source == 'none' && report != null) {
      if (['hydration_score', 'texture_score', 'redness_score'].any((key) => data[key] != null)) {
        throw ApiException('Unexpected check-in measurements');
      }
      return;
    }
    if (!['manual', 'image_proxy'].contains(source)) throw ApiException('Unknown measurement source');
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
    if (hydration != null) request.fields['hydration_score'] = hydration.toString();
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

    final streamedRes = await _client.send(request).timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamedRes);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201) {
      _validateCheckIn(data);
      if (report != null) {
        final confirmed = data['observation']?['user_reported'];
        final symptoms = (report['symptoms'] as List? ?? []).toSet().toList();
        if (confirmed is! Map || confirmed['overall_change'] != report['overall_change'] ||
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
    final res = await _client.post(
      Uri.parse('$baseUrl/doctor/generate-qr?minutes_valid=$minutes'),
      headers: _headers(),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<bool> claimDoctorAccess(String token) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/doctor/claim'),
      headers: _headers(),
      body: jsonEncode({'access_token': token}),
    );
    return res.statusCode == 200;
  }

  Future<bool> revokeDoctorAccess(String patientId) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/doctor/revoke/$patientId'),
      headers: _headers(false),
    );
    return res.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> getDoctorPatients() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/doctor/patients'),
      headers: _headers(false),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    throw ApiException('Could not load authorized patients');
  }

  Future<Map<String, dynamic>> addClinicalNote({
    required String patientId,
    required String content,
    String priority = 'routine',
    String? followUp,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/doctor/patients/$patientId/notes'),
      headers: _headers(),
      body: jsonEncode({
        'content': content,
        'priority': priority,
        'follow_up': followUp,
      }),
    );
    if (res.statusCode != 201) {
      throw ApiException('Clinical note could not be saved');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['id'] is! String || (data['id'] as String).isEmpty ||
        data['patient_id'] != patientId || data['content'] is! String ||
        data['created_at'] is! String || DateTime.tryParse(data['created_at'] as String) == null) {
      throw ApiException('Invalid clinical note confirmation');
    }
    return data;
  }
}

class _SessionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sentToken = request.headers['Authorization'];
    final generation = ApiService.instance.sessionGeneration;
    final client = http.Client();
    http.StreamedResponse response;
    try {
      final streamed = await client.send(request).timeout(const Duration(seconds: 60));
      final bytes = await streamed.stream.toBytes().timeout(const Duration(seconds: 60));
      response = http.StreamedResponse(Stream.value(bytes), streamed.statusCode,
          headers: streamed.headers, request: request, reasonPhrase: streamed.reasonPhrase);
    } finally {
      client.close();
    }
    final api = ApiService.instance;
    if (sentToken != null &&
        (!api.isCurrentSession(generation) || sentToken != 'Bearer ${api.authToken}') &&
        !request.url.path.endsWith('/auth/logout')) {
      throw ApiException('Session changed. Please try again');
    }
    if (response.statusCode == 401 && sentToken != null &&
        sentToken == 'Bearer ${api.authToken}') {
      await api._clearSession();
      throw ApiException('Session expired or invalid. Please sign in again');
    }
    return response;
  }
}

class ApiException implements Exception {
  ApiException(this.message, [this.details]);
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}
