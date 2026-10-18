import 'package:flutter_test/flutter_test.dart' show wrapMatcher;

/// The same Matcher predicates as expect(), without WidgetTester guard/Invoker
/// context. Fake server callbacks can run in native frame Zones. Failed contracts
/// still throw and fail the test; actual payloads/keys are never logged.
void expectContract(Object? actual, Object? expected) {
  if (!wrapMatcher(expected).matches(actual, <Object?, Object?>{})) {
    throw StateError('Synthetic HTTP contract mismatch');
  }
}
