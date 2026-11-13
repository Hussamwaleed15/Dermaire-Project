import 'package:dermaire_app/agent/server_agent_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wave_agent_test.dart' as fixture;

BrokerAction action(String id, int minute) => BrokerAction({
  ...fixture.AgentWire().action(id, {
    'kind': 'request_checkin',
    'rationale': 'Track tolerance',
  }),
  'previewed_at': DateTime.utc(2026, 11, 13, 0, minute).toIso8601String(),
  'preview_valid_until': DateTime.utc(
    2026,
    11,
    13,
    0,
    minute + 5,
  ).toIso8601String(),
});
void main() {
  test('doctor cursor order uses timestamp before id', () {
    expect(
      () => verifyAgentRequestOrder([action('a', 2), action('z', 1)]),
      returnsNormally,
    );
  });
  test('doctor cursor refuses id-descending but time-ascending rows', () {
    expect(
      () => verifyAgentRequestOrder([action('z', 1), action('a', 2)]),
      throwsFormatException,
    );
  });
  test('doctor cursor equal timestamps require descending ids', () {
    expect(
      () => verifyAgentRequestOrder([action('z', 1), action('a', 1)]),
      returnsNormally,
    );
    expect(
      () => verifyAgentRequestOrder([action('a', 1), action('z', 1)]),
      throwsFormatException,
    );
  });
  test('doctor cursor refuses duplicate tuple', () {
    expect(
      () => verifyAgentRequestOrder([action('a', 1), action('a', 1)]),
      throwsFormatException,
    );
  });
}
