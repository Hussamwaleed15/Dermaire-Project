import 'dart:async';
import 'package:flutter/material.dart';

class _DoctorLifecycle extends WidgetsBindingObserver {
  _DoctorLifecycle(this.changed);
  final void Function(AppLifecycleState) changed;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => changed(state);
}

/// Hidden routes/background views display no clinical records. Resume is a read,
/// never an automatic write. ModalRoute dependencies also work without observers.
mixin DoctorViewLifecycle<T extends StatefulWidget> on State<T> {
  late final _DoctorLifecycle _doctorLifecycle;
  bool _foreground = true, _routeVisible = true;
  bool get doctorViewVisible => _foreground && _routeVisible;
  int _viewRevision = 0;
  void pauseDoctorView({required bool background});
  Future<void> resumeDoctorView();
  @override
  void initState() {
    super.initState();
    final initial = WidgetsBinding.instance.lifecycleState;
    _foreground = initial == null || initial == AppLifecycleState.resumed;
    _doctorLifecycle = _DoctorLifecycle((state) {
      final before = doctorViewVisible;
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) {
        _viewRevision++;
        pauseDoctorView(background: true);
        if (mounted) setState(() {});
      } else if (doctorViewVisible && !before) {
        _viewRevision++;
        unawaited(resumeDoctorView());
        if (mounted) setState(() {});
      }
    });
    WidgetsBinding.instance.addObserver(_doctorLifecycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final before = doctorViewVisible;
    _routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (before == doctorViewVisible) return;
    final revision = ++_viewRevision, visible = doctorViewVisible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _viewRevision) return;
      if (visible) {
        unawaited(resumeDoctorView());
      } else {
        pauseDoctorView(background: false);
      }
    });
  }

  @override
  void dispose() {
    _viewRevision++;
    WidgetsBinding.instance.removeObserver(_doctorLifecycle);
    super.dispose();
  }
}

Widget pausedDoctorView() => Scaffold(
  appBar: AppBar(),
  body: const Center(
    child: Text('Doctor view paused. Verify access when returning.'),
  ),
);
