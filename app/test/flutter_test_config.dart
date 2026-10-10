import 'dart:async';

import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit/widget tests use synthetic contracts only, never the production origin.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiService.instance.baseUrl = 'https://flutter-tests.invalid/api/v1';
  // Initialize this even in service-only suites. The Flutter test binding
  // replaces real HTTP with status 400; explicit MockClients still work.
  TestWidgetsFlutterBinding.ensureInitialized();
  await testMain();
}
