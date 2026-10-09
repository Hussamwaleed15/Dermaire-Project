import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'tester/tester_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.init();
  ApiService.instance.baseUrl = TesterEnvironment.baseUrl;
  runApp(const TesterApp());
}
