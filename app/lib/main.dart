import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
      if (!mounted) return;
      // A fast account switch can authenticate before this frame. Discard all
      // routes from the old session and verify the current one from the server.
      navigatorKey.currentState?.pushAndRemoveUntil(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => ApiService.instance.isAuthenticated
              ? PatientEntryGate(state: state)
              : WelcomeScreen(state: state),
        ),
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
      themeAnimationDuration: Duration.zero,
      locale: state.locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: WelcomeScreen(state: state),
    ),
  );
}

class MyApp extends DermaireApp {
  const MyApp({super.key});
}
