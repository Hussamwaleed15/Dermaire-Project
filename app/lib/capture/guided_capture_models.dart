import '../clinical/clinical_models.dart' show object, text, timestamp;

class CaptureQualityCheck {
  CaptureQualityCheck.fromApi(Map<String, dynamic> value)
    : status = text(value['status']),
      confidence = text(value['confidence']),
      reason = value['reason'] as String?;
  final String status, confidence;
  final String? reason;
  bool get supported =>
      ['pass', 'fail', 'unknown'].contains(status) &&
      ['measured', 'heuristic', 'unavailable'].contains(confidence);
}

class CaptureQuality {
  CaptureQuality.fromApi(Map<String, dynamic> value)
    : version = text(value['version']),
      decision = text(value['decision']),
      requestFingerprint = text(value['request_fingerprint']),
      reasons = List.unmodifiable((value['reasons'] as List).map(text)),
      limitations = List.unmodifiable((value['limitations'] as List).map(text)),
      checks = Map.unmodifiable(
        object(value['checks']).map(
          (key, v) => MapEntry(key, CaptureQualityCheck.fromApi(object(v))),
        ),
      );
  final String version, decision, requestFingerprint;
  final List<String> reasons, limitations;
  final Map<String, CaptureQualityCheck> checks;
  bool get supported =>
      version == 'capture-quality-1.0' &&
      checks.isNotEmpty &&
      checks.values.every((c) => c.supported);
}

class CaptureProxy {
  CaptureProxy.fromApi(
    Map<String, dynamic> data, {
    required String captureId,
    required String algorithm,
    required String parentStatus,
  }) : key = text(data['key']),
       unit = text(data['unit']),
       status = text(data['status']),
       value = data['value'] as num?,
       measuredAt = timestamp(data['measured_at']),
       limitations = List.unmodifiable(
         (data['limitations'] as List).map(text),
       ) {
    if (!['red_chromaticity_proxy', 'texture_contrast_proxy'].contains(key) ||
        unit != 'fraction_0_to_1' ||
        data['method_version'] != algorithm ||
        data['source_capture_id'] != captureId ||
        status != parentStatus ||
        data['region'] !=
            'fixed_bilateral_cheek_rectangles_from_frontal_face_detector' ||
        (status == 'measured'
            ? value == null ||
                  !value!.isFinite ||
                  value! < 0 ||
                  value! > 1 ||
                  data['reliability'] != 'limited_image_proxy'
            : value != null || data['reliability'] != 'unavailable')) {
      throw const FormatException('Unverified image proxy');
    }
  }
  final String key, unit, status;
  final num? value;
  final DateTime measuredAt;
  final List<String> limitations;
}

class CaptureMeasurement {
  CaptureMeasurement.fromApi(
    Map<String, dynamic> value, {
    required String captureId,
  }) : id = text(value['id']),
       captureId = text(value['capture_id']),
       algorithm = text(value['algorithm_version']),
       status = text(value['status']),
       qualityFingerprint = text(
         object(value['capture_quality'])['request_fingerprint'],
       ),
       measuredAt = timestamp(value['measured_at']),
       metrics = Map.unmodifiable(
         object(value['metrics']).map(
           (key, v) => MapEntry(
             key,
             CaptureProxy.fromApi(
               object(v),
               captureId: captureId,
               algorithm: text(value['algorithm_version']),
               parentStatus: text(value['status']),
             ),
           ),
         ),
       ) {
    if (value['capture_id'] != captureId ||
        algorithm != 'measurement-1.0' ||
        ![
          'measured',
          'insufficient_quality',
          'failed',
          'unavailable',
        ].contains(status) ||
        value['provenance'] !=
            (status == 'unavailable'
                ? 'server_recorded_unavailability'
                : 'server_computed_from_upload_bytes') ||
        object(value['capture_quality'])['decision'] != 'accepted' ||
        object(value['capture_quality'])['version'] != 'capture-quality-1.0' ||
        metrics.length != 2 ||
        !metrics.containsKey('red_chromaticity_proxy') ||
        !metrics.containsKey('texture_contrast_proxy') ||
        metrics.entries.any(
          (e) => e.key != e.value.key || e.value.measuredAt != measuredAt,
        )) {
      throw const FormatException('Unverified measurement');
    }
  }
  final String id, captureId, algorithm, status, qualityFingerprint;
  final DateTime measuredAt;
  final Map<String, CaptureProxy> metrics;
}

class GuidedCaptureRecord {
  GuidedCaptureRecord.fromApi(
    Map<String, dynamic> data, {
    required this.owner,
    this.readback = false,
  }) : id = text(data['id']),
       state = text(data['state']),
       source = text(data['source']),
       view = text(data['view']),
       receivedAt = timestamp(data['received_at']),
       storage = text(data['storage']),
       quality = CaptureQuality.fromApi(object(data['quality'])) {
    final provenance = object(data['provenance']);
    final ref = data['image_reference'];
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
        !['accepted', 'rejected'].contains(state) ||
        quality.decision != state ||
        !['camera', 'upload'].contains(source) ||
        view != 'front' ||
        provenance['timestamp'] != 'server_received_not_camera_time' ||
        provenance['source'] != 'client_reported' ||
        provenance['view'] != 'client_reported' ||
        provenance['quality'] != 'server_computed' ||
        provenance['server_version'] is! String ||
        !['azure_blob', 'not_persisted'].contains(storage) ||
        (storage == 'azure_blob'
            ? ref is! String ||
                  !ref.startsWith('skin_photos/$owner/${owner}_') ||
                  ref.contains(':') ||
                  ref.contains('?') ||
                  ref.contains('#')
            : ref != null) ||
        (state == 'rejected' &&
            (storage != 'not_persisted' || data['measurement'] != null))) {
      throw const FormatException('Unverified capture receipt');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(quality.requestFingerprint)) {
      throw const FormatException('Invalid request fingerprint');
    }
    if (quality.supported &&
        state == 'accepted' &&
        (quality.reasons.isNotEmpty ||
            [
              'resolution',
              'orientation',
              'face',
              'framing',
              'scale',
              'roll',
              'coarse_front_view',
              'sharpness',
              'exposure',
            ].any((key) => quality.checks[key]?.status != 'pass'))) {
      throw const FormatException('Contradictory quality result');
    }
    if (data['measurement'] != null) {
      try {
        final parsed = CaptureMeasurement.fromApi(
          object(data['measurement']),
          captureId: id,
        );
        if (parsed.qualityFingerprint != quality.requestFingerprint) {
          throw const FormatException('Measurement belongs to another upload');
        }
        measurement = parsed;
        measurementUnavailable = false;
      } catch (_) {
        measurement = null;
        measurementUnavailable = true;
      }
    } else {
      measurement = null;
      measurementUnavailable = false;
    }
  }
  final String owner, id, state, source, view, storage;
  final DateTime receivedAt;
  final CaptureQuality quality;
  final bool readback;
  late final CaptureMeasurement? measurement;
  late final bool measurementUnavailable;
  bool get stored => storage == 'azure_blob';
}

enum CaptureWriteFailure { rejected, uncertain }

class GuidedCaptureWriteException implements Exception {
  const GuidedCaptureWriteException(this.failure, {this.candidateId});
  final CaptureWriteFailure failure;
  final String? candidateId;
}
