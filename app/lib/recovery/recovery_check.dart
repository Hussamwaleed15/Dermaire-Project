/// Presentation of a completed read, never mutation success or clinical clearance.
enum RecoveryCheckState {
  unknown,
  expired,
  currentRecord,
  reviewRequired,
  permissionUnavailable,
  verificationUnavailable,
}

class RecoveryCheck {
  RecoveryCheck(this.state, this.checkedAt);
  final RecoveryCheckState state;
  final DateTime checkedAt;
  String get label => switch (state) {
    RecoveryCheckState.unknown => 'Original outcome unknown',
    RecoveryCheckState.expired => 'Original receipt expired',
    RecoveryCheckState.currentRecord => 'Receipt and current record checked',
    RecoveryCheckState.reviewRequired => 'Current records need review',
    RecoveryCheckState.permissionUnavailable =>
      'Original authorization unavailable',
    RecoveryCheckState.verificationUnavailable => 'Verification unavailable',
  };
  String get nextStep => switch (state) {
    RecoveryCheckState.unknown =>
      'Check again later. Do not submit a replacement while the original outcome is unknown.',
    RecoveryCheckState.expired =>
      'Review current authorized records. Expiry does not prove that the operation failed.',
    RecoveryCheckState.currentRecord =>
      'The receipt and current read are separate evidence. This check does not remove the retained identity or establish medical clearance.',
    RecoveryCheckState.reviewRequired =>
      'Open current authorized records in the original feature. An older receipt must not replace newer data.',
    RecoveryCheckState.permissionUnavailable =>
      'Return to current account and permission controls. A replacement grant cannot revive original authority.',
    RecoveryCheckState.verificationUnavailable =>
      'Retry verification when the service is available. No clinical change will be sent.',
  };
}
