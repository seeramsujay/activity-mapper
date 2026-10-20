# TurnBack: Local-First Endurance Tracker & Activity Mapper

An ultra-lightweight, 100% serverless, battery-optimized GPS activity tracking mobile application designed for runners, cyclists, and hikers. Features fatigue-asymmetric turn-back navigation, low-memory 2GB RAM device optimization, post-run trajectory adjustments (Crop & Merge), and comprehensive multi-format `.zip` export capabilities.

---

## 🚀 Core Features

### 1. 🛡️ Fatigue-Asymmetric Turn-Back Engine
Solves the fundamental problem of **"fatigue asymmetry"** on out-and-back routes (where returning against headwinds or with muscular exhaustion takes longer than heading out).
- Configurable **Safety Margin Buffer** `b` (0% to 20%, defaulting to 8%).
- Turn-back time: `T_out = T_target / (1 + (1 + b) × γ)` with fatigue factor `γ = 1.15` for human-powered activities (`γ = 1.0` for motor vehicles). With the defaults the alarm fires at **~44.6% of the target duration** (40 min 9 s into a 90 min session), leaving ~55% of the time for the slower return leg.
- Elapsed time is active workout time (wall-clock time excluding pauses). The Flutter HUD and the native GPS service use the same formula and the same clock, and share a database flag so the alarm sounds **exactly once**, even with the screen off or the app closed.
- Fires an audible alarm tone (`ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD`, skipped for walks/hikes) and a distinct haptic pulse; for rides it can pause music first. Each can be toggled in Settings.

### 2. ⚡ 2GB RAM & Ultra-Low Battery Architecture
Specifically engineered to run smoothly on low-spec hardware without CPU throttling or battery drain:
- **Stationary Stop Detection:** After 5 consecutive fixes below $0.3\text{ m/s}$, GPS polling drops to one fix every 10 s; full-rate polling resumes on the first moving fix.
- **GPS Quality Filters (Settings → Record Profile & GPS):** fixes worse than the accuracy tolerance are discarded, and points closer than the minimum distance to the previous stored point are not written.
- **Crash / Kill Recovery:** the tracking service persists its session state; if Android kills the process it resumes logging on restart, and reopening the app re-attaches (or restarts) tracking for an active session.
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
- **GPX 1.1:** Standard XML with `<trkpt>`, UTC timestamps, smoothed elevation and speed (Garmin `TrackPointExtension`).
- **TCX:** Garmin Training Center v2 with per-trackpoint cumulative distance and correct sport (Running / Biking) for Garmin Connect, Strava and TrainingPeaks imports.
- **KML:** Google Earth formatted `<LineString>` and start/finish `<Placemark>` pins.
- **GeoJSON:** RFC 7946 compliant `FeatureCollection` format for GIS tools and Web maps.
- **CSV:** Raw tabular telemetry with timestamps, lat/lng, speed, and accuracy columns.
- **ZIP Bundles:** 
  - *Single Activity:* Compresses all 4 formats for a workout into a single `.zip`.
  - *Full Lifetime Backup:* Archives a consistent snapshot of the SQLite database (`turnback.db`, WAL checkpointed first) plus every session in GPX, KML, GeoJSON and CSV.

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
│   └── widgets/              # BreadcrumbPainter (RDP Decimation), VectorMapView
├── docs/                     # Technical Specifications & Documentation
│   └── idea.md               # Detailed Product Spec & Verification Notes
├── test/                     # Mathematical & Unit Test Suites
│   └── turnback_math_test.dart # 16 test suites (Safety math, Hysteresis, RDP, Exporters)
├── .gitignore                # Strict ignore for archives, uv.lock, and build files
└── README.md                 # Project Overview (This file)
```

---

## 🧪 Tests

Run the whole suite (no device needed; database tests use a real SQLite engine via `sqflite_common_ffi`):

```bash
flutter test
```

| Suite | Covers |
|---|---|
| `test/session_control_service_test.dart` | Turn-back formula, pause/resume, continue/reset countdown, alarm de-duplication, crash recovery (mocked native channel) |
| `test/db_service_test.dart` | Schema, foreign-key cascades, atomic clone/merge, turn-back flag, distance cache, legacy-DB migration |
| `test/track_formats_test.dart` | GPX/TCX/KML well-formedness (parsed with `package:xml`), TCX units and sport, GeoJSON, CSV, elevation gain, tile cache keys |
| `test/colab_p2p_test.dart` | AES-256-GCM mesh encryption (nonce reuse, tamper detection), URI handshake, models |
| `test/turnback_math_test.dart` | RDP decimation, hysteresis, reference-route navigation (out-and-back matching, jitter-free cues, off-route) |
| `test/units_and_cache_test.dart` | Metric / imperial formatting, legacy tile-cache migration, mesh QR rendezvous guard |
| `test/adaptive_pacing_test.dart`, `test/future_features_test.dart` | Pacing, Kalman / Savitzky-Golay, BLE parsers |
| `test/track_magic_sheet_test.dart`, `test/strava_relive_test.dart` | Feed card & action sheet widgets, Strava (no credentials ⇒ explicit failure), Relive GPX |

---

## 📦 Build Instructions

### Android APKs (two flavors)
Run `scripts/setup_development.sh` once (installs/locates Flutter and the Android SDK), then:
```bash
# Strict offline tracker
flutter build apk --debug --flavor offline -t lib/main_offline.dart
# Offline tracker + LAN/hotspot group mesh + Strava bridge
flutter build apk --debug --flavor colab -t lib/main_colab.dart
```
Outputs: `build/app/outputs/flutter-apk/app-offline-debug.apk` and `app-colab-debug.apk`.

For a signed release build, create a keystore and `android/key.properties` (both git-ignored):
```properties
storeFile=/absolute/path/to/turnback-release.jks
storePassword=...
keyAlias=turnback
keyPassword=...
```
then `flutter build apk --release --flavor offline -t lib/main_offline.dart`. Without `key.properties`, release builds fall back to the debug key (fine for testing, not for publishing).

### Group mesh connectivity (colab flavor)
Teammates on the same Wi-Fi or phone hotspot find each other automatically. Over mobile data, the host's QR carries its public endpoint (STUN); if a carrier NAT blocks the return path, the host taps **Scan a teammate's QR** on the joiner's phone to open it. All mesh packets are AES-256-GCM encrypted with the session key from the QR.

---

## 🤖 Headless Automation API (Tasker / Automation)

Control the application headlessly via Android Broadcast Intents:

| Action Intent | Intent Extras | Description |
|---|---|---|
| `org.opensource.tracker.START_ACTIVITY` | `duration_mins: int` (or `target_duration: int` seconds), `safety_buffer: double` (%), `activity_type: string` | Starts background tracking (ignored if a session is already active or paused) |
| `org.opensource.tracker.STOP_ACTIVITY` | None | Stops tracking and marks the session completed |
| `org.opensource.tracker.GET_CURRENT_STATS` | None | Replies with an `org.opensource.tracker.STATS_REPLY` broadcast: `is_running`, `session_id`, `elapsed_seconds`, `distance_km`, `points_logged`, `target_duration`, `safety_buffer` |

> Android 12+ only allows starting the tracking service from the background when TurnBack is exempt from battery optimisation (the app asks for this exemption).

---

## 📄 License & Privacy

This project is open-source under the GNU Affero General Public License v3.0 (see `LICENSE`). It operates **100% locally and offline** without tracking, ads, analytics, or external servers. All data remains exclusively on your device.
