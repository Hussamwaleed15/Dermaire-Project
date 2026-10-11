/// Narrow immutable adapter for the identity and profile fields in UserOut.
class AccountProfile {
  AccountProfile._(
    this.id,
    this.name,
    this.email,
    this.role,
    this.skinType,
    this.selectedGoal,
    this.skinConcerns,
    this.context,
  );

  final String id, name, email, role;
  final String? skinType, selectedGoal;
  final List<String>? skinConcerns;
  final Map<String, dynamic>? context;

  static const contextKeys = {
    'age_band',
    'sex',
    'sensitivities_allergies',
    'dermatologist_care',
    'medications_treatments',
    'primary_goals',
    'hormonal_context',
    'hormonal_disclosure',
    'menstrual_context',
  };
  static const listKeys = {
    'sensitivities_allergies',
    'medications_treatments',
    'primary_goals',
    'hormonal_context',
  };

  factory AccountProfile.fromApi(
    Map<String, dynamic> data, {
    required String owner,
    required String role,
  }) {
    const invalid = FormatException('Account profile could not be verified.');
    if (data['id'] != owner ||
        data['role'] != role ||
        role.isEmpty ||
        data['email'] is! String ||
        (data['email'] as String).trim().isEmpty ||
        data['full_name'] is! String ||
        data['safety_accepted'] is! bool) {
      throw invalid;
    }
    String? optionalText(String key) {
      final value = data[key];
      if (value != null && value is! String) throw invalid;
      return value as String?;
    }

    List<String>? strings(Object? value) {
      if (value == null) return null;
      if (value is! List || !value.every((v) => v is String)) throw invalid;
      return List<String>.unmodifiable(value.cast<String>());
    }

    final raw = data['profile_context'];
    Map<String, dynamic>? context;
    if (raw != null) {
      if (raw is! Map<String, dynamic>) throw invalid;
      context = Map<String, dynamic>.unmodifiable({
        for (final key in contextKeys)
          if (raw.containsKey(key))
            key: listKeys.contains(key)
                ? strings(raw[key])
                : raw[key] == null || raw[key] is String
                ? raw[key]
                : throw invalid,
      });
    }
    return AccountProfile._(
      owner,
      data['full_name'] as String,
      data['email'] as String,
      role,
      optionalText('skin_type'),
      optionalText('selected_goal'),
      strings(data['skin_concerns']),
      context,
    );
  }

  bool get partial =>
      skinType == null ||
      selectedGoal == null ||
      skinConcerns == null ||
      skinConcerns!.isEmpty ||
      context == null;

  Map<String, dynamic> get editorFields => Map.unmodifiable({
    'skin_type': skinType,
    'selected_goal': selectedGoal,
    'skin_concerns': skinConcerns,
    'profile_context': context,
  });
}
