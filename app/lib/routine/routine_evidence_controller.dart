import '../integration/contract.dart';
import '../integration/private_view.dart';
import 'routine_evidence.dart';

class RoutineEvidenceController extends PrivateController {
  RoutineEvidenceController({this.entry}) {
    if (entry != null) resourceId(entry);
  }
  final String? entry;
  @override
  bool get current => super.current && role == 'patient';
  final _events = <RoutineConfigurationEvent>[];
  RoutineEvidencePage? _page;
  RoutineCalendarPolicy? _policy;
  String? outcome;
  static const intentId = 'routine:calendar-policy';
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents[intentId] : null;
  List<RoutineConfigurationEvent> get events =>
      current ? List.unmodifiable(_events) : [];
  RoutineEvidencePage? get page => current ? _page : null;
  RoutineCalendarPolicy? get policy => current ? _policy : null;
  bool get more => current && _page?.next != null && _events.length < 1000;
  @override
  void wipe() {
    _events.clear();
    _page = null;
    _policy = null;
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final results = await Future.wait([
        api.routineEvidence(
          'configuration-history',
          generation,
          query: {'limit': '100', 'routine_entry_id': ?entry},
        ),
        api.routineEvidence('calendar-policy', generation),
      ]);
      final history = RoutineEvidencePage.parse(
        results[0].data,
        owner,
        entry: entry,
      );
      final calendar = RoutineCalendarPolicy.parse(results[1].data);
      if (!valid(ticket)) return;
      _page = history;
      _events.addAll(history.items);
      _policy = calendar;
      final original = pending;
      if (original != null &&
          calendar.revision > (original.body['expected_revision'] as int)) {
        // Actual source serializes PUT under the same account lock and CAS. A
        // newer committed revision fences that old precondition. This is not an
        // original receipt or proof the user's earlier request was the winner.
        api.integrationIntents.remove(intentId);
        outcome =
            'Current policy verified. The previous precondition is superseded; its original outcome is not independently receipted.';
      }
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> loadMore() async {
    if (!more || busy) return;
    final before = _page!, ticket = begin();
    try {
      final raw = await api.routineEvidence(
        'configuration-history',
        generation,
        query: {
          'limit': '100',
          'cursor': before.next!,
          'routine_entry_id': ?entry,
        },
      );
      final next = RoutineEvidencePage.parse(raw.data, owner, entry: entry);
      if (!valid(ticket)) return;
      if (next.asOf != before.asOf ||
          next.next != null && next.next == before.next ||
          next.items.any((e) => _events.any((old) => old.id == e.id)) ||
          _events.isNotEmpty &&
              next.items.isNotEmpty &&
              !RoutineEvidencePage.ordered(_events.last, next.items.first)) {
        throw const FormatException('History changed; start a fresh read');
      }
      _events.addAll(next.items);
      _page = next;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> changeZone(String zone, {bool retryOriginal = false}) async {
    if (!current || busy || _policy == null) return;
    try {
      calendarZone(zone);
    } catch (e) {
      error = integrationError(e);
      notifyListeners();
      return;
    }
    final retained = pending;
    if (retained == null && zone == _policy!.zone) {
      outcome = 'This timezone is already current. No update was sent.';
      notifyListeners();
      return;
    }
    if (retained != null && !retryOriginal) return;
    if (retryOriginal &&
        (retained == null || retained.body['timezone'] != zone)) {
      return;
    }
    if (retained == null &&
        api.quarantinedOperations.any(
          (i) => i.path == 'routine/calendar-policy',
        )) {
      error = QuarantinedOperationFailure().message;
      notifyListeners();
      return;
    }
    final op =
        retained ??
        PendingIntent(
          path: 'routine/calendar-policy',
          attemptPath: '',
          method: 'PUT',
          body: {'timezone': zone, 'expected_revision': _policy!.revision},
        );
    api.integrationIntents[intentId] = op;
    final wasUncertain = op.uncertain, ticket = begin();
    outcome = null;
    try {
      final accepted = RoutineCalendarPolicy.parse(
        (await api.routineEvidence(
          'calendar-policy',
          generation,
          method: 'PUT',
          body: op.body,
        )).data,
      );
      if (!valid(ticket)) return;
      if (accepted.zone != zone ||
          accepted.revision <= (op.body['expected_revision'] as int)) {
        throw const FormatException('Calendar response unconfirmed');
      }
      final fresh = RoutineCalendarPolicy.parse(
        (await api.routineEvidence('calendar-policy', generation)).data,
      );
      if (!valid(ticket)) return;
      if (fresh.revision < accepted.revision ||
          fresh.revision == accepted.revision && fresh.zone != accepted.zone) {
        throw const FormatException('Stale calendar readback');
      }
      _policy = fresh;
      api.integrationIntents.remove(intentId);
      outcome = fresh.revision == accepted.revision
          ? 'Timezone policy confirmed by the server. Existing UTC reports and reminders are unchanged.'
          : 'The accepted change is historical; a newer current policy is shown.';
    } catch (e) {
      if (valid(ticket)) {
        if (!wasUncertain &&
            e is IntegrationFailure &&
            [400, 403, 404, 409, 412, 422, 428].contains(e.status)) {
          api.integrationIntents.remove(intentId);
        } else {
          op.uncertain = true;
        }
        if (e is IntegrationFailure && [401, 403, 404].contains(e.status)) {
          wipe();
        }
        _policy = null;
        error =
            'Timezone change unconfirmed. Refresh current policy before another edit. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }
}
