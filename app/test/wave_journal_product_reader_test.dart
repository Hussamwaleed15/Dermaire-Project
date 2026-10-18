import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/recovery/product_receipt_reader.dart';
import 'package:dermaire_app/recovery/recovery_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_authority_test.dart' as auth;
import 'wave_product_receipt_test.dart' as f;

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api.baseUrl = 'https://flutter-tests.invalid/api/v1';
    await api.init();
  });
  tearDown(() => api.init());
  for (final kind in ['create', 'patch', 'delete']) {
    test(
      'actual $kind receipt adapter reads original and current without replay',
      () async {
        final w = f.Wire()..kind = kind;
        await w.run((c) async {
          await w.submit(c);
          final op = c.pendingOperation!;
          final i = OperationIdentity(
            owner: op.owner,
            role: 'patient',
            path: op.path,
            receiptPath: op.attemptPath,
            key: op.key,
            fingerprint: OperationIdentity.digest(op.body),
            scope: op.recoveryScope,
          );
          final r = ProductReceiptReader(api, api.sessionGeneration);
          final before = w.writes;
          final receipt = await r.lookup(i);
          expect(receipt.outcome, ReceiptOutcome.committed);
          expect(await r.verifyCurrent(i, receipt), true);
          expect(w.writes, before);
          if (kind != 'delete') {
            w.current = {...w.current!, 'revision': 20};
            expect(await r.verifyCurrent(i, receipt), false);
          }
          w.changeReceipt = (raw) => {...raw, 'owner_id': 'other-account'};
          await expectLater(r.lookup(i), throwsFormatException);
        });
      },
    );
  }
  test(
    'unknown/expired receipts and denied/current-session loss stay unresolved',
    () async {
      final w = f.Wire()..loss = 'before';
      await w.run((c) async {
        await w.submit(c);
        final op = c.pendingOperation!;
        final i = OperationIdentity(
          owner: op.owner,
          role: 'patient',
          path: op.path,
          receiptPath: op.attemptPath,
          key: op.key,
          fingerprint: OperationIdentity.digest(op.body),
          scope: op.recoveryScope,
        );
        final r = ProductReceiptReader(api, api.sessionGeneration);
        expect((await r.lookup(i)).outcome, ReceiptOutcome.unknown);
        w.lookupStatus = 403;
        await expectLater(r.lookup(i), throwsA(isA<RecoveryPermissionLost>()));
        expect(c.pendingOperation!.key, i.key);
        await api.logout();
        await expectLater(r.lookup(i), throwsA(isA<RecoverySessionLost>()));
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'real retained-identity screen checks receipt 320px200% dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 1200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final w = f.Wire();
        await w.run((c) async {
          await w.submit(c);
          w.lookupStatus = 401;
          await c.recoverProductOperation();
          expect(api.isAuthenticated, false);
          w.lookupStatus = 200;
          await auth.login();
          expect(api.quarantinedOperations.length, 1);
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
              home: const RecoveryReviewScreen(),
            ),
          );
          await t.pumpAndSettle();
          final button = find.text('Check original product receipt');
          await t.scrollUntilVisible(button, 200);
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          final writes = w.writes;
          await t.tap(button);
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.textContaining(
              'Original receipt recorded and current product verified',
            ),
            -200,
          );
          expect(w.writes, writes);
          expect(api.quarantinedOperations.length, 1);
          expect(t.takeException(), isNull);
          await api.logout();
          await t.pumpAndSettle();
          expect(
            find.textContaining('Original receipt recorded'),
            findsNothing,
          );
          expect(find.text('Check original product receipt'), findsNothing);
        });
      },
    );
  }
}
