import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// App-level account gate: Gmail sign-in + license-key activation.
///
/// Deliberately separate from [SessionManager], which owns the Quotex
/// *broker* credential. This one owns "is a real, approved person using this
/// app at all" — it talks to auth_server.py, not the broker.
///
/// Storage policy mirrors SessionManager: the JWT session token goes in
/// flutter_secure_storage (Android Keystore AES); email/name/license flag
/// are plain metadata in SharedPreferences so the splash screen can decide
/// where to route without an async secure-storage read on every cold start.
class AccountManager {
  AccountManager._internal();
  static final AccountManager instance = AccountManager._internal();

  static const String _kSessionToken = 'acct_session_token';
  static const String _kEmail = 'acct_email';
  static const String _kName = 'acct_name';
  static const String _kIsLicensed = 'acct_is_licensed';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;

  String? _sessionToken;
  String? _email;
  String? _name;
  bool _isLicensed = false;

  bool get isSignedIn => _sessionToken != null && _sessionToken!.isNotEmpty;
  bool get isLicensed => _isLicensed;
  String? get email => _email;
  String? get name => _name;

  /// Call once in main() before runApp(), same pattern as SessionManager.
  Future<void> initialize() async {
    try {
      await _googleSignIn.initialize(
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleInitialized = true;
    } catch (e) {
      debugPrint('[ACCOUNT] GoogleSignIn.initialize error: ${e.runtimeType}');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _email = prefs.getString(_kEmail);
      _name = prefs.getString(_kName);
      _isLicensed = prefs.getBool(_kIsLicensed) ?? false;
      _sessionToken = await _secure.read(key: _kSessionToken);
      debugPrint(
        '[ACCOUNT] loaded signedIn=$isSignedIn licensed=$_isLicensed '
        'email=${_email ?? "-"}',
      );
    } catch (e) {
      debugPrint('[ACCOUNT] initialize error: ${e.runtimeType}');
    }
  }

  /// Triggers the Google account picker, then exchanges the ID token with
  /// auth_server.py for an app session token. Returns null on success, or a
  /// short human-readable error message on failure.
  Future<String?> signInWithGoogle() async {
    if (!_googleInitialized) {
      return 'Google Sign-In failed to initialize. Check your network and try again.';
    }
    try {
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      final GoogleSignInAuthentication auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        return 'Google did not return an ID token. Verify googleServerClientId '
            'in app_config.dart matches your Web OAuth Client ID.';
      }
      return await _exchangeGoogleToken(idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('[ACCOUNT] GoogleSignInException: ${e.code} ${e.description}');
      return 'Google sign-in failed: ${e.description ?? e.code}';
    } catch (e) {
      debugPrint('[ACCOUNT] signInWithGoogle error: $e');
      return 'Sign-in failed. Please try again.';
    }
  }

  Future<String?> _exchangeGoogleToken(String idToken) async {
    try {
      final resp = await http
          .post(
            Uri.parse('${AppConfig.authBaseUrl}/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return 'Account server rejected sign-in (${resp.statusCode}).';
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      await _persistSession(
        token: data['session_token'] as String,
        email: data['email'] as String?,
        name: data['name'] as String?,
        isLicensed: data['is_licensed'] as bool? ?? false,
      );
      return null;
    } catch (e) {
      debugPrint('[ACCOUNT] token exchange error: $e');
      return 'Could not reach the account server. Check your internet connection.';
    }
  }

  /// Submits a license key for the signed-in account. Returns null on
  /// success, or a short human-readable error message on failure.
  Future<String?> redeemLicenseKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'Enter a license key.';
    if (_sessionToken == null) return 'You are signed out. Please sign in again.';

    try {
      final resp = await http
          .post(
            Uri.parse('${AppConfig.authBaseUrl}/auth/redeem-key'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_sessionToken',
            },
            body: jsonEncode({'license_key': trimmed}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 404) return 'License key not found.';
      if (resp.statusCode == 409) return 'This license key has already been used.';
      if (resp.statusCode == 401) return 'Session expired. Please sign in again.';
      if (resp.statusCode != 200) return 'Could not activate license (${resp.statusCode}).';

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      _isLicensed = data['is_licensed'] as bool? ?? true;
      await prefs.setBool(_kIsLicensed, _isLicensed);
      return null;
    } catch (e) {
      debugPrint('[ACCOUNT] redeemLicenseKey error: $e');
      return 'Could not reach the account server. Check your internet connection.';
    }
  }

  /// Re-checks license status with the server (e.g. on app resume). Silent,
  /// best-effort — the cached value keeps the app usable offline, so a
  /// failure here is never surfaced to the user.
  Future<void> refreshStatus() async {
    if (_sessionToken == null) return;
    try {
      final resp = await http.get(
        Uri.parse('${AppConfig.authBaseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $_sessionToken'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 401) {
        await signOut();
        return;
      }
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final licensed = data['is_licensed'] as bool? ?? _isLicensed;
      if (licensed != _isLicensed) {
        _isLicensed = licensed;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kIsLicensed, _isLicensed);
      }
    } catch (e) {
      debugPrint('[ACCOUNT] refreshStatus error: ${e.runtimeType}');
    }
  }

  Future<void> _persistSession({
    required String token,
    required String? email,
    required String? name,
    required bool isLicensed,
  }) async {
    await _secure.write(key: _kSessionToken, value: token);
    _sessionToken = token;
    _email = email;
    _name = name;
    _isLicensed = isLicensed;

    final prefs = await SharedPreferences.getInstance();
    if (email != null) await prefs.setString(_kEmail, email);
    if (name != null) await prefs.setString(_kName, name);
    await prefs.setBool(_kIsLicensed, isLicensed);
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _secure.delete(key: _kSessionToken);
    } catch (_) {}

    _sessionToken = null;
    _email = null;
    _name = null;
    _isLicensed = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kEmail);
      await prefs.remove(_kName);
      await prefs.remove(_kIsLicensed);
    } catch (_) {}
  }
}
