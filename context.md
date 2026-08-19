# Activity Mapper (TurnBack) — Development Session Context & Architecture

This document provides a comprehensive technical log and architectural overview of all features, services, optimizations, and future roadmap specifications implemented during this session.

---

## 1. 🚀 Release v1.0.0 & Release APK Build
- **GitHub Release `v1.0.0` Published**: Tagged and published on GitHub without binary release attachments per requirements.
- **Production Release APK Compiled**:
  - Fixed theme enum naming in [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart).
  - Built optimized release APK at `build/app/outputs/flutter-apk/app-release.apk` (52 MB) with `--android-skip-build-dependency-validation`.

---

## 2. 🗺️ Offline OSM Map Tile Engine & Google Maps-Style Downloader
- **Tile Cache Service ([`TileCacheService`](lib/services/tile_cache_service.dart))**:
  - **Cache-First Lookup Policy**: Resolves tiles from local storage (`/osm_tiles/{z}/{x}/{y}.png`) before attempting any network requests.
  - **Area Tile Pack Downloader**: Downloader stream covering zoom levels 13–16 with polite OpenStreetMap User-Agent headers, download progress broadcasts, and tile deduplication.
  - **Download Footprint Estimator**: `estimateAreaMetrics(radiusKm, zoomLevels)` calculates tile counts and expected megabytes:
    * *2 km*: ~60 tiles (~1.5 MB)
    * *5 km*: ~380 tiles (~9.5 MB)
    * *10 km*: ~1,500 tiles (~38.0 MB)
    * *20 km*: ~5,800 tiles (~145.0 MB)
- **Map View Integration ([`OsmMapView`](lib/widgets/osm_map_view.dart))**:
  - Uses `_CachedTileImage` to load tiles directly from disk for 0 ms offline map rendering and zero cellular data usage.
- **Google Maps-Style UI in Settings ([`SettingsScreen`](lib/screens/settings_screen.dart))**:
  - Bottom sheet dialog with custom **Area Name** input field, **Radius Slider** (2 km – 20 km), live storage footprint card, live progress bar, tile count / MB metrics, and 1-tap "Clear Cache" button.

---

## 3. ⛰️ Mountain-Grade Elevation Profile Smoothing
- **Elevation Filter Service ([`ElevationFilterService`](lib/services/elevation_filter_service.dart))**:
  - **1D Real-Time Kalman Filter**: Smooths GPS barometric/altimeter noise on live incoming fixes with process and measurement noise covariance parameters ($Q = 0.08, R = 4.0$).
  - **5-Point Savitzky-Golay Quadratic Smoothing**: Eliminates high-frequency elevation jitter while strictly preserving real mountain peaks and valleys using convolution kernel coefficients $[-3, 12, 17, 12, -3] / 35$.
  - **Forward-Backward Dual Pass**: Bidirectional smoothing filter over complete session elevation profiles for GPX exports and charts.
- **Integration with GPX Exporter ([`GpxService`](lib/services/gpx_service.dart))**:
  - Integrated into `_createGpxString` to produce clean elevation curves.

---

## 4. 🔋 Ultra-Low Battery & Adaptive Display Refresh
- **Native Android Refresh Rate Clamping**:
  - Updated [`MainActivity.kt`](android/app/src/main/kotlin/org/opensource/tracker/MainActivity.kt) and [`PlatformService`](lib/services/platform_service.dart) with `setPowerSaveDisplay(enable: bool)`.
  - Android 11+ / API 23+ window display mode API clamps the physical screen refresh rate to **30 Hz** while the HUD tracking screen is foregrounded.
- **1 Hz Event-Driven HUD Updates**:
  - Eliminated continuous 60–120 FPS render loops; map and telemetry widgets repaint strictly on GPS fix arrivals or user touch interactions.
- **OLED Inactivity Auto-Dimmer ([`HudScreen`](lib/screens/hud_screen.dart))**:
  - Automatically fades screen luminance after 25s of touch inactivity into pure `#000000` AMOLED power saver mode with a subtle indicator, waking instantly on touch.

---

## 5. 🎵 In-HUD Media Player Controller & Native Dispatch
- **In-HUD Glove-Friendly Media Widget ([`HudMediaController`](lib/widgets/hud_media_controller.dart))**:
  - Large touch targets for Play/Pause, Previous, Next Track, and expandable Volume Up / Down controls.
