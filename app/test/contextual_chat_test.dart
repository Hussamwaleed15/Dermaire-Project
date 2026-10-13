// F3 replaces the obsolete unauthenticated/minimal chat response fixture with
// actual consent/session + typed server envelope. These regressions still assert
// server-only canonical text and no local medical fallback.
import 'package:dermaire_app/chatbot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'patient_chat_test.dart' as p;
import 'private_capture_history_test.dart' as h;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  testWidgets(
    'failed server chat shows unavailable assessment, not local conclusions',
    (t) async {
      final f = p.Fixture()..code = 503;
      await f.run(() async {
        await f.login();
        await h.mount(t, f, SkinAssistantScreen(state: f.state));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('assistantInput')),
          'my routine is worse',
        );
        await t.tap(find.byTooltip('Send message'));
        await t.pumpAndSettle();
        expect(
          find.textContaining('server assistant is unavailable'),
          findsOneWidget,
        );
        expect(
          find.textContaining('safety status could not be checked'),
          findsOneWidget,
        );
        await f.done(t);
      });
    },
  );
  testWidgets('chat displays canonical server response', (t) async {
    final f = p.Fixture()
      ..body = p.envelope(message: 'Recorded evidence remains uncertain.');
    await f.run(() async {
      await f.login();
      await h.mount(t, f, SkinAssistantScreen(state: f.state));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('assistantInput')),
        'what changed?',
      );
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(find.text('Recorded evidence remains uncertain.'), findsOneWidget);
      await f.done(t);
    });
  });
}
