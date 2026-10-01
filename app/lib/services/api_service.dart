import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService extends ChangeNotifier {
  ApiService._();
  static final ApiService instance = ApiService._();

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
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        'accept_safety': acceptSafety,
      }),
    );
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _persistAuth(data);
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
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
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
      await _persistAuth(data);
      return data;
    }
    throw ApiException(data['message']?.toString() ?? 'Login failed', data);
  }

  /// Verifies a real Google ID token (from google_sign_in) with our backend
  /// and signs the user in, creating an account automatically on first use.
  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    if (res.body.isEmpty) {
      throw ApiException(
        'Empty response from server (status ${res.statusCode})',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _persistAuth(data);
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

  Future<void> _persistAuth(Map<String, dynamic> data) async {
    final token = data['access_token'];
    final ttl = data['expires_in'];
    if (token is! String || token.trim().isEmpty || ttl is! int || ttl <= 0) {
      throw ApiException('Invalid authentication response from server');
    }
    await _clearSession();
    _authToken = token;
    _currentUser = Map.of(data)..remove('access_token');
    _expiresAt = DateTime.now().add(Duration(seconds: ttl));
    _expiryTimer = Timer(Duration(seconds: ttl), () => unawaited(_clearSession()));
  }

  Future<void> _clearSession() async {
    final hadSession = _authToken != null;
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
  }) async {
    final bodyMap = <String, dynamic>{};
    if (skinType != null) bodyMap['skin_type'] = skinType;
    if (selectedGoal != null) bodyMap['selected_goal'] = selectedGoal;
    if (skinConcerns != null) bodyMap['skin_concerns'] = skinConcerns;

    final res = await _client.patch(
      Uri.parse('$baseUrl/users/skin-profile'),
      headers: _headers(),
      body: jsonEncode(bodyMap),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      _currentUser = data;
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Failed to update skin profile',
      data,
    );
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

  Future<List<Map<String, dynamic>>> getCheckIns() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/checkins'),
      headers: _headers(false),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    return [];
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
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/checkins'),
    );
    request.headers.addAll(_headers(false));
    request.fields['time_of_day'] = timeOfDay;
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
      final analysis = data['ai_vision_analysis'];
      if (data['id'] is! String || (data['id'] as String).isEmpty ||
          data['created_at'] is! String || DateTime.tryParse(data['created_at'] as String) == null ||
          analysis is! Map || !['manual', 'image_proxy'].contains(analysis['measurement_source'])) {
        throw ApiException('Invalid check-in confirmation. Refresh before retrying');
      }
      for (final key in ['hydration_score', 'texture_score', 'redness_score']) {
        final value = data[key];
        if (value is! num || !value.isFinite || value < 0 || value > 100) {
          throw ApiException('Invalid check-in measurements');
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

  Future<Map<String, dynamic>> redeemReward(String rewardId) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/rewards/redeem'),
      headers: _headers(),
      body: jsonEncode({'reward_id': rewardId}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    throw ApiException(
      data['message']?.toString() ?? 'Redemption failed',
      data,
    );
  }
}

class _SessionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sentToken = request.headers['Authorization'];
    final client = http.Client();
    http.StreamedResponse response;
    try {
      final streamed = await client.send(request);
      final bytes = await streamed.stream.toBytes();
      response = http.StreamedResponse(Stream.value(bytes), streamed.statusCode,
          headers: streamed.headers, request: request, reasonPhrase: streamed.reasonPhrase);
    } finally {
      client.close();
    }
    final api = ApiService.instance;
    if (sentToken != null && sentToken != 'Bearer ${api.authToken}' &&
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
