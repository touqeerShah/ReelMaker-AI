import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/local_backend_api.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

class SignUpScreen extends StatefulWidget {
  final VoidCallback? onSignUpSuccess;

  const SignUpScreen({super.key, this.onSignUpSuccess});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _api = LocalBackendAPI();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.register(
        email: _email.text.trim(),
        password: _pass.text,
        name: _name.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Account created! You are now logged in.')),
        );
        Navigator.pop(context);
        widget.onSignUpSuccess?.call();
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CfAppBar(title: Text('Create account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full Name'),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Password (min 6 characters)'),
            enabled: !_loading,
            onSubmitted: (_) => _signUp(),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: _loading ? null : _signUp,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign up'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Already have an account? Sign in'),
          ),
        ],
      ),
    );
  }
}
