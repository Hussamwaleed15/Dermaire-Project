import 'package:flutter/material.dart';

import 'dermaire_state.dart';
import 'dermaire_theme.dart';
import 'onboarding_screens.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DermaireApp());
}

class DermaireApp extends StatefulWidget {
  const DermaireApp({super.key});

  @override
  State<DermaireApp> createState() => _DermaireAppState();
}

class _DermaireAppState extends State<DermaireApp> {
  final navigatorKey = GlobalKey<NavigatorState>();

  void _sessionEnded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ApiService.instance.isAuthenticated) return;
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => WelcomeScreen(state: state)),
        (_) => false,
      );
    });
  }

  late final DermaireState state = DermaireState();

  @override
  void initState() {
    super.initState();
    ApiService.instance.addListener(_sessionEnded);
    state.loadPreferences();
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(_sessionEnded);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Dermaire',
      debugShowCheckedModeBanner: false,
      theme: DermaireTheme.light,
      darkTheme: DermaireTheme.dark,
      themeMode: state.themeMode,
      home: WelcomeScreen(state: state),
    ),
  );
}

class MyApp extends DermaireApp {
  const MyApp({super.key});
}
