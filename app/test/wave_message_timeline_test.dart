import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/messaging/message_timeline.dart';
import 'package:dermaire_app/messaging/messaging_models.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'wave_messaging_test.dart' as f;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  test('UTC day and clock do not silently use local timezone', () {
    final value = DateTime.parse('2026-10-18T01:02:03+03:00');
    expect(messageUtcDay(value), '2026-10-17');
    expect(messageUtcClock(value), '22:02:03 UTC');
  });
  test(
    'timeline keeps server sequence order while grouping only adjacent UTC days',
    () {
      final w = f.MessageWire();
      final messages = [
        CareMessage.fromApi(w.message(1, 'one'), w.model),
        CareMessage.fromApi({
          ...w.message(2, 'two'),
          'created_at': '2026-10-19T00:00:00Z',
        }, w.model),
        CareMessage.fromApi({
          ...w.message(3, 'three'),
          'created_at': '2026-10-19T00:01:00Z',
        }, w.model),
      ];
      final rows = buildCareMessageTimeline(
        messages: messages,
        owner: w.owner,
        role: w.role,
        peerRead: 1,
      ).cast<CareMessageRow>();
      expect(rows.map((r) => r.message.sequence), [1, 2, 3]);
      expect(rows.map((r) => r.startsDay), [true, true, false]);
    },
  );
  for (final doctor in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'real conversation grouped days doctor=$doctor dark=$dark at320px200%',
        (t) async {
          t.view.physicalSize = const Size(320, 1200);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final w = f.MessageWire(doctor: doctor);
          w.messages.addAll([
            {
              ...w.message(1, 'First saved message'),
              'created_at': '2026-10-17T23:59:00Z',
            },
            {
              ...w.message(2, 'Next day peer message'),
              'actor_id': doctor ? 'patient-1' : 'doctor-1',
              'created_at': '2026-10-18T00:01:00Z',
            },
            {
              ...w.message(3, 'Same day own unread message'),
              'created_at': '2026-10-18T12:01:00Z',
            },
          ]);
          if (doctor) {
            w.patientRead = 1;
          } else {
            w.doctorRead = 1;
          }
          await w.run(() async {
            await w.login();
            await t.pumpWidget(
              MaterialApp(
                theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: CareConversationScreen(thread: w.model),
              ),
            );
            await t.pumpAndSettle();
            await t.scrollUntilVisible(
              find.text('Messages · 2026-10-17 UTC'),
              180,
            );
            await t.pumpAndSettle();
            expect(find.text('Messages · 2026-10-17 UTC'), findsOneWidget);
            expect(find.text('Messages · 2026-10-18 UTC'), findsOneWidget);
            expect(find.text('Acknowledged read in app'), findsOneWidget);
            expect(find.textContaining('delivered'), findsNothing);
            expect(find.text('23:59:00 UTC · sequence 1'), findsOneWidget);
            expect(find.text('00:01:00 UTC · sequence 2'), findsOneWidget);
            expect(w.posts, 0);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await ApiService.instance.init();
          });
        },
      );
    }
  }
}
