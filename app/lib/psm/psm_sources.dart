import '../clinical/clinical_models.dart';
import 'psm_models.dart';

class PsmContextDay {
  PsmContextDay(Map<String, dynamic> d)
    : id = psmId(d['id']),
      date = text(d['date']),
      unusualConditions = optionalFlag(d['unusual_conditions']),
      freshness = PsmFreshness.fromApi(object(d['freshness'])) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw const FormatException('Unsupported context date');
    }
  }
  final String id, date;
  final bool? unusualConditions;
  final PsmFreshness freshness;
}

class PsmRoutineEntry {
  PsmRoutineEntry(Map<String, dynamic> d)
    : id = psmId(d['id']),
      product = psmId(d['product_id']),
      schedule = psmChoice(d['schedule'], ['AM', 'PM', 'BOTH']),
      frequency = text(d['frequency']),
      start = text(d['start_date']),
      freshness = PsmFreshness.fromApi(object(d['freshness']));
  final String id, product, schedule, frequency, start;
  final PsmFreshness freshness;
}

class PsmRoutineEvidence {
  PsmRoutineEvidence(Map<String, dynamic> d)
    : entries = List.unmodifiable(
        psmList(
          d['configured'],
          limit: 100,
        ).map((v) => PsmRoutineEntry(object(v))),
      ) {
    if (d['category'] != 'patient_reported') {
      throw const FormatException('Unsupported routine source');
    }
    history = List.unmodifiable(
      psmList(
        d['historical_snapshots'] ?? [],
        limit: 100,
      ).map((v) => PsmRoutineHistory(object(v))),
    );
    final a = object(d['adherence']);
    if (a['category'] != 'deterministic_derived' ||
        a['source'] != 'user_reported') {
      throw const FormatException('Unsupported adherence source');
    }
    expected = count(a['expected_known_slots']);
    reported = count(a['reported_slots']);
    completed = count(a['completed_slots']);
    unknown = count(a['unknown_slots']);
    window = count(a['window_days']);
    if (completed > reported ||
        unknown != (expected - reported).clamp(0, expected) ||
        window < 1) {
      throw const FormatException('Inconsistent adherence counts');
    }
    freshness = PsmFreshness.fromApi(object(a['freshness']));
    caveats = psmTexts(a['caveats']);
  }
  final List<PsmRoutineEntry> entries;
  late final List<PsmRoutineHistory> history;
  late final int expected, reported, completed, unknown, window;
  late final PsmFreshness freshness;
  late final List<String> caveats;
}

class PsmProductEvidence {
  PsmProductEvidence(Map<String, dynamic> d)
    : id = psmId(d['product_id']),
      completeness = psmChoice(d['data_completeness'], [
        'complete',
        'incomplete',
      ]),
      unknowns = psmTexts(d['unknowns']),
      freshness = PsmFreshness.fromApi(object(d['freshness'])) {
    if (d['category'] != 'deterministic_derived') {
      throw const FormatException('Unsupported product source');
    }
  }
  final String id, completeness;
  final List<String> unknowns;
  final PsmFreshness freshness;
}

class PsmRoutineHistory {
  PsmRoutineHistory(Map<String, dynamic> d)
    : id = psmId(d['id']),
      entry = psmId(d['entry_id']),
      date = text(d['date']),
      slot = psmChoice(d['slot'], ['AM', 'PM']),
      status = psmChoice(d['status'], ['completed', 'skipped']),
      recorded = timestamp(d['recorded_at']),
      product = optionalText(object(d['configuration'])['product_id']) {
    if (d['category'] != 'patient_reported') {
      throw const FormatException('Unsupported historical routine source');
    }
  }
  final String id, entry, date, slot, status;
  final String? product;
  final DateTime recorded;
}

class PsmProductWarning {
  PsmProductWarning(Map<String, dynamic> d)
    : key = text(d['key']),
      severity = psmChoice(d['severity'], ['info', 'caution']),
      explanation = text(d['explanation']),
      confidence = psmChoice(d['confidence'], [
        'unknown',
        'low',
        'medium',
        'high',
      ]),
      limitations = psmTexts(d['limitations']),
      products = List.unmodifiable(
        psmList(
          d['evidence'],
          limit: 100,
        ).map((v) => psmId(object(v)['product_id'])),
      ) {
    if (products.isEmpty) {
      throw const FormatException('Missing warning source references');
    }
  }
  final String key, severity, explanation, confidence;
  final List<String> limitations, products;
}