- **Android `AudioManager` Media Key Dispatcher**:
  - [`MainActivity.kt`](android/app/src/main/kotlin/org/opensource/tracker/MainActivity.kt) dispatches standard Android `KeyEvent`s (`KEYCODE_MEDIA_PLAY_PAUSE`, `KEYCODE_MEDIA_NEXT`, `KEYCODE_MEDIA_PREVIOUS`) to active background players (Spotify, Musicolet, Poweramp, VLC, YouTube Music).

---

## 6. ⌚ BLE Sensors & Garmin/Wahoo/Strava TCX Exporter
- **BLE Sensor Service ([`BleSensorService`](lib/services/ble_sensor_service.dart))**:
  - Standard Bluetooth SIG GATT parsers for **Heart Rate** (`0x180D` / `0x2A37`) supporting both 8-bit and 16-bit BPM formats.
  - Standard GATT parser for **Cycling Speed & Cadence (CSC)** (`0x1816` / `0x2A5B`) calculating crank revolutions per minute (RPM).
  - Built-in realistic hardware simulator for in-app testing and pairing controls.
- **In-HUD Telemetry Chip ([`HudScreen`](lib/screens/hud_screen.dart))**:
  - Displays live BPM and RPM chips on the HUD control bar with color-coded heart rate indicators.
- **Garmin / Wahoo TCX Exporter ([`ExportService`](lib/services/export_service.dart))**:
  - Implemented `generateTcxString` producing valid Training Center Database XML (`.tcx`) with trackpoints, speeds, and timestamps for direct sync to Garmin Connect, Wahoo, Strava, and TrainingPeaks.

---

## 7. 🧪 Unit Test Verification
- All 22 test suites in [`test/future_features_test.dart`](test/future_features_test.dart) and [`test/turnback_math_test.dart`](test/turnback_math_test.dart) compile and pass with 100% success:
  - Kalman filter noisy sample filtering
  - Savitzky-Golay quadratic polynomial smoothing
  - BLE 8-bit & 16-bit Heart Rate GATT packet parsers
  - BLE Cycling Speed & Cadence GATT crank RPM calculation
  - Mathematical turn-back safety buffer engines, Haversine formatters, and serializers

---

## 8. 🔭 Future Architecture & Multi-Flavor Roadmap ([`far_future.md`](far_future.md))

### Flavor Separation Principles:
1. **`offline` Flavor (Strict 100% Offline Tracker)**:
   - Zero network requests, zero cloud sync, zero background network threads.
   - Dart tree-shaking completely drops all collaboration, Strava, and network code from the binary.
2. **`colab` Flavor (Wide-Area Serverless P2P Group Mesh + Strava/Relive Bridges)**:
   - **Wide-Area Direct Encrypted Tunneling**: Uses direct UDP hole punching (via public STUN `stun:stun.l.google.com`) or WebRTC DataChannels over mobile data to connect teammates across kilometers with **zero cloud storage** and negligible data usage (~500 bytes/min).
   - **Tailscale & WireGuard Overlay**: Direct binding to virtual mesh IPs (`100.x.y.z`).
   - **Decentralized QR-Key Chaining**: Leader starts session and renders an offline QR code containing the session UUID and 256-bit AES-256-GCM key. Joining teammates scan, set their custom username and color pin, link their own GPX route or record fresh, and can show the same QR code to chain-onboard more riders.
   - **Strava 1-Tap Upload**: OAuth2 API direct upload of `.tcx` / `.gpx` tracks.
   - **Relive 3D Aerial Video Bridge**: Kalman-smoothed elevation GPX format for 3D aerial flyover video generation.

### Hardware & Low-Spec MacBook Air (2017) Optimization:
- JVM heap capped (`-Xmx1536m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC`).
- Workers capped (`org.gradle.workers.max=2`), Gradle caching enabled, parallel tasks disabled.
- Single-ABI ARM64 compilation (`--target-platform android-arm64`) for ~300% faster build cycles.
- Side-by-side Android package IDs (`org.opensource.tracker.offline` vs `org.opensource.tracker.colab`).
