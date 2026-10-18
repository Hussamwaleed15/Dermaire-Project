import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import '../doctor/doctor_view_lifecycle.dart';
import 'contract.dart';

String integrationError(Object failure) => failure is IntegrationFailure
    ? failure.message
    : RequestFailure.from(failure).message;

abstract class PrivateController extends ChangeNotifier {
  PrivateController()
    : generation = ApiService.instance.sessionGeneration,
      owner = ApiService.instance.authenticatedOwner ?? '',
      role = ApiService.instance.authenticatedRole ?? '' {
    api.addListener(sessionChanged);
  }
  final api = ApiService.instance;
  final int generation;
  final String owner, role;
  bool disposed = false, visible = true, busy = false;
  int revision = 0;
  String? error;
  bool get authenticatedCurrent =>
      !disposed &&
      owner.isNotEmpty &&
      api.isCurrentSession(generation) &&
      api.authenticatedOwner == owner &&
      api.authenticatedRole == role;
  bool get current =>
      authenticatedCurrent &&
      visible &&
      (role == 'patient'
          ? api.canReadPatientClinicalStatus
          : api.canReadDoctorWorkspace);
  bool valid(int ticket) => current && ticket == revision;
  void wipe();
  Future<void> refresh();
  void sessionChanged() {
    if (!current) {
      revision++;
      wipe();
      busy = false;
      error = null;
      notifyListeners();
    }
  }

  void hide() {
    if (disposed) return;
    visible = false;
    revision++;
    wipe();
    busy = false;
    error = null;
    notifyListeners();
  }

  Future<void> show() async {
    if (!authenticatedCurrent) return;
    visible = true;
    await refresh();
  }

  int begin() {
    final ticket = ++revision;
    busy = true;
    error = null;
    notifyListeners();
    return ticket;
  }

  void finish(int ticket) {
    if (!disposed && ticket == revision) {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    revision++;
    wipe();
    api.removeListener(sessionChanged);
    super.dispose();
  }
}

class PrivateView<T extends PrivateController> extends StatefulWidget {
  const PrivateView({
    super.key,
    required this.controller,
    required this.builder,
    this.unavailableBuilder,
  });
  final T controller;
  final Widget Function(BuildContext, T) builder;
  final Widget Function(BuildContext, T)? unavailableBuilder;
  @override
  State<PrivateView<T>> createState() => _PrivateViewState<T>();
}

class _PrivateViewState<T extends PrivateController>
    extends State<PrivateView<T>>
    with DoctorViewLifecycle<PrivateView<T>> {
  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  void pauseDoctorView({required bool background}) => widget.controller.hide();
  @override
  Future<void> resumeDoctorView() => widget.controller.show();
  @override
  void didUpdateWidget(covariant PrivateView<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.dispose();
      widget.controller.refresh();
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (doctorViewVisible && widget.controller.current) {
        return widget.builder(context, widget.controller);
      }
      if (doctorViewVisible &&
          widget.controller.authenticatedCurrent &&
          widget.unavailableBuilder != null) {
        return widget.unavailableBuilder!(context, widget.controller);
      }
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text(
            'Private view unavailable. Return and verify your account and access.',
          ),
        ),
      );
    },
  );
}
