// Synthetic debug-only native qualification entry. Never the production target.
import 'dart:convert';
import 'dart:io';
import 'package:dermaire_app/recovery/encrypted_operation_journal.dart';
import 'package:dermaire_app/recovery/journal_platform.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/recovery/product_receipt_reader.dart';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

/// Test-only storage qualification. A simulator does not reproduce hardware file
/// Data Protection. Never used by lib/ or enabled for actual app mutations.
class SimulatorQualificationPlatform implements JournalPlatform {
  final native = NativeJournalPlatform();
  bool protectionUnavailable = false;
  @override
  Future<Uint8List> epoch() => native.epoch();
  @override
  Future<String> directory(String n) => native.directory(n);
  @override
  Future<Uint8List> key(String n, {required bool create}) =>
      native.key(n, create: create);
  @override
  Future<void> action(String n, String action) async {
    try {
      await native.action(n, action);
    } on JournalUnavailable catch (e) {
      if (action != 'protectFiles' ||
          e.stage != 'fileProtectionMismatch' ||
          !const bool.fromEnvironment('DERMAIRE_SIMULATOR_QUALIFICATION') ||
          kReleaseMode) {
        rethrow;
      }
      protectionUnavailable = true;
    }
  }
}

EncryptedOperationJournal? heldSyntheticJournal;

