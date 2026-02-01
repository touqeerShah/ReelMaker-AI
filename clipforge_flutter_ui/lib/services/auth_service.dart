import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Web client ID from Google Cloud Console (must match Supabase config)
const _webClientId = '522345988245-l1nfo9icq82ei5firdmi0h1ip7gqrpf7.apps.googleusercontent.com';

/// iOS client ID (create in Google Cloud Console for iOS)
/// You'll need to create this in the Google Cloud Console
const _iosClientId = '522345988245-XXXXXXXXXXXXXXXXXXXXXXX.apps.googleusercontent.com';

class AuthService {
  SupabaseClient get _sb => Supabase.instance.client;

  Stream<AuthState> authChanges() => _sb.auth.onAuthStateChange;
  Session? get session => _sb.auth.currentSession;

  Future<void> signInEmail(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> signUpEmail(String email, String password) async {
    await _sb.auth.signUp(email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    await _sb.auth.resetPasswordForEmail(email.trim());
  }

  /// Sign in with Google using native SDK on mobile, OAuth on web
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      // Web: use OAuth redirect flow
      await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'http://localhost:3000',
      );
    } else {
      // Native: use google_sign_in for better UX
      await _nativeGoogleSignIn();
    }
  }

  /// Native Google Sign-In using google_sign_in package
  Future<void> _nativeGoogleSignIn() async {
    final googleSignIn = GoogleSignIn(
      clientId: _iosClientId,
      serverClientId: _webClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw Exception('No ID Token found from Google');
    }

    // Sign in to Supabase with the Google ID token
    await _sb.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<void> signInWithFacebook() async {
    await _sb.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: kIsWeb ? 'http://localhost:3000' : 'io.clipforge://login-callback',
    );
  }

  Future<void> signOut() async {
    // Sign out from Google as well if signed in
    if (!kIsWeb) {
      try {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      } catch (_) {
        // Ignore errors during Google sign out
      }
    }
    await _sb.auth.signOut();
  }
}
