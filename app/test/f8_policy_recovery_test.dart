import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dermaire_app/entry/verified_policy.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> metadata() => {
  'schema_version': 1,
  'required_version': '2.0',
  'enforcement_enabled': false,
  'document_status': 'approved',
  'acceptance_ready': true,
  'document': {
    'url': 'https://flutter-tests.invalid/policy',
    'sha256': sha256.convert(utf8.encode('Reviewed policy bytes')).toString(),
  },
};
void main() {
  test(
    'verified policy preserves exact bytes/version and sends no credentials',
    () async {
      final policy = await PolicyMetadata(metadata()).download(
        MockClient((r) async {
          expect(r.url.host, 'flutter-tests.invalid');
          expect(r.headers.containsKey('Authorization'), false);
          expect(r.followRedirects, false);
          return http.Response(
            'Reviewed policy bytes',
            200,
            headers: {'content-type': 'text/plain; charset=utf-8'},
          );
        }),
      );
      expect(policy.version, '2.0');
      expect(policy.document, 'Reviewed policy bytes');
    },
  );
  for (final mode in ['digest', 'redirect', 'html', 'size', 'malformed']) {
    test('policy refuses $mode without acceptance', () async {
      final m = metadata();
      if (mode == 'malformed') m['schema_version'] = 2;
      Future<void> attempt() async {
        await PolicyMetadata(m).download(
          MockClient(
            (r) async => http.Response(
              mode == 'digest'
                  ? 'changed'
                  : mode == 'size'
                  ? 'x' * 262145
                  : 'Reviewed policy bytes',
              mode == 'redirect' ? 302 : 200,
              headers: {
                'content-type': mode == 'html' ? 'text/html' : 'text/plain',
                if (mode == 'size') 'content-length': '999999',
              },
            ),
          ),
        );
      }

      await expectLater(attempt(), throwsA(anything));
    });
  }
  test('unavailable policy is blocked, never synthesized', () async {
    final m = metadata()
      ..['document_status'] = 'unavailable'
      ..['acceptance_ready'] = false
      ..['document'] = null;
    await expectLater(
      PolicyMetadata(
        m,
      ).download(MockClient((_) async => throw StateError('No HTTP'))),
      throwsA(anything),
    );
  });
  for (final code in ['1234567', '123456789', '１２３４５６７８', 'abcdefgh']) {
    test('reset rejects non-eight-ASCII code $code before network', () async {
      await http.runWithClient(
        () async => expectLater(
          ApiService.instance.resetPassword(
            email: 'test@example.invalid',
            token: code,
            newPassword: ' valid password ',
          ),
          throwsA(anything),
        ),
        () => MockClient((_) async => throw StateError('No HTTP')),
      );
    });
  }
  test('forgot response discards token/debug/account text', () async {
    await http.runWithClient(
      () async {
        final result = await ApiService.instance.forgotPassword(
          email: 'test@example.invalid',
        );
        expect(result.keys, ['message']);
        expect(result.toString(), isNot(contains('secret')));
      },
      () => MockClient((r) async {
        expect(r.url.host, 'flutter-tests.invalid');
        return http.Response(
          '{"message":"registered secret","reset_token":"secret","note":"secret"}',
          200,
        );
      }),
    );
  });
  test('new reset password whitespace is not mutated', () async {
    await http.runWithClient(
      () async {
        await ApiService.instance.resetPassword(
          email: 'test@example.invalid',
          token: '12345678',
          newPassword: ' password ',
        );
      },
      () => MockClient((r) async {
        expect(r.url.host, 'flutter-tests.invalid');
        expect(jsonDecode(r.body)['new_password'], ' password ');
        return http.Response('{}', 200);
      }),
    );
  });
}
