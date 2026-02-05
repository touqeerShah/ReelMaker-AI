import 'package:flutter/material.dart';
import '../screens/app_shell.dart';
import '../screens/login_screen.dart';
import '../services/local_backend_api.dart';

/// Auth gate that uses local backend API
class AuthGate extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChanged;

  const AuthGate({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    // Check if user is authenticated
    final isAuthenticated = LocalBackendAPI().isAuthenticated;

    if (isAuthenticated) {
      // User is logged in - show main app
      return AppShell(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      );
    } else {
      // User not logged in - show login screen
      // Pass callback to rebuild when login succeeds
      return LoginScreen(
        onLoginSuccess: () {
          // Rebuild to show AppShell
          setState(() {});
        },
      );
    }
  }
}
