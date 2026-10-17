/// Versioned server consent takes precedence over the legacy Boolean.
class ServerEntryMetadata {
  ServerEntryMetadata.fromApi(Map<String, dynamic> user) {
    accepted = user['safety_accepted'] == true;
    if (user.containsKey('safety_consent')) {
      final value = user['safety_consent'];
      if (value is! Map ||
          value['schema_version'] != 1 ||
          ![
            'missing',
            'current',
            'outdated',
            'unknown',
          ].contains(value['state']) ||
          value['acceptance_required'] is! bool ||
          value['required_version'] is! String ||
          !RegExp(r'^[0-9]+\.[0-9]+$').hasMatch(value['required_version']) ||
          (value['required_version'] as String).length > 20) {
        throw const FormatException('Unverified safety policy');
      }
      requiredPolicy = value['required_version'] as String;
      accepted =
          accepted &&
          value['state'] == 'current' &&
          value['acceptance_required'] == false &&
          value['accepted_version'] == requiredPolicy;
      if (accepted) {
        final at = DateTime.tryParse(value['accepted_at']?.toString() ?? '');
        if (at == null || at.isAfter(DateTime.now().toUtc())) {
          throw const FormatException('Unverified policy receipt');
        }
      }
    }
    if (user.containsKey('onboarding')) {
      final value = user['onboarding'];
      if (value is! Map ||
          value['schema_version'] != 1 ||
          ![
            'never_reviewed',
            'reviewed',
            'not_applicable',
          ].contains(value['review_state'])) {
        throw const FormatException('Unverified profile review');
      }
      if (value['review_state'] == 'reviewed' &&
          DateTime.tryParse(value['reviewed_at']?.toString() ?? '') == null) {
        throw const FormatException('Unverified profile review timestamp');
      }
      profileReviewRequired =
          user['role'] == 'patient' &&
          value['review_state'] == 'never_reviewed';
    }
  }
  late bool accepted;
  String? requiredPolicy;
  bool profileReviewRequired = false;
}
