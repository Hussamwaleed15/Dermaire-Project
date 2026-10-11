import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'baseline/baseline_controller.dart';
import 'account/account_controller.dart';
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
    account = AccountController(ApiService.instance)
      ..addListener(notifyListeners);
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

  late final AccountController account;
  late final ProductsController productController;
  late final BaselineController baseline;
  late final ContextController dailyContext;
  late final HomeController home;
  late final ExperimentController experiments;
  static const _darkModeKey = 'dermaire_dark_mode';

  Locale locale = const Locale('en');

  void toggleLanguage() {
    locale = Locale(locale.languageCode == 'en' ? 'ar' : 'en');
    notifyListeners();
  }

  ThemeMode themeMode = ThemeMode.light;
  bool get safetyAccepted => ApiService.instance.hasConfirmedSafetyAcceptance;
  int selectedTab = 0;
  int? get baselineCheckIns => baseline.completedDays;
  int experimentDay = 1;
  bool experimentPaused = false;
  bool get todayCheckedIn => baseline.todayCheckedIn;
  bool doctorLinkActive = false;
  String get selectedGoal => account.value?.selectedGoal ?? '';
  Set<String> get skinConcerns =>
      Set.unmodifiable(account.value?.skinConcerns ?? <String>[]);
  String get userName => account.value?.name ?? '';
  String get userEmail => account.value?.email ?? '';
  String? get userRole => account.value?.role;
  final List<JournalEntry> journal = [];

  Future<void> loadPreferences() async {
    await ApiService.instance.init();
    try {
      final preferences = await SharedPreferences.getInstance();
      themeMode = preferences.getBool(_darkModeKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
      notifyListeners();
    } catch (_) {
      // Keep safe defaults when platform storage or network is unavailable.
    }
  }

  void clearAccountData() {
    account.clear();
    selectedTab = 0;
    baseline.clear();
    dailyContext.clear();
    home.clear();
    experiments.clear();
    experimentDay = 1;
    experimentPaused = false;
    doctorLinkActive = false;
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

  void selectTab(int value) {
    selectedTab = value;
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
    account
      ..removeListener(notifyListeners)
      ..dispose();
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
