import 'dart:convert';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../home/home_response.dart';
import '../doctor/doctor_connection.dart';
import '../doctor/doctor_evidence_models.dart';
import '../psm/psm_models.dart';
import 'clinical_models.dart';

String canonicalJson(Object? value) {
  Object? order(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: order(v[k])};
    }
    if (v is List) return v.map(order).toList();
    return v;
  }

  return jsonEncode(order(value));
}

class ClinicalSnapshot {
  ClinicalSnapshot(
    Map<String, dynamic> v, {
    required String owner,
    required String role,
    String? grant,
  }) : id = resourceId(v['snapshot_id']),
       patient = resourceId(v['patient_id']),
       asOf = timestamp(v['evaluated_at']),
       home = Map.unmodifiable(object(v['home'])),
       review = Map.unmodifiable(object(v['review'])),
       safety = SafetyAssessment.fromApi(object(v['safety'])),
       limitations = List.unmodifiable((v['limitations'] as List).map(text)) {
    if (v['schema_version'] != (role == 'patient' ? 1 : 2) ||
        !['patient', 'doctor'].contains(role) ||
        (role == 'patient'
            ? patient != owner
            : (v['reader_id'] != owner ||
                  v['reader_role'] != 'doctor' ||
                  v['access_id'] != grant ||
                  grant == null ||
                  v['projection_visibility'] !=
                      'doctor_review_with_patient_home_and_psm')) ||
        v['consistency'] != 'postgresql_repeatable_read_transaction' ||
        v['atomic_scope'] != 'database_rows_visible_in_one_transaction' ||
        v['external_sources'] != 'not_fetched_not_atomic' ||
        v['replayable'] != false ||
        v['clinical_clearance'] != false) {
      throw const FormatException('Unverified clinical snapshot authority');
    }
    final rawModel = object(v['personal_skin_model']);
    model = PersonalSkinModel.fromApi(rawModel, owner: patient);
    if (role == 'patient') {
      patientReview = ClinicianReview.fromApi(review, owner: patient);
    } else {
      DoctorReviewRead.fromApi(review, patient);
    }
    if (review['patient_id'] != patient ||
        safety.evaluatedAt != asOf ||
        timestamp(review['as_of']) != asOf ||
        timestamp(home['as_of']) != asOf ||
        model.generatedAt != asOf ||
        [
          review['safety'],
          home['safety'],
          rawModel['safety'],
        ].any((s) => canonicalJson(s) != canonicalJson(v['safety']))) {
      throw const FormatException('Snapshot sources disagree');
    }
    validateHomeResponse(home, asOf.toUtc().toIso8601String().split('T').first);
    for (final row in home['journal'] as List) {
      if (timestamp(row['created_at'], naiveUtc: true).isAfter(asOf)) {
        throw const FormatException('Future measurement in snapshot');
      }
    }
    final status = object(home['observation_status']);
    if (status['schema_version'] != 1 ||
        status['day_basis'] != 'UTC' ||
        status['today_completed'] is! bool ||
        (status['recent'] as List).length > 2) {
      throw const FormatException('Unverified observation completion');
    }
    observationCompleted = status['today_completed'] as bool;
    final ids = <String>{};
    for (final value in status['recent'] as List) {
      final row = object(value);
      resourceId(row['id']);
      final time = timestamp(row['created_at']);
      if (!ids.add(row['id'] as String) ||
          time.isAfter(asOf) ||
          !['Morning', 'Evening'].contains(row['time_of_day']) ||
          !['report_only', 'report_and_measurement'].contains(row['kind']) ||
          row['measurement_available'] !=
              (row['kind'] == 'report_and_measurement')) {
        throw const FormatException('Unverified observation history');
      }
    }
    final day = home['date'];
    bool sameDay(Object? time, {bool naive = false}) =>
        timestamp(
          time,
          naiveUtc: naive,
        ).toUtc().toIso8601String().split('T').first ==
        day;
    if (observationCompleted &&
        !(status['recent'] as List).any((r) => sameDay(r['created_at']))) {
      throw const FormatException(
        'Observation completion lacks current evidence',
      );
    }
    if (home['today_checked_in'] == true &&
        !(home['journal'] as List).any(
          (r) => sameDay(r['created_at'], naive: true),
        )) {
      throw const FormatException(
        'Measurement completion lacks current evidence',
      );
    }
  }
  final String id, patient;
  final DateTime asOf;
  final Map<String, dynamic> home, review;
  final SafetyAssessment safety;
  final List<String> limitations;
  late final PersonalSkinModel model;
  ClinicianReview? patientReview;
  late final bool observationCompleted;
}

class ClinicalSnapshotController extends PrivateController {
  ClinicalSnapshotController({this.connection})
    : originalGrant = connection?.grant?.id {
    connection?.addListener(connectionChanged);
  }
  final DoctorConnectionController? connection;
  final String? originalGrant;
  ClinicalSnapshot? _value;
  @override
  bool get current =>
      super.current &&
      (role == 'patient'
          ? connection == null
          : connection != null &&
                connection!.confirmed &&
                connection!.parent.generation == generation &&
                originalGrant != null &&
                connection!.grant?.id == originalGrant);
  ClinicalSnapshot? get value => current ? _value : null;
  void connectionChanged() {
    if (!current) {
      revision++;
      wipe();
      busy = false;
      notifyListeners();
    }
  }

  @override
  void wipe() {
    _value = null;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final c = connection;
      if (c != null && (!await c.verifyForRead() || !valid(ticket))) return;
      final data = object(
        (await api.integrationResource(
          c == null
              ? 'clinical-snapshot'
              : 'clinical-snapshot/patients/${resourceId(c.patientId)}',
          generation,
        )).data,
      );
      if (!valid(ticket)) return;
      final value = ClinicalSnapshot(
        data,
        owner: owner,
        role: role,
        grant: originalGrant,
      );
      if (c != null &&
          (value.patient != c.patientId || !await c.verifyForRead())) {
        throw const FormatException('Original patient snapshot grant changed');
      }
      if (!valid(ticket)) return;
      _value = value;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  @override
  void dispose() {
    connection?.removeListener(connectionChanged);
    super.dispose();
  }
}
