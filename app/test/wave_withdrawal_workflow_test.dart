import 'package:flutter_test/flutter_test.dart';
import 'support/withdrawal_workflow.dart';

void main() {
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'patient safety → selective revoke → plan → evaluation → logout → account switch dark=$dark large=$large',
        (t) => withdrawalWorkflow(t, dark: dark, large: large),
      );
    }
  }
}
