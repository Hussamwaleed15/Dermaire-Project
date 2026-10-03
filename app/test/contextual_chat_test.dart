import 'package:dermaire_app/chatbot.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ApiService.instance.init());

  testWidgets('failed server chat shows unavailable assessment, not local conclusions', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SkinAssistantScreen()));
      await tester.enterText(find.byKey(const Key('assistantInput')), 'my routine is worse');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('server assistant is unavailable'), findsOneWidget);
      expect(find.textContaining('safety status could not be checked'), findsOneWidget);
    }, () => MockClient((_) async => http.Response('{}', 503)));
  });

  testWidgets('chat displays canonical server response', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SkinAssistantScreen()));
      await tester.enterText(find.byKey(const Key('assistantInput')), 'what changed?');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Recorded evidence remains uncertain.'), findsOneWidget);
    }, () => MockClient((request) async {
      expect(request.url.path, endsWith('/chat'));
      return http.Response('{"reply":"Recorded evidence remains uncertain.","kind":"education"}', 200);
    }));
  });
}
