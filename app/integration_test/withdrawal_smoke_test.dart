import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/support/withdrawal_workflow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'isolated patient withdrawal smoke on actual Flutter device',
    (t) => withdrawalWorkflow(t, dark: false, large: false, device: true),
  );
}
