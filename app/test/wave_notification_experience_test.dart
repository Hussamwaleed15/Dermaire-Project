import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/notifications/inbox_models.dart';
import 'package:dermaire_app/notifications/inbox_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'wave_inbox_test.dart' as f;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  test(
    'loaded filters preserve server order and never infer a global unread count',
    () {
      final w = f.InboxWire();
      w.notices.last.addAll({
        'read_at': '2026-10-18T11:00:00Z',
        'unread': false,
      });
      final rows = w.notices.map(InboxNotice.new).toList();
      expect(filterLoadedNotices(rows).map((n) => n.id), [
        'notice-2',
        'notice-1',
      ]);
      expect(filterLoadedNotices(rows, unreadOnly: true).single.id, 'notice-2');
      expect(
        filterLoadedNotices(rows, category: 'message', unreadOnly: true),
        isEmpty,
      );
    },
  );
  test('UTC due grouping uses server date rather than device local date', () {
    final w = f.InboxWire();
    final row = InboxNotice({
      ...w.notices.first,
      'due_at': '2026-10-18T01:00:00+03:00',
    });
    expect(noticeUtcDay(row), '2026-10-17');
  });
  for (final dark in [false, true]) {
    testWidgets('real inbox filtering and bounded counts dark=$dark 320px200%', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final w = f.InboxWire()..pageSize = 2;
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
            home: const NotificationInboxScreen(),
          ),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.widgetWithText(ChoiceChip, 'routine'),
          180,
        );
        await t.ensureVisible(find.widgetWithText(ChoiceChip, 'routine'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(ChoiceChip, 'routine'));
        await t.pumpAndSettle();
        expect(
          find.text(
            'No loaded updates match this filter. Change filters or load earlier updates.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('0 matching loaded updates'),
          findsOneWidget,
        );
        expect(w.sends, isEmpty);
        await t.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(ChoiceChip, 'All'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Due · 2026-10-18 UTC'), 180);
        expect(find.text('Due · 2026-10-18 UTC'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      });
    });
  }
  for (final field in [
    'IANA timezone',
    'Quiet hours start · HH:mm',
    'Quiet hours end · HH:mm',
  ]) {
    testWidgets('editing $field invalidates prior settings consent', (t) async {
      final w = f.InboxWire();
      await w.run(() async {
        await w.login();
        await t.pumpWidget(
          const MaterialApp(home: NotificationPreferencesScreen()),
        );
        await t.pumpAndSettle();
        final consent = find.widgetWithText(
          CheckboxListTile,
          'I consent to save these notification settings.',
        );
        await t.scrollUntilVisible(
          consent,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        final cb = find.descendant(
          of: consent,
          matching: find.byType(Checkbox),
        );
        await t.ensureVisible(cb);
        await t.pumpAndSettle();
        await t.tap(cb);
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save settings'),
              )
              .onPressed,
          isNotNull,
        );
        final input = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == field,
        );
        await t.ensureVisible(input);
        await t.pumpAndSettle();
        await t.enterText(
          input,
          field == 'IANA timezone' ? 'Africa/Cairo' : '01:30',
        );
        await t.pumpAndSettle();
        expect(t.widget<Checkbox>(cb).value, false);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save settings'),
              )
              .onPressed,
          isNull,
        );
        expect(w.sends, isEmpty);
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      });
    });
  }
}
