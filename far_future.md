# Future Architecture & Build Flavors Specification

## Core Philosophy: Strict Flavor Isolation
1. **`offline` Flavor (Pure Local Tracker)**:
   - **100% Offline & Isolated**: Zero network requests, zero telemetry uploads, zero third-party auth tokens or external cloud services.
   - **Pure Local Execution**: Local SQLite database with WAL mode, offline vector canvas rendering, pre-cached local OSM tiles, and direct `.gpx`/`.kml`/`.tcx`/`.csv` file exports to the device.
   - **Zero Code Bloat**: Dart compiler tree-shaking drops all collaboration, Strava, and network code completely from the `offline` APK binary.

2. **`colab` Flavor (Serverless P2P Group Tracking & Optional Cloud Sync)**:
   - **Zero-Cloud End-to-End Encrypted (E2EE) P2P Protocol**:
     * **Instant QR-Key Pairing**: Host creates a group session, generating a 256-bit symmetric session key (AES-256-GCM / ChaCha20-Poly1305) encoded into an offline QR code (`activitymapper://p2p?ch=<UUID>&key=<BASE64_KEY>`).
     * **Zero-Knowledge Over-the-Air Mesh**: All location packets broadcast over local Wi-Fi Hotspot, multicast UDP (`239.255.255.250:8888`), or BLE are encrypted with AES-256-GCM using unique per-packet nonces.
     * Only teammates who physically scanned the QR code possess the key to decrypt and plot teammate positions on their live map.
   - **Serverless Live Team Tracking**:
     * Zero central server required — operates directly in remote mountains/forests without cellular internet.
     * Shows live teammates on the map with distinctive avatars, real-time pace, distance-to-peer, and breadcrumbs.
     * Multi-track group GPX export: export individual GPX tracks for each teammate or a merged group activity file.
   - **Strava Direct Upload Integration**:
     * Optional 1-tap OAuth2 upload of `.tcx` or `.gpx` tracks directly to Strava Activity API.
   - **Relive 3D Aerial Route Video Bridge**:
     * Relive-formatted GPX export with Kalman-smoothed elevations and waypoint tags for 3D flyover video generation.

---

## 🛠️ Low-Spec Developer Environment (2017 Dual-Core Mac, 8GB RAM)

- **Target Device**: Physical ARMv8 64-bit (`android-arm64`).
- **Single-ABI Compilation**: Eliminate fat universal APKs by targeting `--target-platform android-arm64` to speed up compile times by ~300%.
- **Gradle & JVM Capping**:
  * `org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC`
  * `org.gradle.workers.max=2`
  * `org.gradle.caching=true`
  * `org.gradle.parallel=false`
  * Debug `minSdkVersion 21+` to eliminate legacy pre-dexing bottlenecks.

---

## 📦 Android Product Flavors Configuration (`android/app/build.gradle`)

```groovy
flavorDimensions "mode"

productFlavors {
    offline {
        dimension "mode"
        applicationId "org.opensource.tracker.offline"
        manifestPlaceholders = [appName: "TurnBack (Offline)"]
        versionNameSuffix "-offline"
    }
    colab {
        dimension "mode"
        applicationId "org.opensource.tracker.colab"
        manifestPlaceholders = [appName: "TurnBack (Colab)"]
        versionNameSuffix "-colab"
    }
}
```
*Both APKs can be installed side-by-side simultaneously on the same device.*

---

## ⚡ Fast CLI Commands & Helper Script

### Fast Debug Run on Physical Phone:
```bash
# Pure Offline Flavor
flutter run -t lib/main_offline.dart --flavor offline --target-platform android-arm64

# Colab / P2P Flavor
flutter run -t lib/main_colab.dart --flavor colab --target-platform android-arm64
```

### Release Single-ABI APK Build:
```bash
# Pure Offline Release APK
flutter build apk -t lib/main_offline.dart --flavor offline --target-platform android-arm64

# Colab Release APK
flutter build apk -t lib/main_colab.dart --flavor colab --target-platform android-arm64
```
