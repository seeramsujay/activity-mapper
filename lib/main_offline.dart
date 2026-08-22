import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'services/settings_service.dart';
import 'screens/setup_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

/// Pure 100% Offline Flavor Entry Point.
/// Zero network telemetry, zero cloud dependencies, 100% local SQLite WAL execution.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Map<String, dynamic>? activeSession;
  try {
    final dbHelper = DbService.instance;
    await dbHelper.database;
    activeSession = await dbHelper.getActiveSession();
  } catch (e, stack) {
    debugPrint("Startup Offline DB initialization error: $e\n$stack");
  }
  
  runApp(const TurnBackOfflineApp());
}

/// The root Widget of the TurnBack Offline application.
class TurnBackOfflineApp extends StatelessWidget {
  const TurnBackOfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final currentTheme = SettingsService.instance.getThemeData(context);
        return MaterialApp(
          title: 'TurnBack (Offline)',
          debugShowCheckedModeBanner: false,
          theme: currentTheme,
          darkTheme: currentTheme,
          themeMode: ThemeMode.dark,
          home: const SetupScreen(isOfflineOnly: true),
          routes: {
            '/setup': (context) => const SetupScreen(isOfflineOnly: true),
            '/history': (context) => const HistoryScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}
