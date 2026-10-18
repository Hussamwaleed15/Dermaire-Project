import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import 'inbox_models.dart';

class InboxController extends PrivateController {
  final _notices = <InboxNotice>[];
  final _history = <NoticeHistory>[];
  String? next, nextHistory;
  String? outcome;
  List<InboxNotice> get notices => current ? List.unmodifiable(_notices) : [];
  List<NoticeHistory> get history => current ? List.unmodifiable(_history) : [];
  int get unreadLoaded => notices.where((n) => n.read == null).length;
  @override
  void wipe() {
    _notices.clear();
    _history.clear();
    next = null;
    nextHistory = null;
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      await readPage(ticket);
      if (valid(ticket)) await readHistory(ticket);
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
    final data = object(
      (await api.integrationResource(
        'notifications',
        generation,
        query: {'limit': '50', 'before': ?before},
      )).data,
    );
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
    final ids = _notices.map((n) => n.id).toSet();
    if (rows.any((n) => !ids.add(n.id)) || cursor != null && cursor == before) {
      throw const FormatException('Changed inbox pages');
    }
    _notices.addAll(rows);
    next = cursor;
  }

  Future<void> readHistory(int ticket, {String? before}) async {
    final data = object(
      (await api.integrationResource(
        'notifications/history',
        generation,
        query: {'limit': '50', 'before': ?before},
      )).data,
    );
    if (data['history_contract'] !=
        'prospective_attempts_and_current_authority_no_delivery_proof') {
      throw const FormatException('Unverified history authority');
    }
    final rows = (data['items'] as List)
        .map((e) => NoticeHistory(object(e)))
        .toList();
    final cursor = data['next_before'] == null
        ? null
        : resourceId(data['next_before']);
    if (!valid(ticket)) return;
    final ids = _history.map((n) => n.id).toSet();
    if (rows.any((n) => !ids.add(n.id)) || cursor != null && cursor == before) {
      throw const FormatException('Changed history pages');
    }
    _history.addAll(rows);
    nextHistory = cursor;
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
        await readHistory(ticket, before: cursor);
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

  Future<bool> mark(InboxNotice notice, {required bool read}) async {
    if (!current || busy || !notices.any((n) => n.id == notice.id)) {
      return false;
    }
    final ticket = begin();
    try {
      final receipt = object(
        (await api.integrationResource(
          'notifications/${notice.id}/${read ? 'read' : 'unread'}',
          generation,
          method: 'PUT',
        )).data,
      );
      if (receipt['id'] != notice.id ||
          receipt['delivery_confirmed'] != false ||
          (read
              ? (receipt['receipt'] != 'app_read_acknowledged' ||
                    receipt['read_at'] == null)
              : (receipt['unread'] != true || receipt['read_at'] != null))) {
        throw const FormatException('Unverified read receipt');
      }
      if (!valid(ticket)) return false;
      wipe();
      await readPage(ticket);
      if (!valid(ticket)) return false;
      final currentRow = _notices.where((n) => n.id == notice.id).firstOrNull;
      if (currentRow == null || (currentRow.read != null) != read) {
        throw const FormatException('Read state changed; refresh');
      }
      await readHistory(ticket);
      if (!valid(ticket)) return false;
      outcome =
          'Current app read state confirmed. Device delivery is unconfirmed.';
      return true;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
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
    final ticket = begin();
    wipe();
    try {
      final v = await read();
      if (!valid(ticket)) return;
      if (_seenRevision != null && v.revision < _seenRevision!) {
        throw const FormatException('Stale settings');
      }
      _seenRevision = v.revision;
      _value = v;
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
      api.integrationIntents.remove(intentId);
    } else {
      error =
          'The previous update is unconfirmed. Refresh or explicitly retry the same settings; a conflicting revision will be rejected.';
    }
  }

  Future<void> disableAll() async {
    if (!canDisable) return;
    final ticket = begin(), expected = _seenRevision!;
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
      _seenRevision = receipt.revision;
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
      final latest = await read();
      if (!valid(ticket)) return false;
      if (latest.revision < receipt.revision) {
        throw const FormatException('Stale settings readback');
      }
      _seenRevision = latest.revision;
      _value = latest;
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
