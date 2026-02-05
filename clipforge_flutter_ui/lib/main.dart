import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/auth_gate.dart';
import 'services/local_backend_api.dart';
import 'services/queue_sync_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local backend API
  await LocalBackendAPI().init();
  
  // Connect to WebSocket if authenticated
  if (LocalBackendAPI().isAuthenticated) {
    await QueueSyncService().connect();
  }

  runApp(const ClipForgeApp());
}

class ClipForgeApp extends StatefulWidget {
  const ClipForgeApp({super.key});

  @override
  State<ClipForgeApp> createState() => _ClipForgeAppState();
}

class _ClipForgeAppState extends State<ClipForgeApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AuthGate(
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
