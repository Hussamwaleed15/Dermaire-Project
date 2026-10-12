import '../capture/guided_photo_disclosure.dart';

/// Fixed English product copy. Independent of device locale, preferences and
/// server account state. User-provided text is not translated or modified.
class EntryCopy {
  const EntryCopy();
  static const english = EntryCopy();
  String get welcome => 'A clearer view of your skin.';
  String get welcomeBody =>
      'Observe changes. Understand your history. Take the next step with more context.';
  String get create => 'Create account';
  String get existing => 'I already have an account';
  String get email => 'Email';
  String get password => 'Password';
  String get confirm => 'Confirm password';
  String get signIn => 'Sign in';
  String get google => 'Continue with Google';
  String get retry => 'Try again';
  String get signOut => 'Sign out / use another account';
  String get checking => 'Confirming your safety acceptance…';
  String get profile => 'Loading your account profile…';
  String get signingIn => 'Signing you in…';
  String get failure => 'We couldn’t complete this step';
  String get authError =>
      'Sign-in failed: please check your details and connection, then try again.';
  String get success => 'You’re ready to continue';
  String get continueApp => 'Continue to Dermaire';
  String get clinicalDisclaimer =>
      'Sign-in confirmation is not a clinical assessment.';
  String get disclosure => guidedPhotoDisclosure;
  String get validEmail => 'Enter a valid email address';
  String get passwordRequired => 'Enter your password';
  String get passwordRules =>
      'Use 8+ characters with upper, lower and a number';
}
