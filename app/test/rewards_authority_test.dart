import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';

void main() {
  testWidgets('rewards remain honestly unavailable through reset and restart', (tester) async {
    for (var restart = 0; restart < 2; restart++) {
      final state = DermaireState();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: RewardsTab(state: state))));
      expect(find.textContaining('Rewards are not available.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('free product'), findsNothing);
      expect(find.text('Redemption history'), findsNothing);
      state.clearAccountData();
      await tester.pump();
      expect(find.textContaining('Rewards are not available.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    }
  });
}
