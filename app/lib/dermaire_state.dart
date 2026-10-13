import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'baseline/baseline_controller.dart';
import 'account/account_controller.dart';
import 'clinical/clinical_controller.dart';
import 'observations/observation_controller.dart';
import 'experiments/experiment_controller.dart';
import 'context_controller.dart';
import 'home_controller.dart';
import 'capture/guided_capture_controller.dart';
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
    ClinicalRepository? clinicalRepository,
    ObservationRepository? observationRepository,
    GuidedCaptureRepository? captureRepository,
  }) {
    guidedCapture = GuidedCaptureController(
      ApiService.instance,
      repository: captureRepository,
    );
    observations = ObservationController(
      ApiService.instance,
      repository: observationRepository,
      onConfirmed: _observationConfirmed,
      onUncertain: _refreshObservationSafety,
    )..addListener(notifyListeners);
    clinical = ClinicalController(
      ApiService.instance,
      repository: clinicalRepository,
    )..addListener(notifyListeners);
    account = AccountController(ApiService.instance)
      ..addListener(_accountChanged);
    experiments = ExperimentController(
      experimentRepository ?? RemoteExperimentRepository(),
      onConfirmed: (generation) =>
          refreshRoutineContext(generation: generation, experiments: false),
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
      onConfirmed: (generation) =>
          refreshRoutineContext(generation: generation, products: false),
    )..addListener(notifyListeners);
  }

  void _refreshObservationSafety() {
    // The server may have received an uncertain write. Re-read guidance without
    // using a safety response as proof that the observation was saved.
    clinical.markStale();
    unawaited(clinical.refresh());
  }

  void _observationConfirmed() {
    // Only re-read server projections, never increment Home/baseline locally.
    _refreshObservationSafety();
    final generation = ApiService.instance.sessionGeneration;
    unawaited(markTodayCheckedIn());
    unawaited(observations.loadHistory(generation: generation));
  }

  late final ObservationController observations;
  late final GuidedCaptureController guidedCapture;

  Object? _clinicalProfile;
  void _accountChanged() {
    final profile = account.value;
    if (account.ready && !identical(profile, _clinicalProfile)) {
      _clinicalProfile = profile;
      // A verified profile update can change ingredient/sensitivity evidence.
      // Refresh server guidance; never recalculate it on the device.
      if (clinical.allowed &&
          (clinical.safety.value != null || clinical.review.value != null)) {
        clinical.markStale();
        unawaited(clinical.refresh());
      }
    }
    notifyListeners();
  }

  late final ClinicalController clinical;
  late final AccountController account;
  late final ProductsController productController;
  late final BaselineController baseline;
  late final ContextController dailyContext;
  late final HomeController home;
  late final ExperimentController experiments;
  static const _darkModeKey = 'dermaire_dark_mode';

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
    guidedCapture.clear();
    observations.clear();
    clinical.clear();
    _clinicalProfile = null;
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
    // Dispatch in this session together; never start a second read after logout.
    await Future.wait([baseline.refresh(), home.refresh()]);
  }

  Future<void> refreshPatientHome({
    required int generation,
    bool refreshProfile = false,
  }) async {
    final api = ApiService.instance;
    if (!api.canReadPatientClinicalStatus ||
        !api.isCurrentSession(generation)) {
      return;
    }
    // Independent sections render as soon as they arrive. No local projection.
    await Future.wait([
      home.refresh(),
      baseline.refresh(),
      observations.loadHistory(generation: generation),
      clinical.refresh(expectedGeneration: generation),
      if (refreshProfile) account.hydrate(reuseConsent: false),
    ]);
  }

  /// Read affected projections; never manufacture completion or inject PSM facts.
  Future<void> refreshRoutineContext({
    required int generation,
    bool products = true,
    bool experiments = true,
  }) async {
    final api = ApiService.instance;
    if (!api.isCurrentSession(generation) || !api.canReadPatientClinicalStatus) {
      return;
    }
    await Future.wait([
      if (products) productController.load(),
      if (experiments) this.experiments.refresh(),
      home.refresh(),
      clinical.refresh(expectedGeneration: generation),
    ]);
  }

  void resumePatientHome() {
    if (!ApiService.instance.canReadPatientClinicalStatus) return;
    home.markStale();
    baseline.markStale();
    observations.markHistoryStale();
    clinical.markStale();
    unawaited(
      refreshPatientHome(
        generation: ApiService.instance.sessionGeneration,
        refreshProfile: true,
      ),
    );
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
    guidedCapture.dispose();
    observations
      ..removeListener(notifyListeners)
      ..dispose();
    clinical
      ..removeListener(notifyListeners)
      ..dispose();
    account
      ..removeListener(_accountChanged)
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
