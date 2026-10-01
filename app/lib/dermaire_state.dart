import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'baseline/baseline_controller.dart';
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
  DermaireState({ProductRepository? productRepository, BaselineRepository? baselineRepository}) {
    baseline = BaselineController(baselineRepository ?? RemoteBaselineRepository())
      ..addListener(notifyListeners);
    ApiService.instance.addListener(clearAccountData);
    productController = ProductsController(
      productRepository ?? RemoteProductRepository(),
    )..addListener(notifyListeners);
  }

  late final ProductsController productController;
  late final BaselineController baseline;
  static const _darkModeKey = 'dermaire_dark_mode';
  static const _safetyAcceptedKey = 'dermaire_safety_accepted';

  ThemeMode themeMode = ThemeMode.light;
  bool safetyAccepted = false;
  int selectedTab = 0;
  int tokens = 0;
  int? get baselineCheckIns => baseline.completedDays;
  int experimentDay = 1;
  bool experimentPaused = false;
  bool get todayCheckedIn => baseline.todayCheckedIn;
  bool doctorLinkActive = false;
  String selectedGoal = 'Improve Skin Texture';
  final Set<String> skinConcerns = <String>{};
  final List<String> redemptionHistory = [];
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
      safetyAccepted = preferences.getBool(_safetyAcceptedKey) ?? false;
      
      // Fetch live user profile from Azure
      final userProfile = await ApiService.instance.getCurrentUser();
      if (userProfile != null) {
        userName = userProfile['full_name'] as String? ?? userName;
        userEmail = userProfile['email'] as String? ?? userEmail;
        selectedGoal = userProfile['selected_goal'] as String? ?? selectedGoal;
        if (userProfile['skin_concerns'] is List) {
          skinConcerns.clear();
          skinConcerns.addAll((userProfile['skin_concerns'] as List).cast<String>());
        }
      }

      // Fetch live checkins from Azure to populate real journal
      final checkins = await ApiService.instance.getCheckIns();
      if (checkins.isNotEmpty) {
        journal.clear();
        for (final c in checkins) {
          final dateStr = (c['created_at'] as String?)?.split('T').first ?? 'Recent';
          final timeStr = c['time_of_day']?.toString().toUpperCase() ?? 'CHECK-IN';
          final h = c['hydration_score'] ?? 70;
          final r = c['redness_score'] ?? 20;
          final t = c['texture_score'] ?? 70;
          journal.add(JournalEntry(dateStr, timeStr, 'Hydration: $h · Redness: $r · Texture: $t'));
        }
        tokens = checkins.length * 2;
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
    tokens = 0;
    baseline.clear();
    experimentDay = 1;
    experimentPaused = false;
    doctorLinkActive = false;
    selectedGoal = 'Improve Skin Texture';
    skinConcerns.clear();
    redemptionHistory.clear();
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

  void earnToken([String? reason]) {
    tokens++;
    notifyListeners();
  }

  void addJournalEntry() {
    journal.insert(
      0,
      const JournalEntry(
        'Today',
        'Morning',
        'Hydration: Good · Texture: Stable',
      ),
    );
    earnToken();
  }

  // A confirmed write never increments baseline locally. Read its server projection.
  Future<void> markTodayCheckedIn() async {
    await baseline.refresh();
  }

  bool redeemReward() {
    if (tokens < 10) return false;
    tokens -= 10;
    redemptionHistory.insert(0, 'Travel-size Hydrating Serum · Today');
    notifyListeners();
    // Sync redemption with Azure Backend
    ApiService.instance.redeemReward('travel_serum').catchError((_) => <String, dynamic>{});
    return true;
  }

  void togglePause() {
    experimentPaused = !experimentPaused;
    notifyListeners();
  }

  void revokeDoctorLink() {
    doctorLinkActive = false;
    notifyListeners();
    final user = ApiService.instance.currentUser;
    if (user != null && user['user_id'] != null) {
      ApiService.instance.revokeDoctorAccess(user['user_id'].toString()).catchError((_) => false);
    }
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(clearAccountData);
    baseline
      ..removeListener(notifyListeners)
      ..dispose();
    productController
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
