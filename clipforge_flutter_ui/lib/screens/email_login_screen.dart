import 'package:flutter/material.dart';

import '../services/local_backend_api.dart';
import '../widgets/widgets.dart';

class EmailLoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  
  const EmailLoginScreen({super.key, this.onLoginSuccess});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _api = LocalBackendAPI();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.login(email: _email.text.trim(), password: _pass.text);
      if (mounted) {
        // Login successful - pop screen
        Navigator.pop(context);
        // Trigger parent callback to rebuild auth state
        widget.onLoginSuccess?.call();
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
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
      appBar: const CfAppBar(title: Text('Email sign in')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            enabled: !_loading,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            enabled: !_loading,
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: _loading ? null : _login,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
