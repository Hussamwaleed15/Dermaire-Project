import '../clinical/clinical_models.dart';
import '../integration/contract.dart';

const noticeKinds = [
  'message',
  'follow_up',
  'comparison',
  'routine',
  'agent_request',
];

class InboxNotice {
  InboxNotice(Map<String, dynamic> v)
    : id = resourceId(v['id']),
      kind = text(v['kind']),
      source = resourceId(v['source_id']),
      revision = count(v['source_revision']),
      created = timestamp(v['created_at']),
      due = timestamp(v['due_at']),
      read = v['read_at'] == null ? null : timestamp(v['read_at']) {
    if (!noticeKinds.contains(kind) ||
        v['unread'] != (read == null) ||
        v['push_delivery'] != 'unconfirmed') {
      throw const FormatException('Unverified notification');
    }
  }
  final String id, kind, source;
  final int revision;
  final DateTime created, due;
  final DateTime? read;
}

class NoticeHistory {
  NoticeHistory(Map<String, dynamic> v)
    : id = resourceId(v['id']),
      kind = text(v['kind']),
      state = text(v['state']),
      due = timestamp(v['due_at']),
      jobs = List.unmodifiable(
        (v['jobs'] as List).map(
          (j) => Map<String, dynamic>.unmodifiable(object(j)),
        ),
      ) {
    if (!noticeKinds.contains(kind) ||
        !['current', 'cancelled'].contains(state) ||
        v['delivery_confirmed'] != false) {
      throw const FormatException('Invalid notification history');
    }
    for (final j in jobs) {
      resourceId(j['id']);
      text(j['state']);
      count(j['attempts']);
      if (j['attempt_history'] is! List) {
        throw const FormatException('Invalid attempt history');
      }
    }
  }
  final String id, kind, state;
  final DateTime due;
  final List<Map<String, dynamic>> jobs;
}

class NoticeSettings {
  NoticeSettings(Map<String, dynamic> v, {this.reminder = false})
    : revision = count(v['revision']),
      data = Map.unmodifiable(v) {
    if (reminder) {
      if (v['configured'] is! bool || v['enabled'] is! bool) {
        throw const FormatException('Invalid reminder settings');
      }
      if (v['configured'] == false) {
        if (revision != 0 || v['enabled'] != false) {
          throw const FormatException('Invalid default reminder');
        }
        return;
      }
      if (v['gap_policy'] != 'skip' ||
          ![0, 1].contains(v['fold']) ||
          v['calendar_policy'] != 'prospective_fixed_occurrences_v1' ||
          v['live_delivery'] != 'unavailable') {
        throw const FormatException('Invalid calendar authority');
      }
      timestamp(v['effective_at']);
      minute(v['am_minute']);
      minute(v['pm_minute']);
    } else {
      final kinds = (v['enabled_kinds'] as List).cast<String>();
      if (kinds.toSet().length != kinds.length ||
          kinds.any((k) => !noticeKinds.contains(k)) ||
          v['push_enabled'] is! bool ||
          v['provider'] != 'disabled' ||
          v['actual_delivery'] != 'unavailable') {
        throw const FormatException('Invalid notification preferences');
      }
      minute(v['quiet_start']);
      minute(v['quiet_end']);
    }
    if (v['timezone'] is! String || (v['timezone'] as String).isEmpty) {
      throw const FormatException('Missing timezone');
    }
  }
  final bool reminder;
  final int revision;
  final Map<String, dynamic> data;
  bool matches(Map<String, dynamic> body) => body.entries
      .where((e) => e.key != 'expected_revision')
      .every(
        (e) => e.value is List
            ? (data[e.key] is List &&
                  (data[e.key] as List).length == (e.value as List).length &&
                  (data[e.key] as List).toSet().containsAll(e.value as List))
            : data[e.key] == e.value,
      );
}

int minute(Object? v) {
  if (v is! int || v < 0 || v >= 1440) {
    throw const FormatException('Invalid clock minute');
  }
  return v;
}

String clockMinute(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
int? parseClock(String s) {
  if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return null;
  final a = s.split(':').map(int.parse).toList();
  if (a[0] > 23 || a[1] > 59) return null;
  return a[0] * 60 + a[1];
}
