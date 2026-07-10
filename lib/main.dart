import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'screens/setup_screen.dart';
import 'screens/hud_screen.dart';
import 'screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize shared database connection (WAL mode enabled)
  final dbHelper = DbService.instance;
  await dbHelper.database;
  
  // Query for crash recovery
  final activeSession = await dbHelper.getActiveSession();
  
  runApp(TurnBackApp(recoveredSession: activeSession));
}

class TurnBackApp extends StatelessWidget {
  final Map<String, dynamic>? recoveredSession;

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
      home: recoveredSession != null
          ? HudScreen(
              sessionId: recoveredSession!['id'] as int,
              targetDuration: Duration(seconds: recoveredSession!['target_duration'] as int),
              safetyBufferPct: recoveredSession!['safety_buffer'] as double,
              activityType: recoveredSession!['activity_type'] as String,
            )
          : const SetupScreen(),
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
