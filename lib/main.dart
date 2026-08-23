import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'services/settings_service.dart';
import 'screens/setup_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

/// The entry point of the TurnBack Endurance Tracker.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Map<String, dynamic>? activeSession;
  try {
    await SettingsService.instance.loadSettings();
    final dbHelper = DbService.instance;
    await dbHelper.database;
    activeSession = await dbHelper.getActiveSession();
  } catch (e, stack) {
    debugPrint("Startup initialization error: $e\n$stack");
  }
  
  runApp(TurnBackApp(recoveredSession: activeSession));
}

/// The root Widget of the TurnBack Flutter application.
class TurnBackApp extends StatelessWidget {
  final Map<String, dynamic>? recoveredSession;

  const TurnBackApp({super.key, this.recoveredSession});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final currentTheme = SettingsService.instance.getThemeData(context);
        final isLight = SettingsService.instance.isLightMode(context);

        return MaterialApp(
          title: 'TurnBack',
          theme: currentTheme,
          darkTheme: currentTheme,
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
          home: const SetupScreen(),
          routes: {
            '/setup': (context) => const SetupScreen(),
            '/history': (context) => const HistoryScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute(builder: (context) => const SetupScreen());
            }
            return null;
          },
        );
      },
    );
  }
}

