import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'baseline/baseline_controller.dart';
import 'experiments/experiment_controller.dart';
import 'context_controller.dart';
import 'home_controller.dart';
import 'products/product_repository.dart';
import 'products/products_controller.dart';
import 'services/api_service.dart';

class JournalEntry {
  const JournalEntry(this.date, this.time, this.summary);
  final String date;
  final String time;
  final String summary;
}

class DermaireState extends ChangeNotifier {
  DermaireState({
    ProductRepository? productRepository,
    BaselineRepository? baselineRepository,
    ContextRepository? contextRepository,
    HomeRepository? homeRepository,
    ExperimentRepository? experimentRepository,
  }) {
    experiments = ExperimentController(
      experimentRepository ?? RemoteExperimentRepository(),
    )..addListener(notifyListeners);
    home = HomeController(homeRepository ?? RemoteHomeRepository())
      ..addListener(notifyListeners);
    dailyContext = ContextController(
      contextRepository ?? RemoteContextRepository(),
    )..addListener(notifyListeners);
    baseline = BaselineController(
      baselineRepository ?? RemoteBaselineRepository(),
    )..addListener(notifyListeners);
    ApiService.instance.addListener(clearAccountData);
    productController = ProductsController(
      productRepository ?? RemoteProductRepository(),
    )..addListener(notifyListeners);
  }

  late final ProductsController productController;
  late final BaselineController baseline;
  late final ContextController dailyContext;
  late final HomeController home;
  late final ExperimentController experiments;
  static const _darkModeKey = 'dermaire_dark_mode';
  static const _safetyAcceptedKey = 'dermaire_safety_accepted';

  ThemeMode themeMode = ThemeMode.light;
  bool safetyAccepted = false;
  int selectedTab = 0;
  int? get baselineCheckIns => baseline.completedDays;
  int experimentDay = 1;
  bool experimentPaused = false;
  bool get todayCheckedIn => baseline.todayCheckedIn;
  bool doctorLinkActive = false;
  String selectedGoal = '';
  final Set<String> skinConcerns = <String>{};
  String userName = 'Skin Lab User';
  String userEmail = '';
  final List<JournalEntry> journal = [];

  Future<void> loadPreferences() async {
    await ApiService.instance.init();
    try {
      final preferences = await SharedPreferences.getInstance();
      themeMode = preferences.getBool(_darkModeKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
      notifyListeners();
      if (!ApiService.instance.isAuthenticated) return;
      await productController.load();
      await baseline.refresh();
      await dailyContext.refresh();
      await home.refresh();
      safetyAccepted = preferences.getBool(_safetyAcceptedKey) ?? false;

      // Fetch live user profile from Azure
      final userProfile = await ApiService.instance.getCurrentUser();
      if (userProfile != null) {
        userName = userProfile['full_name'] as String? ?? userName;
        userEmail = userProfile['email'] as String? ?? userEmail;
        selectedGoal = userProfile['selected_goal'] as String? ?? selectedGoal;
        if (userProfile['skin_concerns'] is List) {
          skinConcerns.clear();
          skinConcerns.addAll(
            (userProfile['skin_concerns'] as List).cast<String>(),
          );
        }
      }

      // Sync remote experiment if active
      final remoteExp = await ApiService.instance.getCurrentExperiment();
      if (remoteExp != null) {
        experimentDay = remoteExp['current_day'] as int? ?? 1;
        experimentPaused = remoteExp['status'] == 'paused';
      }
      notifyListeners();
    } catch (_) {
      // Keep safe defaults when platform storage or network is unavailable.
    }
  }

  void clearAccountData() {
    safetyAccepted = false;
    selectedTab = 0;
    baseline.clear();
    dailyContext.clear();
    home.clear();
    experiments.clear();
    experimentDay = 1;
    experimentPaused = false;
    doctorLinkActive = false;
    selectedGoal = '';
    skinConcerns.clear();
    userName = 'Skin Lab User';
    userEmail = '';
    journal.clear();
    productController.clear();
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_darkModeKey, themeMode == ThemeMode.dark);
    } catch (_) {}
  }

  Future<void> acceptSafety() async {
    safetyAccepted = true;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_safetyAcceptedKey, true);
    } catch (_) {}
  }

  void selectTab(int value) {
    selectedTab = value;
    notifyListeners();
  }

  void selectGoal(String value) {
    selectedGoal = value;
    notifyListeners();
  }

  void toggleConcern(String value) {
    skinConcerns.contains(value)
        ? skinConcerns.remove(value)
        : skinConcerns.add(value);
    notifyListeners();
  }

  // Legacy callers can request a read, never manufacture a measurement.
  Future<bool> addJournalEntry() => home.refresh();

  // A confirmed write never increments baseline locally. Read its server projection.
  Future<void> markTodayCheckedIn() async {
    await baseline.refresh();
    await home.refresh();
  }

  void togglePause() {
    experiments.refresh();
  }

  void revokeDoctorLink() {
    doctorLinkActive = false;
    notifyListeners();
    final user = ApiService.instance.currentUser;
    if (user != null && user['user_id'] != null) {
      ApiService.instance
          .revokeDoctorAccess(user['user_id'].toString())
          .catchError((_) => false);
    }
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(clearAccountData);
    experiments
      ..removeListener(notifyListeners)
      ..dispose();
    home
      ..removeListener(notifyListeners)
      ..dispose();
    dailyContext
      ..removeListener(notifyListeners)
      ..dispose();
    baseline
      ..removeListener(notifyListeners)
      ..dispose();
    productController
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
