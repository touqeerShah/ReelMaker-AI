import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  SupabaseClient get _sb => Supabase.instance.client;

  /// Emits auth state changes.
  Stream<AuthState> authChanges() => _sb.auth.onAuthStateChange;

  Session? get session => _sb.auth.currentSession;

  Future<void> signInEmail(String email, String password) async {
    await _sb.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUpEmail(String email, String password) async {
    await _sb.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    await _sb.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signInWithGoogle() async {
    await _sb.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.clipforge://login-callback',
    );
  }

  Future<void> signInWithFacebook() async {
    await _sb.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: 'io.clipforge://login-callback',
    );
  }

  Future<void> signOut() async {
    await _sb.auth.signOut();
  }
}
