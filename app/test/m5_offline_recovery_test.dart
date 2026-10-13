import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/services/request_failure.dart';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'routine_authority_test.dart' as r;
import 'product_authority_test.dart' as p;

final api = ApiService.instance;

class Wire {
  String owner = 'patient-1';
  bool accepted = true;
  Object? failure;
  int? status;
  int gets = 0, writes = 0;
  Completer<http.Response>? pending;
  final logoutSent = Completer<void>();
  Completer<http.Response>? logoutResponse;
  Future<http.Response> call(http.Request request) async {
    expect(request.url.host, 'flutter-tests.invalid');
    final path = request.url.path;
    if (path.endsWith('/auth/login')) {
      return http.Response(
        jsonEncode({
          'access_token': 'test-session',
          'expires_in': 3600,
          'user_id': owner,
          'role': 'patient',
        }),
        200,
      );
    }
    if (path.endsWith('/users/me')) {
      return http.Response(
        jsonEncode({
          'id': owner,
          'role': 'patient',
          'safety_accepted': accepted,
        }),
        200,
      );
    }
    if (path.endsWith('/auth/logout')) {
      logoutSent.complete();
      return logoutResponse?.future ?? http.Response('', 204);
    }
    if (request.method != 'GET') {
      writes++;
      throw TimeoutException('uncertain synthetic write');
    }
    gets++;
    if (pending != null) return pending!.future;
    if (failure != null) throw failure!;
    if (status != null) {
      return http.Response('private server body must not be shown', status!);
    }
    return http.Response(
      jsonEncode(path.endsWith('/routine/entries') ? [r.entry()] : []),
      200,
    );
  }

  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient(call));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  final failures = <Object, RequestFailureKind>{
    TimeoutException('secret'): RequestFailureKind.timeout,
    const SocketException('DNS private'): RequestFailureKind.connection,
    http.ClientException('private URL'): RequestFailureKind.connection,
    const FormatException('patient payload'): RequestFailureKind.invalid,
    StateError('token secret'): RequestFailureKind.unknown,
  };
  for (final pair in failures.entries) {
    test(
      'request classification ${pair.key.runtimeType} hides sensitive details',
      () {
        final failure = RequestFailure.from(pair.key);
        expect(failure.kind, pair.value);
        expect(failure.toString(), isNot(contains('secret')));
        expect(failure.toString(), isNot(contains('private')));
        expect(failure.toString(), isNot(contains('patient payload')));
      },
    );
  }
  for (final code in [401, 403, 429, 500, 503, 422]) {
    test('HTTP $code is a distinct failed request, never offline proof', () {
      expect(RequestFailure.http(code).kind, switch (code) {
        401 => RequestFailureKind.session,
        403 => RequestFailureKind.denied,
        429 => RequestFailureKind.rateLimited,
        >= 500 => RequestFailureKind.server,
        _ => RequestFailureKind.rejected,
      });
    });
  }
  for (final mode in [
    'DNS',
    'connection',
    'timeout',
    '403',
    '429',
    '500',
    '503',
    'invalid',
  ]) {
    test(
      'routine $mode retains previous confirmation, then GET recovery',
      () async {
        final wire = Wire();
        await wire.run(() async {
          await p.login();
          final c = RoutineController(RemoteRoutineRepository());
          await c.refresh();
          final confirmed = c.lastConfirmedAt;
          wire.failure = switch (mode) {
            'DNS' => const SocketException('DNS'),
            'connection' => http.ClientException('offline transport'),
            'timeout' => TimeoutException('synthetic'),
            'invalid' => const FormatException('synthetic'),
            _ => null,
          };
          wire.status = int.tryParse(mode);
          await c.refresh();
          expect(c.stale, true);
          expect(c.entries!.single['id'], 'entry');
          expect(c.lastConfirmedAt, confirmed);
          expect(c.readFailure, isNotNull);
          expect(c.error, isNot(contains('private server body')));
          expect(await c.write('entries', {'schedule': 'AM'}), false);
          final before = wire.gets;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          expect(
            wire.gets,
            before,
          ); // No auto retry/backoff loop or POST replay.
          wire.failure = null;
          wire.status = null;
          await c.refresh();
          expect(c.stale, false);
          expect(c.readFailure, isNull);
          expect(wire.writes, 0);
          c.dispose();
        });
      },
    );
  }
  for (final resource in ['routine', 'experiments', 'products']) {
    test(
      '$resource ignores duplicate concurrent refresh without extra GET',
      () async {
        final wire = Wire();
        await wire.run(() async {
          await p.login();
          wire.pending = Completer();
          final dynamic c = switch (resource) {
            'routine' => RoutineController(RemoteRoutineRepository()),
            'experiments' => ExperimentController(RemoteExperimentRepository()),
            _ => ProductsController(RemoteProductRepository()),
          };
          Future<void> refresh() async {
            if (resource == 'products') {
              await c.load();
            } else {
              await c.refresh();
            }
          }

          final first = refresh();
          await Future<void>.delayed(Duration.zero);
          await Future.wait(List.generate(10, (_) => refresh()));
          expect(wire.gets, 1);
          final wait = wire.pending!;
          wire.pending = null;
          wait.complete(http.Response('[]', 200));
          await first;
          expect(wire.gets, resource == 'routine' ? 2 : 1);
          expect(wire.writes, 0);
          c.dispose();
        });
      },
    );
  }
  test(
    'uncertain adherence survives successful GET and is not replayed',
    () async {
      final wire = Wire();
      await wire.run(() async {
        await p.login();
        final c = RoutineController(RemoteRoutineRepository());
        await c.refresh();
        final payload = {
          'routine_entry_id': 'entry',
          'date': '2026-10-02',
          'slot': 'AM',
          'status': 'completed',
        };
        expect(await c.write('adherence', payload), false);
        await c.refresh();
        expect(c.stale, false);
        expect(c.uncertain, contains(c.writeKey('adherence', payload)));
        expect(c.history, isEmpty);
        expect(await c.write('adherence', payload), false);
        expect(wire.writes, 1);
        c.dispose();
      });
    },
  );
  for (final mode in [
    'logout',
    'switch account',
    'old 401',
    'current 401',
    'revoke',
    'dispose',
  ]) {
    test('late recovery $mode cannot restore an old routine/session', () async {
      final wire = Wire();
      await wire.run(() async {
        await p.login();
        final c = RoutineController(RemoteRoutineRepository());
        await c.refresh();
        wire.pending = Completer();
        final read = c.refresh();
        await Future<void>.delayed(Duration.zero);
        if (mode == 'logout') await api.logout();
        if (mode == 'switch account' || mode == 'old 401') {
          await api.init();
          wire.owner = 'patient-b';
          await p.login();
        }
        if (mode == 'revoke') {
          wire.accepted = false;
          await api.readSafetyAcceptance();
        }
        if (mode == 'dispose') c.dispose();
        wire.pending!.complete(
          http.Response(
            jsonEncode([r.entry()]),
            mode.contains('401') ? 401 : 200,
          ),
        );
        await read;
        if (mode != 'dispose') {
          expect(c.entries, isNull);
          expect(c.lastConfirmedAt, isNull);
          expect(c.readFailure, isNull);
        }
        if (mode == 'old 401' || mode == 'switch account') {
          expect(api.observationOwner, 'patient-b');
          expect(api.isAuthenticated, true);
        }
        if (mode == 'current 401' || mode == 'logout') {
          expect(api.isAuthenticated, false);
        }
        if (mode == 'revoke') expect(api.hasConfirmedSafetyAcceptance, false);
        expect(wire.writes, 0);
        if (mode != 'dispose') c.dispose();
      });
    });
  }
  test('old logout 401 with reused token does not clear account B', () async {
    final wire = Wire()..logoutResponse = Completer();
    await wire.run(() async {
      await p.login();
      final logout = api.logout();
      await wire.logoutSent.future;
      expect(api.isAuthenticated, false);
      wire.owner = 'patient-b';
      await p.login();
      final generation = api.sessionGeneration;
      wire.logoutResponse!.complete(http.Response('', 401));
      await logout;
      expect(api.sessionGeneration, generation);
      expect(api.observationOwner, 'patient-b');
      expect(api.hasConfirmedSafetyAcceptance, true);
    });
  });
  test(
    'current authenticated 401 invalidates before an unconsumed stalled body',
    () async {
      var consumed = false;
      final client = MockClient.streaming((request, body) async {
        expect(request.url.host, 'flutter-tests.invalid');
        if (request.url.path.endsWith('/auth/login')) {
          return http.StreamedResponse(Stream.value(p.auth().bodyBytes), 200);
        }
        if (request.url.path.endsWith('/users/me')) {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                '{"id":"patient-1","role":"patient","safety_accepted":true}',
              ),
            ),
            200,
          );
        }
        Stream<List<int>> stalled() async* {
          consumed = true;
          await Completer<void>().future;
        }

        return http.StreamedResponse(stalled(), 401);
      });
      await http.runWithClient(() async {
        await p.login();
        await expectLater(
          api.patientResource('routine/entries', api.sessionGeneration),
          throwsA(isA<RequestFailure>()),
        );
        expect(api.isAuthenticated, false);
        expect(consumed, false);
      }, () => client);
    },
  );
}
