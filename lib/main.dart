import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'screens/setup_screen.dart';
import 'screens/history_screen.dart';

/// The entry point of the TurnBack Endurance Tracker.
///
/// It initializes the Flutter bindings, ensures the SQLite local database is
/// instantiated with Write-Ahead Logging (WAL) mode enabled, and checks if
/// there is an active session from a previous run for crash recovery.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Map<String, dynamic>? activeSession;
  try {
    // Initialize shared database connection (WAL mode enabled)
    final dbHelper = DbService.instance;
    await dbHelper.database;
    
    // Query for crash recovery
    activeSession = await dbHelper.getActiveSession();
  } catch (e, stack) {
    debugPrint("Startup DB initialization error: $e\n$stack");
  }
  
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
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF111827),
          secondary: Color(0xFFFF4500),
          surface: Colors.white,
          onSurface: Color(0xFF111827),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          ),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090A0C),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFFFF5722),
          surface: Color(0xFF14171C),
          onSurface: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF23272F), width: 1.5),
          ),
          color: const Color(0xFF14171C),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
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

