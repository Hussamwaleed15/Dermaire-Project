import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around the google_sign_in package.
///
/// IMPORTANT: `serverClientId` below must be the **Web application** OAuth
/// client ID from Google Cloud Console (APIs & Services > Credentials) —
/// not the Android client ID. This is what makes the resulting ID token's
/// audience match what the backend verifies against
/// (`settings.GOOGLE_WEB_CLIENT_ID`). The Android client ID is used
/// implicitly behind the scenes by Google Play Services, matched via this
/// app's package name + signing certificate (SHA-1) registered in the
/// Google Cloud project — it isn't referenced directly in code.
class GoogleAuthHelper {
  static const String _webClientId =
      '1042340572793-ss2cemhfub1bod1a8nakitgco1af2540.apps.googleusercontent.com';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId,
    scopes: const ['email', 'profile'],
  );

  /// Shows the native Google account picker and returns a Google ID token
  /// suitable for backend verification, or null if the user cancelled.
  static Future<String?> signInAndGetIdToken() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null; // user dismissed the picker
    final auth = await account.authentication;
    if (auth.idToken == null) {
      throw Exception('Google did not return an ID token for this account.');
    }
    return auth.idToken;
  }

  static Future<void> signOut() => _googleSignIn.signOut();
}
