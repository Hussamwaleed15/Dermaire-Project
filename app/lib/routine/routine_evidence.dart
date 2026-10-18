import '../clinical/clinical_models.dart' show timestamp;
import '../integration/contract.dart';

String recordedDay(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      DateTime.tryParse(
            '${value}T00:00:00Z',
          )?.toIso8601String().substring(0, 10) !=
          value) {
    throw const FormatException('Invalid recorded day');
  }
  return value;
}

String calendarZone(Object? value) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9_+/-]{0,99}$').hasMatch(value) ||
      value.contains('//')) {
    throw const FormatException('Enter a valid IANA timezone');
  }
  return value;
}

class RoutineConfigurationEvent {
  RoutineConfigurationEvent._(
    this.id,
    this.entry,
    this.product,
    this.kind,
    this.created,
    this.name,
    this.schedule,
    this.active,
    this.revision,
    this.actor,
    this.writer,
  );
  final String id, entry, product, kind, schedule, writer;
  final String? name, actor;
  final DateTime created;
  final bool active;
  final int revision;
  factory RoutineConfigurationEvent.parse(Object? value, String owner) {
    if (value is! Map ||
        value['schema_version'] != 1 ||
        ![
          'created',
          'changed',
          'stopped',
          'product_evidence_changed',
        ].contains(value['kind'])) {
      throw const FormatException('Unsupported routine event');
    }
    final id = resourceId(value['id']),
        entry = resourceId(value['routine_entry_id']),
        product = resourceId(value['source_product_id']);
    final s = value['snapshot'];
    if (s is! Map ||
        s['id'] != entry ||
        s['user_id'] != owner ||
        s['product_id'] != product ||
        s['revision'] is! int ||
        s['revision'] < 1 ||
        s['revision'] > 2147483647 ||
        !['AM', 'PM', 'BOTH'].contains(s['schedule']) ||
        s['active'] is! bool ||
        s['frequency'] != 'daily') {
      throw const FormatException('Wrong configuration event scope');
    }
    final p = s['provenance'], e = s['product_evidence'];
    if (p is! Map ||
        p['owner_id'] != owner ||
        p['source'] != 'committed_configuration_write' ||
        p['day_basis'] != 'UTC' ||
        p['historical_backfill'] != false ||
        p['clinical_validation'] != false ||
        p['writer_operation'] is! String ||
        (p['writer_operation'] as String).length > 100 ||
        e != null &&
            (e is! Map ||
                e['id'] != product ||
                e['name'] is! String ||
                (e['name'] as String).length > 500)) {
      throw const FormatException('Unverified event provenance');
    }
    return RoutineConfigurationEvent._(
      id,
      entry,
      product,
      value['kind'] as String,
      timestamp(value['created_at'], naiveUtc: true),
      e?['name'] as String?,
      s['schedule'] as String,
      s['active'] as bool,
      s['revision'] as int,
      p['actor_id'] == null ? null : resourceId(p['actor_id']),
      p['writer_operation'] as String,
    );
  }
}

class RoutineEvidencePage {
  RoutineEvidencePage._(
    this.asOf,
    this.coverageSince,
    this.latest,
    this.items,
    this.next,
  );
  final DateTime asOf;
  final DateTime? coverageSince, latest;
  final List<RoutineConfigurationEvent> items;
  final String? next;
  factory RoutineEvidencePage.parse(Object? v, String owner, {String? entry}) {
    if (v is! Map ||
        v['schema_version'] != 1 ||
        v['day_basis'] != 'UTC' ||
        v['coverage'] != 'prospective_orm_writes_no_backfill' ||
        v['freshness'] != 'event_history_not_current_state_verification' ||
        v['consistency'] != 'append_only_keyset_cutoff_not_atomic_snapshot' ||
        v['items'] is! List ||
        (v['items'] as List).length > 100) {
      throw const FormatException('Unsupported routine history');
    }
    final asOf = timestamp(v['as_of']);
    final since = v['coverage_since'] == null
        ? null
        : timestamp(v['coverage_since']);
    final latest = v['last_evidence_at'] == null
        ? null
        : timestamp(v['last_evidence_at']);
    if ((since == null) != (latest == null) ||
        since != null && (latest!.isBefore(since) || latest.isAfter(asOf))) {
      throw const FormatException('Inconsistent routine coverage');
    }
    final rows = (v['items'] as List)
        .map((e) => RoutineConfigurationEvent.parse(e, owner))
        .toList();
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (!seen.add(r.id) ||
          entry != null && r.entry != entry ||
          r.created.isAfter(asOf) ||
          since == null ||
          r.created.isBefore(since) ||
          r.created.isAfter(latest!) ||
          i > 0 && !ordered(rows[i - 1], r)) {
        throw const FormatException('Changed routine history order');
      }
    }
    final next = v['next_cursor'];
    if (next != null &&
        (next is! String ||
            !RegExp(r'^[A-Za-z0-9_.-]{1,4096}$').hasMatch(next) ||
            rows.isEmpty)) {
      throw const FormatException('Invalid history continuation');
    }
    return RoutineEvidencePage._(
      asOf,
      since,
      latest,
      List.unmodifiable(rows),
      next as String?,
    );
  }
  static bool ordered(
    RoutineConfigurationEvent a,
    RoutineConfigurationEvent b,
  ) =>
      a.created.isAfter(b.created) ||
      a.created == b.created && a.id.compareTo(b.id) > 0;
}

class RoutineCalendarPolicy {
  RoutineCalendarPolicy._(
    this.revision,
    this.zone,
    this.effective,
    this.localToday,
  );
  final int revision;
  final String zone, localToday;
  final DateTime? effective;
  factory RoutineCalendarPolicy.parse(Object? v) {
    if (v is! Map ||
        v['schema_version'] != 1 ||
        v['revision'] is! int ||
        v['revision'] < 0 ||
        v['revision'] > 2147483647 ||
        v['adherence_day_basis'] != 'UTC' ||
        v['historical_reinterpretation'] != false ||
        v['policy'] != 'forward_only_labels_at_committed_instant' ||
        v['reminder_policy'] != 'explicit_per_reminder_timezone_fold_and_gap') {
      throw const FormatException('Unsupported calendar policy');
    }
    final zone = calendarZone(v['timezone']);
    final effective = v['effective_at'] == null
        ? null
        : timestamp(v['effective_at']);
    if (v['revision'] == 0 && (zone != 'UTC' || effective != null) ||
        v['revision'] > 0 && effective == null) {
      throw const FormatException('Invalid calendar revision');
    }
    return RoutineCalendarPolicy._(
      v['revision'] as int,
      zone,
      effective,
      recordedDay(v['local_today']),
    );
  }
}
