import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/widgets/interactive_telemetry_graph.dart';
import 'package:turnback/widgets/telemetry_bottom_sheet.dart';

void main() {
  testWidgets(
      'TelemetryBottomSheet displays glanceable speed, distance and time',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    bool pauseTapped = false;
    bool finishTapped = false;
    bool markerTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              TelemetryBottomSheet(
                currentSpeedMps: 5.0, // 18 km/h
                avgSpeedMps: 4.5,
                maxSpeedMps: 8.0,
                distanceKm: 4.52,
                elapsed: const Duration(minutes: 25, seconds: 30),
                altitude: 120.0,
                totalAscent: 45.0,
                totalDescent: 12.0,
                activityType: 'run',
                isSpeedMode: true,
                isPaused: false,
                graphPoints: const [
                  GraphPoint(
                      distanceKm: 0.0,
                      elapsedSeconds: 0,
                      speedKmh: 10,
                      altitudeMeters: 100),
                  GraphPoint(
                      distanceKm: 2.0,
                      elapsedSeconds: 600,
                      speedKmh: 18,
                      altitudeMeters: 120),
                ],
                onTogglePause: () => pauseTapped = true,
                onFinish: () => finishTapped = true,
                onAddWaypoint: () => markerTapped = true,
                brightness: Brightness.dark,
                accentColor: Colors.blue,
              ),
            ],
          ),
        ),
      ),
    );

    // Verify distance and time are displayed in the collapsed header
    expect(find.text('4.52'), findsOneWidget);
    expect(find.text('25:30'), findsOneWidget);

    // Tap pause button in glanceable header
    final pauseBtn = find.byIcon(Icons.pause_rounded);
    expect(pauseBtn, findsOneWidget);
    await tester.tap(pauseBtn);
    expect(pauseTapped, isTrue);

    // Drag sheet upward on the glanceable header
    await tester.drag(find.text('TIME'), const Offset(0, -600));
    await tester.pumpAndSettle();

    // Tap marker button now visible in expanded sheet
    final markerBtn = find.text('MARKER');
    expect(markerBtn, findsOneWidget);
    await tester.tap(markerBtn);
    expect(markerTapped, isTrue);

    // Verify elevation card is displayed
    expect(find.text('ELEVATION & INCLINE'), findsOneWidget);
  });
}
