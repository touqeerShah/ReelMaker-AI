import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/widgets.dart'; // uses CfAppBar/CfCard if you want consistency

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _isLoading = false;
  bool _isSignup = false;
  String? _error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CfAppBar(title: Text('Sign in')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          CfCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ClipForge',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Offline creator tools. Your videos stay on-device.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.65)),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),

                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: TextStyle(color: cs.error)),
                  ),

                FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () => _run(() async {
                            if (_isSignup) {
                              await _auth.signUpEmail(_email.text, _pass.text);
                            } else {
                              await _auth.signInEmail(_email.text, _pass.text);
                            }
                          }),
                  child: Text(_isSignup ? 'Create account' : 'Sign in'),
                ),

                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _isSignup = !_isSignup),
                  child: Text(_isSignup ? 'Have an account? Sign in' : 'New here? Create an account'),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => _run(() async {
                              await _auth.sendPasswordReset(_email.text);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Password reset email sent (if email exists).')),
                                );
                              }
                            }),
                    child: const Text('Forgot password?'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(child: Divider(color: cs.outline.withOpacity(0.35))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
              ),
              Expanded(child: Divider(color: cs.outline.withOpacity(0.35))),
            ],
          ),

          const SizedBox(height: 14),

          CfCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _run(() async => _auth.signInWithGoogle()),
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _run(() async => _auth.signInWithFacebook()),
                  icon: const Icon(Icons.facebook),
                  label: const Text('Continue with Facebook'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
