import 'package:flutter_test/flutter_test.dart';
import 'package:dermaire_app/tester/tester_app.dart';

void main() {
  test('summary exports functional results only and resets per account', () {
    final summary = TestSessionSummary();
    summary.results['Google login'] = 'PASS';
    expect(summary.export(), contains('Google login: PASS'));
    expect(summary.export(), isNot(contains('access_token')));
    summary.reset();
    expect(summary.results.values.every((v) => v == 'SKIPPED'), isTrue);
  });
  testWidgets(
    'signed out harness exposes Google and production identity only',
    (tester) async {
      await tester.pumpWidget(const TesterApp());
      expect(find.text('TESTER • PRODUCTION'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Delete Test Account'), findsNothing);
      expect(find.textContaining('Google login: SKIPPED'), findsOneWidget);
    },
  );
}
