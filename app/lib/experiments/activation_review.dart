import 'package:flutter/material.dart';
import '../doctor/doctor_view_lifecycle.dart';
import '../services/api_service.dart';

/// A review is single-use. Hiding or changing session discards the reviewed copy;
/// returning never silently restores authority to activate an intervention.
class ExperimentActivationReview extends StatefulWidget {
  const ExperimentActivationReview({
    super.key,
    required this.generation,
    required this.entry,
    required this.experiment,
  });
  final int generation;
  final Map<String, dynamic> entry, experiment;
  @override
  State<ExperimentActivationReview> createState() =>
      _ExperimentActivationReviewState();
}

class _ExperimentActivationReviewState extends State<ExperimentActivationReview>
    with DoctorViewLifecycle<ExperimentActivationReview> {
  Map<String, dynamic>? entry, experiment;
  final api = ApiService.instance;
  bool get current =>
      api.isCurrentSession(widget.generation) &&
      api.canReadPatientClinicalStatus &&
      doctorViewVisible;
  @override
  void initState() {
    super.initState();
    entry = Map.of(widget.entry);
    experiment = Map.of(widget.experiment);
    api.addListener(sessionChanged);
  }

  void sessionChanged() {
    if (!current && mounted) {
      entry = null;
      experiment = null;
      setState(() {});
    }
  }

  @override
  void pauseDoctorView({required bool background}) {
    entry = null;
    experiment = null;
  }

  @override
  Future<void> resumeDoctorView() async {}
  @override
  void dispose() {
    api.removeListener(sessionChanged);
    entry = null;
    experiment = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = entry, row = experiment;
    if (!current || e == null || row == null) {
      return AlertDialog(
        title: const Text('Review expired'),
        content: const Text(
          'Return to experiments and verify the routine again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final change = switch (row['intervention']['type']) {
      'start_entry' => 'Start step',
      'stop_entry' => 'Stop step',
      'change_schedule' => 'Change schedule',
      _ => 'Unavailable',
    };
    return AlertDialog(
      title: const Text('Review linked routine'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product: ${e['product_name']}'),
            Text(
              'Current schedule: ${e['schedule']} · ${e['active'] == true ? 'active' : 'stopped'}',
            ),
            Text('Instructions: ${e['instructions'] ?? 'None recorded'}'),
            Text(
              'Planned change: $change · ${row['intervention']['schedule'] ?? 'no use'}',
            ),
            Text('Planned start: ${row['start_date']} (UTC)'),
            const Text(
              'Activation applies this saved experiment to the routine configuration shown here. The server checks eligibility and conflicts. This is not clinical approval.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep draft'),
        ),
        FilledButton(
          onPressed: () {
            if (current && entry != null) Navigator.pop(context, true);
          },
          child: const Text('Confirm activation'),
        ),
      ],
    );
  }
}
