import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import 'inbox_models.dart';

class InboxController extends PrivateController {
  final _notices = <InboxNotice>[];
  final _history = <NoticeHistory>[];
  String? next, nextHistory;
  String? historyError;
  final Map<String, ({int revision, DateTime? read})> _stateProof = {};
  @override
  void hide() {
    _stateProof.clear();
    super.hide();
  }

  @override
  void sessionChanged() {
    if (!current) _stateProof.clear();
    super.sessionChanged();
  }

  @override
  void dispose() {
    _stateProof.clear();
    super.dispose();
  }

  String? outcome;
  final Set<String> _noticeCursors = {}, _historyCursors = {};
  int get unconfirmedReadChanges => authenticatedCurrent
      ? api.integrationIntents.entries
            .where(
              (e) => e.key.startsWith('notice-state:') && e.value.uncertain,
            )
            .length
      : 0;
  PendingIntent? pendingRead(InboxNotice notice) => authenticatedCurrent
      ? api.integrationIntents['notice-state:${notice.id}']
      : null;
  bool get inboxLimitReached => _notices.length >= 500;
  bool get historyLimitReached => _history.length >= 500;
  List<InboxNotice> get notices => current ? List.unmodifiable(_notices) : [];
  List<NoticeHistory> get history => current ? List.unmodifiable(_history) : [];
  int get unreadLoaded => notices.where((n) => n.read == null).length;
  @override
  void wipe() {
    _noticeCursors.clear();
    _historyCursors.clear();
    _notices.clear();
    _history.clear();
    next = null;
    nextHistory = null;
    historyError = null;
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      await readPage(ticket);
      if (valid(ticket)) await readHistorySafely(ticket);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> readPage(int ticket, {String? before}) async {
    final limit = (500 - _notices.length).clamp(1, 50);
    final data = object(
      (await api.integrationResource(
        'notifications',
        generation,
        query: {'limit': '$limit', 'before': ?before},
      )).data,
    );
    if (data['items'] is! List || (data['items'] as List).length > limit) {
      throw const FormatException('Inbox page exceeds requested bound');
    }
    final rows = (data['items'] as List)
        .map((e) => InboxNotice(object(e)))
        .toList();
    if (data['provider'] != 'disabled' ||
        data['delivery_confirmed'] != false ||
        data['unread_in_page'] != rows.where((n) => n.read == null).length) {
      throw const FormatException('Invalid inbox authority');
    }
    final cursor = data['next_before'] == null
        ? null
        : resourceId(data['next_before']);
    if (!valid(ticket)) return;
    InboxNotice? previous = _notices.lastOrNull;
    for (final row in rows) {
      if (previous != null &&
          !(previous.created.isAfter(row.created) ||
              previous.created == row.created &&
                  previous.id.compareTo(row.id) > 0)) {
        throw const FormatException('Unverified inbox ordering');
      }
      previous = row;
    }
    if (_notices.length + rows.length > 500 ||
        cursor != null && !_noticeCursors.add(cursor)) {
      throw const FormatException('Inbox continuation changed');
    }
    for (final row in rows) {
      final prior = _stateProof[row.id];
      if (prior != null &&
          (row.stateRevision == null ||
              row.stateRevision! < prior.revision ||
              row.stateRevision == prior.revision && row.read != prior.read)) {
        throw const FormatException('Notification read state regressed');
      }
    }
    for (final row in rows) {
      if (row.stateRevision != null) {
        _stateProof[row.id] = (revision: row.stateRevision!, read: row.read);
      }
    }
    final ids = _notices.map((n) => n.id).toSet();
    if (rows.any((n) => !ids.add(n.id)) || cursor != null && cursor == before) {
      throw const FormatException('Changed inbox pages');
    }
    _notices.addAll(rows);
    next = cursor;
  }

  Future<void> readHistory(int ticket, {String? before}) async {
    final limit = (500 - _history.length).clamp(1, 50);
    final data = object(
      (await api.integrationResource(
        'notifications/history',
        generation,
        query: {'limit': '$limit', 'before': ?before},
      )).data,
    );
    if (data['history_contract'] !=
        'prospective_attempts_and_current_authority_no_delivery_proof') {
      throw const FormatException('Unverified history authority');
    }
    if (data['items'] is! List || (data['items'] as List).length > limit) {
      throw const FormatException('History page exceeds requested bound');
    }
    final rows = (data['items'] as List)
        .map((e) => NoticeHistory(object(e)))
        .toList();
    final cursor = data['next_before'] == null
        ? null
        : resourceId(data['next_before']);
    if (!valid(ticket)) return;
    if (_history.length + rows.length > 500 ||
        cursor != null && !_historyCursors.add(cursor)) {
      throw const FormatException('History continuation changed');
    }
    final ids = _history.map((n) => n.id).toSet();
    if (rows.any((n) => !ids.add(n.id)) || cursor != null && cursor == before) {
      throw const FormatException('Changed history pages');
    }
    _history.addAll(rows);
    nextHistory = cursor;
  }

  Future<void> readHistorySafely(int ticket, {String? before}) async {
    try {
      await readHistory(ticket, before: before);
      if (valid(ticket)) historyError = null;
    } catch (e) {
      if (e is IntegrationFailure && [401, 403].contains(e.status)) rethrow;
      if (valid(ticket)) {
        _history.clear();
        _historyCursors.clear();
        nextHistory = null;
        historyError =
            'Transport history is unavailable. Current inbox state is separate. ${integrationError(e)}';
      }
    }
  }

  Future<void> refreshHistory() async {
    if (!current || busy) return;
    final ticket = begin();
    _history.clear();
    _historyCursors.clear();
    nextHistory = null;
    historyError = null;
    try {
      await readHistorySafely(ticket);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> more({bool history = false}) async {
    final cursor = history ? nextHistory : next;
    if (!current ||
        busy ||
        cursor == null ||
        (history ? _history.length : _notices.length) >= 500) {
      return;
    }
    final ticket = begin();
    try {
      if (history) {
        await readHistorySafely(ticket, before: cursor);
      } else {
        await readPage(ticket, before: cursor);
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

  Future<bool> mark(
    InboxNotice notice, {
    required bool read,
    PendingIntent? original,
  }) async {
    if (!current ||
        busy ||
        notice.stateRevision == null ||
        notice.stateRevision! < 1 ||
        !notices.any((n) => identical(n, notice))) {
      return false;
    }
    final intentId = 'notice-state:${notice.id}';
    final prior = pendingRead(notice);
    if (original != null) {
      if (!identical(prior, original) ||
          original.body['expected_revision'] != notice.stateRevision ||
          original.path !=
              'notifications/${notice.id}/${read ? 'read' : 'unread'}') {
        return false;
      }
    } else if (prior != null) {
      if (notice.stateRevision! <= (prior.body['expected_revision'] as int)) {
        error =
            'Original app-read change is unconfirmed. Refresh or explicitly retry its original CAS request.';
        notifyListeners();
        return false;
      }
      if (prior.uncertain) {
        api.integrationIntents['notice-state:unconfirmed:${prior.key}'] = prior;
      }
    }
    final intent =
        original ??
        PendingIntent(
          path: 'notifications/${notice.id}/${read ? 'read' : 'unread'}',
          attemptPath: '',
          method: 'PUT',
          body: {'expected_revision': notice.stateRevision},
        );
    api.integrationIntents[intentId] = intent;
    intent.uncertain = true;
    final ticket = begin();
    try {
      final receipt = object(
        (await api.integrationResource(
          intent.path,
          generation,
          method: 'PUT',
          query: {'expected_revision': '${intent.body['expected_revision']}'},
        )).data,
      );
      if (receipt['id'] != notice.id ||
          receipt['state_revision'] is! int ||
          receipt['state_revision'] < notice.stateRevision! ||
          receipt['delivery_confirmed'] != false ||
          (read
              ? (receipt['receipt'] != 'app_read_acknowledged' ||
                    receipt['read_at'] == null)
              : (receipt['unread'] != true || receipt['read_at'] != null))) {
        throw const FormatException('Unverified read receipt');
      }
      if (authenticatedCurrent &&
          identical(api.integrationIntents[intentId], intent)) {
        intent.uncertain = false;
      }
      if (!valid(ticket)) return false;
      wipe();
      await readPage(ticket);
      if (!valid(ticket)) return false;
      final currentRow = _notices.where((n) => n.id == notice.id).firstOrNull;
      if (currentRow == null ||
          currentRow.stateRevision == null ||
          currentRow.stateRevision! < (receipt['state_revision'] as int) ||
          (currentRow.read != null) != read) {
        throw const FormatException('Read state changed; refresh');
      }
      await readHistorySafely(ticket);
      if (!valid(ticket)) return false;
      if (identical(api.integrationIntents[intentId], intent)) {
        api.integrationIntents.remove(intentId);
      }
      outcome =
          'Current app read state confirmed. Device delivery is unconfirmed.';
      return true;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        if (e is IntegrationFailure && e.status == 412) {
          try {
            await readPage(ticket);
            if (valid(ticket)) await readHistorySafely(ticket);
            if (!valid(ticket)) return false;
          } catch (_) {
            if (valid(ticket)) wipe();
          }
        }
        error =
            'Read state is unconfirmed. Refresh the inbox. ${integrationError(e)}';
      }
      return false;
    } finally {
      finish(ticket);
    }
  }
}

/// CAS settings use exact session-only intent. GET reconciliation never replays a
/// PUT automatically, nor overwrites a newer revision with an old receipt.
class NoticeSettingsController extends PrivateController {
  NoticeSettingsController({this.entryId});
  final String? entryId;
  NoticeSettings? _value;
  int? _seenRevision;
  bool get canDisable =>
      authenticatedCurrent &&
      visible &&
      entryId == null &&
      _seenRevision != null &&
      !busy;
  DateTime? confirmedAt;
  bool get unconfirmedWithdrawal =>
      authenticatedCurrent &&
      api.integrationIntents['settings:withdrawal:$path']?.uncertain == true;
  int get unconfirmedOriginals => authenticatedCurrent
      ? api.integrationIntents.entries
            .where(
              (e) =>
                  e.key.startsWith('settings:unconfirmed:$path:') &&
                  e.value.uncertain,
            )
            .length
      : 0;
  String? outcome;
  String get path => entryId == null
      ? 'notifications/preferences'
      : 'notifications/routine-reminders/${resourceId(entryId)}';
  String get intentId => 'settings:$path';
  NoticeSettings? get value => current ? _value : null;
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents[intentId] : null;
  @override
  void wipe() {
    _value = null;
    outcome = null;
  }

  Future<NoticeSettings> read() async => NoticeSettings(
    object((await api.integrationResource(path, generation)).data),
    reminder: entryId != null,
  );
  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final previous = _value;
    final ticket = begin();
    wipe();
    try {
      final v = await read();
      if (previous != null &&
          previous.revision == v.revision &&
          !v.matches(previous.data)) {
        throw const FormatException('Settings changed at the same revision');
      }
      if (!valid(ticket)) return;
      if (_seenRevision != null && v.revision < _seenRevision!) {
        throw const FormatException('Stale settings');
      }
      _seenRevision = v.revision;
      _value = v;
      confirmedAt = DateTime.now().toUtc();
      resolve(v);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  void resolve(NoticeSettings v) {
    final intent = pending;
    if (intent == null) return;
    final previous = intent.body['expected_revision'] as int;
    if (v.revision > previous) {
      if (v.matches(intent.body)) {
        outcome =
            'Current settings confirmed by the server. Device delivery is unavailable.';
      } else {
        error =
            'Settings changed elsewhere. Review the current settings before a new edit.';
      }
      if (intent.uncertain) {
        api.integrationIntents['settings:unconfirmed:$path:${intent.key}'] =
            intent;
      }
      api.integrationIntents.remove(intentId);
    } else {
      error =
          'The previous update is unconfirmed. Refresh or explicitly retry the same settings; a conflicting revision will be rejected.';
    }
  }

  Future<void> disableAll() async {
    if (!canDisable) return;
    final ticket = begin(), expected = _seenRevision!;
    final slot = 'settings:withdrawal:$path';
    final retained = api.integrationIntents[slot];
    if (retained != null &&
        retained.body['expected_revision'] != expected &&
        retained.uncertain) {
      api.integrationIntents['settings:unconfirmed:$path:${retained.key}'] =
          retained;
    }
    final original =
        retained != null && retained.body['expected_revision'] == expected
        ? retained
        : PendingIntent(
            path: 'notifications/preferences',
            attemptPath: '',
            method: 'DELETE',
            body: {'expected_revision': expected},
          );
    api.integrationIntents[slot] = original;
    original.uncertain = true;
    try {
      final data = object(
        (await api.integrationResource(
          'notifications/preferences',
          generation,
          method: 'DELETE',
          query: {'expected_revision': '$expected'},
          withdrawal: true,
        )).data,
      );
      final receipt = NoticeSettings(data);
      if (!authenticatedCurrent || !visible || ticket != revision) return;
      if (receipt.revision != expected + 1 ||
          receipt.data['push_enabled'] != false ||
          (receipt.data['enabled_kinds'] as List).isNotEmpty) {
        throw const FormatException('Unverified withdrawal');
      }
      original.uncertain = false;
      if (identical(api.integrationIntents[slot], original)) {
        api.integrationIntents.remove(slot);
      }
      _seenRevision = receipt.revision;
      final old = pending;
      if (old != null && old.uncertain) {
        api.integrationIntents['settings:unconfirmed:$path:${old.key}'] = old;
      }
      api.integrationIntents.remove(intentId);
      _value = null;
      outcome =
          'Notification withdrawal acknowledged by the server at revision ${receipt.revision}. Refresh after verifying current safety policy to read current settings.';
    } catch (e) {
      if (authenticatedCurrent && visible && ticket == revision) {
        error = 'Withdrawal is unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> save(Map<String, dynamic> fields) async {
    final v = value;
    if (!current || busy || pending != null || v == null) return false;
    final keys = entryId == null
        ? {
            'enabled_kinds',
            'push_enabled',
            'timezone',
            'quiet_start',
            'quiet_end',
          }
        : {
            'enabled',
            'timezone',
            'am_minute',
            'pm_minute',
            'fold',
            'gap_policy',
          };
    if (fields.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(fields.keys.toSet()).isNotEmpty) {
      return false;
    }
    final intent = PendingIntent(
      path: path,
      attemptPath: path,
      method: 'PUT',
      body: {'expected_revision': v.revision, ...fields},
    );
    api.integrationIntents[intentId] = intent;
    return deliver(intent);
  }

  Future<bool> retryOriginal() async {
    final intent = pending;
    if (intent == null || !current || busy) return false;
    return deliver(intent);
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin();
    try {
      final before = await read();
      if (!valid(ticket)) return false;
      if (_seenRevision != null && before.revision < _seenRevision!) {
        throw const FormatException('Stale settings');
      }
      _seenRevision = before.revision;
      _value = before;
      if (before.revision != intent.body['expected_revision']) {
        resolve(before);
        return outcome != null;
      }
      intent.uncertain = true;
      final receipt = NoticeSettings(
        object(
          (await api.integrationResource(
            path,
            generation,
            method: 'PUT',
            body: intent.body,
          )).data,
        ),
        reminder: entryId != null,
      );
      if (receipt.revision != (intent.body['expected_revision'] as int) + 1 ||
          !receipt.matches(intent.body)) {
        throw const FormatException('Settings receipt mismatch');
      }
      if (authenticatedCurrent && identical(pending, intent)) {
        intent.uncertain = false;
      }
      final latest = await read();
      if (!valid(ticket)) return false;
      if (latest.revision < receipt.revision) {
        throw const FormatException('Stale settings readback');
      }
      _seenRevision = latest.revision;
      _value = latest;
      confirmedAt = DateTime.now().toUtc();
      resolve(latest);
      return outcome != null;
    } catch (e) {
      if (valid(ticket)) {
        _value = null;
        error =
            'Settings are unconfirmed. Read current settings before any new edit. ${integrationError(e)}';
      }
      return false;
    } finally {
      finish(ticket);
    }
  }
}
