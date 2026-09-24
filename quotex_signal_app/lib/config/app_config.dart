/// Deployment-time configuration for the account/license server.
///
/// Fill these in once you've completed the manual setup steps (Google Cloud
/// OAuth client + deploying auth_server.py). See the project README for the
/// checklist. Nothing in the app will work — login will fail immediately —
/// until both are set to real values.
abstract final class AppConfig {
  /// Base URL of the deployed auth_server.py instance, no trailing slash.
  /// e.g. "https://msn-signal-auth.onrender.com"
  static const String authBaseUrl = 'https://REPLACE_WITH_YOUR_AUTH_SERVER_URL';

  /// The "Web application" OAuth Client ID from Google Cloud Console.
  /// Passed to GoogleSignIn as `serverClientId` so the ID token it returns
  /// is audience-scoped to your backend (GOOGLE_CLIENT_ID in auth_server.py
  /// must be this exact value). This is NOT the Android client ID.
  static const String googleServerClientId =
      'REPLACE_WITH_YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
}
