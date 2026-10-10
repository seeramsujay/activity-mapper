import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turnback/widgets/session_feed_card.dart';
import 'package:turnback/widgets/track_magic_sheet.dart';

void main() {
  final testSession = <String, dynamic>{
    'id': 42,
    'activity_type': 'run',
    'start_time': DateTime(2026, 10, 9, 8, 30).millisecondsSinceEpoch,
    'end_time': DateTime(2026, 10, 9, 9, 15).millisecondsSinceEpoch, // 45 min
    'target_duration': 3600, // 60 min
    'safety_buffer': 0.08,
    'turn_back_triggered_at': null,
    'status': 'completed',
  };

  final samplePoints = [
    const Point(37.7749, -122.4194),
    const Point(37.7755, -122.4180),
    const Point(37.7760, -122.4170),
  ];

  group('SessionFeedCard Clean UI & Magic Trigger Tests', () {
    testWidgets('renders cleanly without cluttered button toolbars', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionFeedCard(
              session: testSession,
              textColor: Colors.black,
              brightness: Brightness.light,
              initialDistanceKm: 5.25,
              initialPoints: samplePoints,
              onDelete: () {},
              onEdit: () {},
              onContinue: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Card Header Elements
      expect(find.text('RUN #42'), findsOneWidget);
      expect(find.text('9/10/2026 • 08:30'), findsOneWidget);
      expect(find.text('SAFE OUT-BACK'), findsOneWidget);

      // Card Body Stats
      expect(find.text('5.25 KM'), findsOneWidget);
      expect(find.text('45m 0s'), findsOneWidget);
      expect(find.text('60m'), findsOneWidget); // Target duration

      // Discoverable '...' more menu button
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

      // Verify NO old cluttered buttons on card face
      expect(find.text('CONTINUE'), findsNothing);
      expect(find.text('EDIT'), findsNothing);
      expect(find.text('GPX'), findsNothing);
      expect(find.text('DELETE'), findsNothing);
    });

    testWidgets('long press opens TrackMagicSheet modal', (WidgetTester tester) async {
      bool continueCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionFeedCard(
              session: testSession,
              textColor: Colors.black,
              brightness: Brightness.light,
              initialDistanceKm: 5.25,
              initialPoints: samplePoints,
              onDelete: () {},
              onEdit: () {},
              onContinue: () => continueCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Long press on the card
      await tester.longPress(find.byType(SessionFeedCard));
      await tester.pumpAndSettle();

      // Verify TrackMagicSheet appeared
      expect(find.byType(TrackMagicSheet), findsOneWidget);
      expect(find.text('SUMMARY & CHARTS'), findsOneWidget);
      expect(find.text('CONTINUE RUN'), findsOneWidget);
      expect(find.text('View Interactive Route Map'), findsOneWidget);
      expect(find.text('Edit & Trim Activity'), findsOneWidget);
      expect(find.text('Quick Share GPX File'), findsOneWidget);
      expect(find.text('Export Multi-Format Hub'), findsOneWidget);
      expect(find.text('Upload to Strava'), findsOneWidget);
      expect(find.text('Delete Activity'), findsOneWidget);

      // Tap 'CONTINUE RUN' inside the sheet
      await tester.tap(find.text('CONTINUE RUN'));
      await tester.pumpAndSettle();

      expect(continueCalled, isTrue);
    });

    testWidgets('tapping more (...) icon also triggers TrackMagicSheet', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionFeedCard(
              session: testSession,
              textColor: Colors.black,
              brightness: Brightness.light,
              initialDistanceKm: 5.25,
              initialPoints: samplePoints,
              onDelete: () {},
              onEdit: () {},
              onContinue: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap '...' button
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // Verify Magic Sheet is visible
      expect(find.byType(TrackMagicSheet), findsOneWidget);
      expect(find.text('ROUTE & VISUALIZATION'), findsOneWidget);
      expect(find.text('SHARE & EXPORT'), findsOneWidget);
      expect(find.text('MANAGEMENT'), findsOneWidget);
    });
  });

  group('TrackMagicSheet Component Tests', () {
    testWidgets('displays all metric items and actions properly', (WidgetTester tester) async {
      bool editTapped = false;
      bool deleteTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    TrackMagicSheet.show(
                      context: context,
                      session: testSession,
                      distanceKm: 8.40,
                      duration: const Duration(minutes: 50, seconds: 24),
                      mapPoints: samplePoints,
                      onContinue: () {},
                      onEdit: () => editTapped = true,
                      onDelete: () => deleteTapped = true,
                    );
                  },
                  child: const Text('OPEN SHEET'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN SHEET'));
      await tester.pumpAndSettle();

      // Metrics pill in sheet
      expect(find.text('8.40 KM'), findsOneWidget);
      expect(find.text('50m 24s'), findsOneWidget);

      // Scroll down to reveal Delete Activity in bottom sheet
      final deleteFinder = find.text('Delete Activity');
      await tester.scrollUntilVisible(deleteFinder, 300, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();

      // Tap Delete Activity opens confirmation dialog
      await tester.tap(deleteFinder);
      await tester.pumpAndSettle();

      expect(find.text('Delete Activity?'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });
  });
}