void require(bool value) {
  if (!value) throw StateError('Synthetic recovery check failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) throw StateError('Synthetic entry disabled in release');
  final phaseFile = File(
    '${Directory.systemTemp.path}/dermaire-journal-test-phase',
  );
  final phase = phaseFile.existsSync()
      ? phaseFile.readAsStringSync().trim()
      : '';
  if (!['prepare', 'recover', 'cleanup'].contains(phase)) {
    throw StateError('Explicit synthetic phase required');
  }
  final platform = SimulatorQualificationPlatform();
  final ns = await JournalNamespace.resolve(
    platform,
    owner: 'synthetic-restart-2',
    role: 'patient',
  );
  final dir = await platform.directory(ns.value);
  final result = File('${Directory(dir).parent.path}/validation-$phase.json');
  final evidence = <String, Object>{
    'phase': phase,
    'passed': false,
    'qualification_only': true,
  };
  var checkpoint = 'initializing';
  try {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService.instance;
    api.baseUrl = 'https://flutter-tests.invalid/api/v1';
    await api.init();
    var writes = 0, receipts = 0, currentReads = 0;
    await api.withSyntheticTransport(
      () async {
        await api.login(
          email: 'synthetic@example.invalid',
          password: 'synthetic',
        );
        await api.readSafetyAcceptance();
        final generation = api.sessionGeneration;
        bool authorized() =>
            api.isCurrentSession(generation) &&
            api.authenticatedOwner == 'synthetic-restart-2' &&
            api.canReadPatientClinicalStatus;
        checkpoint = 'opening-journal';
        final journal = await EncryptedOperationJournal.open(
          platform: platform,
          namespace: ns,
          active: authorized,
        );
        try {
          checkpoint = 'journal-open';
          final original = OperationIdentity(
            owner: 'synthetic-restart-2',
            role: 'patient',
            path: 'products',
            receiptPath: 'products/attempts',
            key: 'c' * 48,
            fingerprint: 'd' * 64,
          );
          final coordinator = JournalCoordinator(
            journal,
            active: (_) => authorized(),
            now: () => DateTime.now().toUtc(),
          );
          if (phase == 'prepare') {
            require((await journal.pending()).isEmpty);
            await coordinator.prepareAndSend(
              JournalEntry(
                identity: original,
                createdAt: DateTime.now().toUtc(),
                reviewAt: DateTime.now().toUtc().add(const Duration(days: 2)),
                phase: JournalPhase.prepared,
              ),
              () async {
                // Check actual disk through an independent SQLCipher connection before
                // issuing the synthetic write. No memory-only acknowledgment.
                checkpoint = 'read-before-send';
                final second = await EncryptedOperationJournal.open(
                  platform: platform,
                  namespace: ns,
                  active: authorized,
                );
                require(
                  (await second.read(original))?.phase ==
                      JournalPhase.unconfirmed,
                );
                second.close();
                await api.patientResource(
                  'products',
                  generation,
                  method: 'POST',
                  payload: {'name': 'Synthetic'},
                  idempotencyKey: original.key,
                );
              },
            );
            require(writes == 1);
            require(
              (await journal.read(original))?.phase == JournalPhase.unconfirmed,
            );
          } else if (phase == 'recover') {
            final restored = await journal.pending();
            require(
              restored.length == 1 &&
                  restored.single.identity.key == original.key &&
                  restored.single.phase == JournalPhase.unconfirmed,
            );
            final outcome = await coordinator.reconcile(
              original,
              ProductReceiptReader(api, generation),
            );
            require(
              outcome == JournalPhase.reviewRequired,
            ); // Original revision1 vs current2.
            require(writes == 0 && receipts == 1 && currentReads == 1);
            final b = await JournalNamespace.resolve(
              platform,
              owner: 'synthetic-restart-other-2',
              role: 'patient',
            );
            final other = await EncryptedOperationJournal.open(
              platform: platform,
              namespace: b,
              active: () => true,
            );
            require((await other.pending()).isEmpty);
            await other.erase();
            await api
                .init(); // Expired/current session cannot read recovered identities.
            var denied = false;
            try {
              await journal.pending();
            } on RecoverySessionLost {
              denied = true;
            }
            require(denied);
          } else {
            await journal.erase();
            var denied = false;
            try {
              await platform.key(ns.value, create: true);
            } on JournalUnavailable {
              denied = true;
            }
            require(denied);
          }
          final engine = sqlite3.openInMemory();
          evidence['cipher_version'] = engine
              .select('PRAGMA cipher_version')
              .single
              .values
              .first
              .toString();
          evidence['sqlite_version'] = engine
              .select('SELECT sqlite_version()')
              .single
              .values
              .first
              .toString();
          engine.close();
          evidence['file_protection_verified'] =
              !platform.protectionUnavailable;
          evidence.addAll({
            'writes': writes,
            'receipts': receipts,
            'current_reads': currentReads,
            'passed': true,
          });
        } finally {
          if (phase == 'prepare') {
            heldSyntheticJournal =
                journal; // Keep WAL open until OS process termination.
          } else {
            journal.close();
          }
        }
      },
      () => MockClient((request) async {
        require(request.url.host == 'flutter-tests.invalid');
        final path = request.url.path;
        if (path.endsWith('/auth/login')) {
          return http.Response(
            '{"access_token":"synthetic","expires_in":3600,"user_id":"synthetic-restart-2","role":"patient"}',
            200,
          );
        }
        if (path.endsWith('/users/me')) {
          return http.Response(
            '{"id":"synthetic-restart-2","role":"patient","safety_accepted":true}',
            200,
          );
        }
        if (request.method == 'POST' && path.endsWith('/products')) {
          writes++;
          require(request.headers['Idempotency-Key'] == 'c' * 48);
          throw const SocketException('Synthetic committed response lost');
        }
        final product = {
          'id': 'synthetic-product',
          'user_id': 'synthetic-restart-2',
          'status': 'active',
          'name': 'Synthetic',
          'category': 'serum',
          'active_ingredients': <String>[],
          'skin_concerns': <String>[],
          'usage_instructions': 'Synthetic',
          'frequency_per_week': 3,
          'time_of_use': 'both',
          'in_routine': false,
          'in_experiment': false,
          'created_at': '2026-10-19T00:00:00Z',
          'updated_at': '2026-10-19T00:00:00Z',
          'start_date': '2026-10-19T00:00:00Z',
          'tags': <String>[],
          'revision_protected': true,
          'revision': 1,
        };
        if (path.endsWith('/products/attempts/${'c' * 48}')) {
          require(request.method == 'GET');
          receipts++;
          return http.Response(
            jsonEncode({
              'schema_version': 1,
              'attempt_id': 'synthetic-attempt',
              'owner_id': 'synthetic-restart-2',
              'actor_id': 'synthetic-restart-2',
              'operation': 'product_create',
              'status': 'committed',
              'result_availability': 'retained',
              'resource_id': 'synthetic-product',
              'resource_revision': 1,
              'recorded_at': '2026-10-19T00:00:00Z',
              'expires_at': '2026-11-18T00:00:00Z',
              'result': product,
            }),
            200,
          );
        }
        if (path.endsWith('/products/synthetic-product')) {
          currentReads++;
          return http.Response(jsonEncode({...product, 'revision': 2}), 200);
        }
        throw StateError('Unexpected synthetic route');
      }),
    );
  } catch (error) {
    evidence['error'] = 'Synthetic validation failed';
    evidence['checkpoint'] = checkpoint;
    evidence['failure_type'] = error.runtimeType.toString();
    if (error is JournalUnavailable) evidence['storage_stage'] = error.stage;
  }
  await result.writeAsString(jsonEncode(evidence), flush: true);
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            evidence['passed'] == true
                ? 'Synthetic recovery verified'
                : 'Synthetic recovery failed',
          ),
        ),
      ),
    ),
  );
}
