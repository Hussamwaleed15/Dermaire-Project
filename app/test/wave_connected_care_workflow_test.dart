import 'package:flutter_test/flutter_test.dart';
import 'support/connected_care_workflow.dart';

void main() {
  for (final doctor in [false, true]) {
    for (final dark in [false, true]) {
      for (final large in [false, true]) {
        testWidgets(
          'connected care safety → messaging → plan → inbox → Agent → logout → account switch doctor=$doctor dark=$dark large=$large',
          (t) => connectedCareWorkflow(
            t,
            doctor: doctor,
            dark: dark,
            large: large,
          ),
        );
      }
    }
  }
}
