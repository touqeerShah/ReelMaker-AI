import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'email_login_screen.dart';
import 'signup_screen.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  bool _loading = false;
  String? _error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // immersive like the HTML templates
      extendBodyBehindAppBar: true,
      appBar: const CfAppBar(title: Text('')),

      body: Stack(
        children: [
          // Background: top gradient + radial glow (like template)
          const _LoginBackground(),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const Spacer(),

                      // Logo tile
                      _LogoTile(primary: cs.primary),

                      const SizedBox(height: 14),

                      Text(
                        'ClipForge',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Next-gen video synthesis on your device.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.60),
                            fontWeight: FontWeight.w600),
                      ),

                      const SizedBox(height: 26),

                      if (_error != null) ...[
                        Text(_error!, style: TextStyle(color: cs.error)),
                        const SizedBox(height: 10),
                      ],

                      // OAuth buttons
                      _OAuthButton(
                        loading: _loading,
                        label: 'Continue with Apple',
                        background: AppTheme.surfaceDarker,
                        foreground: cs.onSurface,
                        borderColor: cs.outline.withOpacity(0.15),
                        icon: const Icon(Icons.phone_iphone, size: 20),
                        onPressed: () {
                          // placeholder if you don't support Apple yet
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Apple login not enabled')),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _OAuthButton(
                        loading: _loading,
                        label: 'Continue with Google',
                        background: Colors.white,
                        foreground: const Color(0xFF111718),
                        borderColor: Colors.transparent,
                        icon: const Icon(Icons.search, size: 22),
                        onPressed: () => _run(() => _auth.signInWithGoogle()),
                      ),
                      const SizedBox(height: 16),

                      // Divider "Or"
                      Row(
                        children: [
                          Expanded(
                              child:
                                  Divider(color: cs.outline.withOpacity(0.30))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: cs.onSurface.withOpacity(0.55),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                            ),
                          ),
                          Expanded(
                              child:
                                  Divider(color: cs.outline.withOpacity(0.30))),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Email login opens bottom sheet (keeps “minimal steps”)
                      _OAuthButton(
                        loading: _loading,
                        label: 'Log in with Email',
                        background: Colors.transparent,
                        foreground: cs.onSurface,
                        borderColor: cs.outline.withOpacity(0.45),
                        icon: Icon(Icons.mail,
                            size: 20, color: cs.onSurface.withOpacity(0.8)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmailLoginScreen(
                                onLoginSuccess: widget.onLoginSuccess,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 18),

                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SignUpScreen(
                                onSignUpSuccess: widget.onLoginSuccess,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          "Don't have an account?  Sign Up",
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _FooterLink(label: 'Terms of Service', onTap: () {}),
                          const SizedBox(width: 16),
                          _FooterLink(label: 'Privacy Policy', onTap: () {}),
                        ],
                      ),

                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEmailSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final email = TextEditingController();
    final pass = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sign in with Email',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading
                      ? null
                      : () => _run(() async {
                            Navigator.pop(ctx);
                            await _auth.signInEmail(email.text, pass.text);
                          }),
                  child: const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => _run(() async {
                          await _auth.sendPasswordReset(email.text);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Password reset email sent (if email exists).',
                                style: TextStyle(color: cs.onInverseSurface),
                              ),
                            ),
                          );
                        }),
                child: const Text('Forgot password?'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          // Top abstract gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.50,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withOpacity(0.22),
                    Theme.of(context).scaffoldBackgroundColor.withOpacity(0.92),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),

          // Radial glow (blurred)
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.35,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: const SizedBox(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.primary});
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF283639), Color(0xFF101F22)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            blurRadius: 26,
            spreadRadius: -12,
            color: primary.withOpacity(0.25),
          ),
        ],
      ),
      child: Icon(Icons.movie_filter, color: primary, size: 34),
    );
  }
}

class _OAuthButton extends StatelessWidget {
  const _OAuthButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.loading,
    required this.background,
    required this.foreground,
    required this.borderColor,
  });

  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final bool loading;
  final Color background;
  final Color foreground;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: icon,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          side: BorderSide(color: borderColor),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withOpacity(0.40),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
