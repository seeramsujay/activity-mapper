# TurnBack: Local-First Endurance Tracker & Activity Mapper

An ultra-lightweight, 100% serverless, battery-optimized GPS activity tracking mobile application designed for runners, cyclists, and hikers. Features fatigue-asymmetric turn-back navigation, low-memory 2GB RAM device optimization, post-run trajectory adjustments (Crop & Merge), and comprehensive multi-format `.zip` export capabilities.

---

## 🚀 Core Features

### 1. 🛡️ The 54% Turn-Back Engine
Solves the fundamental problem of **"fatigue asymmetry"** on out-and-back routes (where returning against headwinds or with muscular exhaustion takes longer than heading out).
- Configurable **Safety Margin Buffer** (0% to 20%, defaulting to 8%).
- Evaluates your elapsed time and alerts you when exactly **54%** of the target duration remains (at 46% elapsed time).
- Fires a persistent audible alarm tone (`ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD`) and distinct haptic pulse pattern.

### 2. ⚡ 2GB RAM & Ultra-Low Battery Architecture
Specifically engineered to run smoothly on low-spec hardware without CPU throttling or battery drain:
- **Stationary Stop Detection:** When resting or stopped ($\le 0.2\text{ m/s}$ across 3 consecutive ticks), GPS sampling frequency automatically scales from 5s down to 30s intervals.
- **Ramer-Douglas-Peucker (RDP) Decimation:** In-memory GPS coordinates are dynamically decimated down to visual resolution for the custom breadcrumb painter, maintaining 60 FPS rendering under $< 5\text{MB}$ RAM overhead.
- **Deterministic 2x3 HUD Grid:** High-performance dashboard enclosed in a `RepaintBoundary` to prevent unnecessary widget tree repaints:
  - Top Left: Big Pace / Speed (auto-switching with 5-tick hysteresis at 18 km/h).
  - Top Right: Remaining Countdown / 54% Target.
  - Mid Left: Total Distance (km).
  - Mid Right: Current Elevation / Elevation Gain (m).
  - Bottom Row: Compact Vector Breadcrumb Polyline.

### 3. ✂️ Post-Run Adjustment Suite
Full post-run editing suite located in the activity editor:
- **CROP:** Hardware-accelerated dual-handle range slider with haptic feedback (`HapticFeedback.selectionClick()`), live path preview, and recalculated distance/duration.
- **MERGE:** Chronologically merges two completed workout sessions into a single continuous track with database transaction safety.
- **N-CHOP:** Divides long endurance activities into $N$ equal distance segments.
- **TIME-CHOP:** Splits workouts into fixed time chunk intervals.

### 4. 📦 Multi-Format Export & ZIP Engine
Export single activities or your entire workout history directly from device storage without any cloud or server dependencies:
- **GPX 1.1:** Standard XML with `<trkpt>`, timestamps, and elevation data.
- **KML:** Google Earth formatted `<LineString>` and start/finish `<Placemark>` pins.
- **GeoJSON:** RFC 7946 compliant `FeatureCollection` format for GIS tools and Web maps.
- **CSV:** Raw tabular telemetry with timestamps, lat/lng, speed, and accuracy columns.
- **ZIP Bundles:** 
  - *Single Activity:* Compresses all 4 formats for a workout into a single `.zip`.
  - *Full Lifetime Backup:* Archives the raw SQLite database (`turnback.db`), WAL journals, and complete GPX archives in one zip file.

---

## 🛠️ Technology Stack

- **UI & Presentation:** Flutter (Dart 3.x, Material 3, Pure Vanilla CustomPainter)
- **Background Location Engine:** 
  - **Android:** Native Foreground Service (`GpsLoggingService.kt`) with `WAKE_LOCK`, `FOREGROUND_SERVICE_LOCATION`, and direct WAL-mode SQLite writes.
- **Database:** SQLite with Write-Ahead Logging (`PRAGMA journal_mode=WAL;`)
- **Archiving & Compression:** Pure Dart `archive` library for fast on-device zip generation.

---

## 📁 Project Architecture

```
.
├── android/                  # Android Native Layer
│   └── app/src/main/kotlin/  # GpsLoggingService.kt, AutomationReceiver.kt, DBHelper.kt
├── lib/                      # Flutter UI & Business Logic Layer
│   ├── main.dart             # Application Entrypoint & Theme Routing
│   ├── models/               # Geodesic, Activity, & Navigation Models
│   ├── screens/              # SetupScreen, HudScreen, HistoryScreen, EditorScreen
│   ├── services/             # DbService, ExportService, BackupService, RallyEngine
│   └── widgets/              # BreadcrumbPainter (RDP Decimation), OsmMapView
├── docs/                     # Technical Specifications & Documentation
│   └── idea.md               # Detailed Product Spec & Verification Notes
├── test/                     # Mathematical & Unit Test Suites
│   └── turnback_math_test.dart # 16 test suites (Safety math, Hysteresis, RDP, Exporters)
├── .gitignore                # Strict ignore for archives, uv.lock, and build files
└── README.md                 # Project Overview (This file)
```

---

## 🧪 Unit & Math Tests

All core algorithms (safety buffer arithmetic, speed hysteresis state machine, multi-format serializers, RDP decimation, and session merging) are verified via comprehensive tests:

```bash
flutter test test/turnback_math_test.dart
```

---

## 📦 Build Instructions

### Android Debug APK
To build the debug APK on Linux/macOS:
```bash
flutter build apk --debug
```
The output APK will be placed at:
```
build/app/outputs/flutter-apk/app-debug.apk
```

---

## 🤖 Headless Automation API (Tasker / Automation)

Control the application headlessly via Android Broadcast Intents:

| Action Intent | Intent Extras | Description |
|---|---|---|
| `org.opensource.tracker.START_ACTIVITY` | `duration_mins: int` | Starts background tracking service instantly |
| `org.opensource.tracker.STOP_ACTIVITY` | None | Stops tracking and saves activity to database |
| `org.opensource.tracker.GET_CURRENT_STATS` | None | Emits JSON with current distance, pace, speed, and status |

---

## 📄 License & Privacy

This project is open-source under the MIT License. It operates **100% locally and offline** without tracking, ads, analytics, or external servers. All data remains exclusively on your device.
