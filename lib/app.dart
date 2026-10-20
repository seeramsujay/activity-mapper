import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'services/settings_service.dart';
import 'screens/setup_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

/// Shared startup for every flavor entry point (main.dart, main_offline.dart, main_colab.dart).
///
/// Loads persisted settings and opens the database before the first frame so the first screen
/// renders with the user's theme and any in-progress session is visible on the dashboard.
Future<void> runTurnBackApp({required String title, required bool isOfflineOnly}) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SettingsService.instance.loadSettings();
    final db = DbService.instance;
    await db.database;
    // Older versions ran without foreign keys, so deleted sessions may have left points behind.
    await db.purgeOrphanPoints();
  } catch (e, stack) {
    debugPrint("Startup initialization error: $e\n$stack");
  }

  runApp(TurnBackApp(title: title, isOfflineOnly: isOfflineOnly));
}

/// The root Widget of the TurnBack Flutter application.
class TurnBackApp extends StatelessWidget {
  /// Window/task title.
  final String title;

  /// True for the strict offline flavor (hides collaboration features).
  final bool isOfflineOnly;

  const TurnBackApp({super.key, this.title = 'TurnBack', this.isOfflineOnly = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final settings = SettingsService.instance;
        return MaterialApp(
          title: title,
          debugShowCheckedModeBanner: false,
          theme: settings.buildTheme(light: true),
          darkTheme: settings.buildTheme(light: false),
          themeMode: settings.materialThemeMode,
          home: SetupScreen(isOfflineOnly: isOfflineOnly),
          routes: {
            '/setup': (context) => SetupScreen(isOfflineOnly: isOfflineOnly),
            '/history': (context) => const HistoryScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}
