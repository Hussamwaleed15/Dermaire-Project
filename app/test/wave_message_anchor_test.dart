import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/messaging/anchored_conversation.dart';
import 'package:dermaire_app/messaging/message_timeline.dart';
import 'package:dermaire_app/messaging/messaging_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wave_messaging_test.dart' as f;

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'prepend keeps variable-height visible row dark=$dark scale=$scale',
        (t) async {
          t.view.physicalSize = const Size(320, 1100);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final wire = f.MessageWire();
          CareMessage message(int i) => CareMessage.fromApi(
            wire.message(
              i,
              'Message $i ${List.filled(i % 7 + 1, 'variable length text').join(' ')}',
            ),
            wire.model,
          );
          var messages = [for (var i = 51; i <= 100; i++) message(i)];
          late StateSetter change;
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: StatefulBuilder(
                builder: (context, set) {
                  change = set;
                  return AnchoredConversation(
                    header: const [
                      Text('Conversation'),
                      Text('Load earlier messages'),
                    ],
                    footer: const [Text('Composer')],
                    messages: messages,
                    owner: wire.owner,
                    role: wire.role,
                    peerRead: 60,
                  );
                },
              ),
            ),
          );
          await t.pumpAndSettle();
          final scroll = t.state<ScrollableState>(find.byType(Scrollable));
          scroll.position.jumpTo(450);
          await t.pumpAndSettle();
          final visible =
              find
                      .byType(CareMessageRow)
                      .evaluate()
                      .where((e) {
                        final box = e.renderObject as RenderBox;
                        final y = box.localToGlobal(Offset.zero).dy;
                        return y >= 60 && y < 900;
                      })
                      .first
                      .widget
                  as CareMessageRow;
          final anchor = find.byWidgetPredicate(
            (w) => w is CareMessageRow && w.message.id == visible.message.id,
          );
          final before = t.getTopLeft(anchor).dy;
          change(() => messages = [for (var i = 1; i <= 100; i++) message(i)]);
          await t.pumpAndSettle();
          expect(t.getTopLeft(anchor).dy, closeTo(before, .1));
          expect(t.takeException(), isNull);
          // Appended server messages and header loading changes keep the origin.
          change(() => messages = [...messages, message(101)]);
          await t.pumpAndSettle();
          expect(t.getTopLeft(anchor).dy, closeTo(before, .1));
          scroll.position.jumpTo(scroll.position.minScrollExtent);
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.text('Conversation'),
            -700,
            maxScrolls: 100,
          );
          expect(find.text('Conversation'), findsOneWidget);
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
