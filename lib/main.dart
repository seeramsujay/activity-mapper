import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'screens/setup_screen.dart';
import 'screens/hud_screen.dart';
import 'screens/history_screen.dart';

/// The entry point of the TurnBack Endurance Tracker.
///
/// It initializes the Flutter bindings, ensures the SQLite local database is
/// instantiated with Write-Ahead Logging (WAL) mode enabled, and checks if
/// there is an active session from a previous run for crash recovery.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize shared database connection (WAL mode enabled)
  final dbHelper = DbService.instance;
  await dbHelper.database;
  
  // Query for crash recovery
  final activeSession = await dbHelper.getActiveSession();
  
  runApp(TurnBackApp(recoveredSession: activeSession));
}

/// The root Widget of the TurnBack Flutter application.
///
/// Configures high-contrast light and dark themes tailored for direct sunlight
/// visibility, maps core routes, and manages startup navigation.
class TurnBackApp extends StatelessWidget {
  /// An optional active session map recovered from the database on startup.
  final Map<String, dynamic>? recoveredSession;

  /// Creates a new [TurnBackApp] instance.
  const TurnBackApp({super.key, this.recoveredSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurnBack',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: Colors.black,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.white,
      ),
      themeMode: ThemeMode.system,
      // Handle recovery routing directly on start
      home: const SetupScreen(),
      routes: {
        '/setup': (context) => const SetupScreen(),
        '/history': (context) => const HistoryScreen(),
      },
      // Fallback route when Navigator.pushReplacementNamed(context, '/') is called
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(builder: (context) => const SetupScreen());
        }
        return null;
      },
    );
  }
}

