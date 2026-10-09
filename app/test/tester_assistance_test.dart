import 'dart:convert';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('assistance uses contextual endpoint and validates contract', () async {
    final result = await http.runWithClient(
      () => ApiService.instance.requestAssistance('What should I track?'),
      () => MockClient((request) async {
        expect(request.url.path, '/api/v1/assistance');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'message': 'What should I track?'});
        return http.Response(
          jsonEncode({
            'schema_version': 'contextual-ai-1.0',
            'message': 'Track changes.',
            'metadata': {'availability': 'disabled', 'mode': 'degraded'},
          }),
          200,
        );
      }),
    );
    expect(result['metadata']['availability'], 'disabled');
  });
  for (final code in [404, 422, 503]) {
    test('assistance $code never surfaces raw response', () async {
      await http.runWithClient(
        () => expectLater(
          ApiService.instance.requestAssistance('question'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'safe error',
              'Assistance unavailable (status $code)',
            ),
          ),
        ),
        () => MockClient(
          (_) async => http.Response('private server trace', code),
        ),
      );
    });
  }
}
