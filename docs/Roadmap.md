# Project Engineering Roadmap

This roadmap details an ultra-lightweight, local-first endurance tracker that solves "fatigue asymmetry" on out-and-back routes while preserving battery under direct sunlight.

The ideal architecture combines **Flutter** (for a lean, cross-platform UI layer) with highly optimized **Native Background Services** (Kotlin on Android, Swift on iOS) to handle low-level GPS polling without waking up the heavy webviews or Flutter UI threads.

---

## 1. Core Architecture & Battery Optimization Strategy

Running a screen under intense sunlight forces the device’s display to maximum brightness, which is the primary source of battery drain. If the CPU is also churning through heavy UI rendering or complex map styling, the phone will thermal-throttle and kill the background process.

### The "Zero-Bloat" Local Pipeline

```
[Hardware GPS] ──(Native Background Service)──► [SQLite / Isar DB]
                                                        │
    ┌───────────────────────────────────────────────────┘
    ▼
[Flutter UI Layer] ──► Map Rendering (Vector-to-Bitmap caching)
                   ──► Dynamic Unit Compute (min/km vs km/h)
                   ──► Turn-back Prediction Engine (54% Threshold)
```

### Critical Optimization Rules

* **Background Isolate Separation:** The background tracking service must run on a separate native OS thread (Android Foreground Service with `Sticky` flag / iOS Background Tasks). It handles *only* raw GPS telemetry, calculates distance differentials via the Haversine formula, and writes directly to a fast, lightweight local database (Isar or SQLite). The Flutter UI should only wake up when the screen is active.
* **Sunlight-Optimized UI (High Contrast):** Instead of standard rich maps which chew processing power during pans/zooms, implement a primary **High-Contrast Light Mode** (white background, black indicators) for direct sunlight readability, and a secondary **Monochrome AMOLED Black Mode** for power saving, utilizing localized offline vector tiles (via **MapLibre Native** with local `.mbtiles`).

---

## 2. Feature-by-Feature Deep Dive & Logic

### A. The 54% "Fatigue-Aware" Turn-Back Engine

Instead of checking a flat 50% split, the app uses a **54% remaining countdown window** for timed runs. This leaves a 4% buffer ($54\% - 46\% = 8\%$ extra time allocation) to account for muscular fatigue, elevation climbs, or headwinds on the return leg.

* **Mathematical Logic:**
  $$T_{\text{target}} = \text{Total Allocated Time}$$
  $$T_{\text{elapsed}} = \text{Current Timestamp} - \text{Start Timestamp}$$
  $$\text{Time Remaining \%} = \left(1 - \frac{T_{\text{elapsed}}}{T_{\text{target}}}\right) \times 100$$

* **The Trigger:** When $\text{Time Remaining \%} \le 54\%$, fire a high-priority system notification and an audio cue: *"54% time remaining. Fatigue buffer active. It is time to turn back."*
* **Infinity Mode:** If selected, the app bypasses this countdown, running a standard chronometer that tracks indefinitely until a manual stop signal or an automated intent is received.

### B. Dynamic Velocity Unit Switching

To keep the screen clean, the app will dynamically flip between runner-centric pace ($\text{min/km}$) and cyclist-centric speed ($\text{km/h}$) based on a velocity threshold.

* **The Pivot Point:** $18 \text{ km/h}$ ($\sim 3:20 \text{ min/km}$). Anything below this is treated as a pedestrian pace; anything above is categorized as transit speed (cycling/driving).
* **Calculation Logic:**
  ```dart
  void updateVelocityMetrics(double metersPerSecond) {
    if (metersPerSecond <= 0) return;

    // Convert to km/h for the threshold check
    double kmh = metersPerSecond * 3.6; 

    if (kmh > 18.0) {
      currentDisplayUnit = "${kmh.toStringAsFixed(1)} km/h";
    } else {
      // Calculate minutes per kilometer
      double minPerKm = 16.6667 / metersPerSecond; 
      int minutes = minPerKm.floor();
      int seconds = ((minPerKm - minutes) * 60).round();
      currentDisplayUnit = "$minutes:${seconds.toString().padLeft(2, '0')} min/km";
    }
  }
  ```

### C. Geo-Tracker Grade Statistics Tab

To match Geo-Tracker's depth, the tracking loop must calculate and persist the following data points per node:

* **Moving Time vs. Total Time:** If velocity drops below $0.5 \text{ m/s}$ for more than 5 seconds, split the accumulator into "idle time" to maintain absolute average moving speed accuracy.
* **3D Distance:** Calculated using both lat/lon steps and raw altitude variations:
  $$\Delta d_{3D} = \sqrt{\Delta d_{\text{horizontal}}^2 + \Delta \text{elevation}^2}$$
* **True Bearing/Angle:** Calculated via the heading between the last two valid GPS coordinates.
* **Elevation Metrics:** Cumulative Elevation Gain (Climb) and Cumulative Elevation Loss (Descent), filtered with a low-pass smoothing threshold (e.g., ignoring vertical jitters under 1.5 meters).

---

## 3. Automation, Security, and File Systems

### Tasker & External Automation via App Intents

To make the app infinitely automatable, it exposes local Android Broadcast Receivers and iOS App Intents. This allows Tasker (or Automate/Shortcuts) to control the application without opening the GUI.

| Action Intent | Parameters | Target Behavior |
| :--- | :--- | :--- |
| `org.opensource.tracker.START_ACTIVITY` | `mode: "timed" \| "infinity"`, `duration_mins: 60` | Spawns foreground tracking service instantly, bypasses onboarding/main screen. |
| `org.opensource.tracker.STOP_ACTIVITY` | None | Halts tracking, renders statistics, triggers auto-GPX export. |
| `org.opensource.tracker.GET_CURRENT_STATS` | None | Returns a JSON string payload containing `distance`, `speed`, `elapsed_time`, and `turn_back_triggered`. |

### Secure, Local-First File Architecture

* **Silent Onboarding Target:** During the initial setup, the user selects a target directory via SAF (Storage Access Framework on Android) or File Documents Directory (iOS). This directory reference is securely persisted in native key-value storage.
* **Automated GPX Serialization:** The moment the user hits "Stop", a background isolate reads the coordinate tables from the local database, builds an un-scrambled, schema-compliant XML string, and streams it straight to the designated folder:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <gpx version="1.1" creator="OpenSourceTracker">
    <trk>
      <name>Activity_${DateTime.now().millisecondsSinceEpoch}</name>
      <trkseg>
        <trkpt lat="12.9716" lon="77.5946"><ele>920.1</ele><time>2026-07-10T13:30:00Z</time></trkpt>
      </trkseg>
    </trk>
  </gpx>
  ```
* **Full Database Zip Dump:** Under settings, a "Compress & Export" button bundles the entire database file (`.db` / `.isar`), any cached waypoint assets, and a clean index file into a standard `.zip` archive stored in the local downloads folder, ready for direct manual or automated uploading to Google Drive or Nextcloud.

---

## 4. Engineering Roadmap

To build this systematically, break the project down into four distinct structural milestones:

### Milestone 1: The Native Telemetry Core
* Implement an Android Foreground Service with a persistent notification layer to prevent OS execution kills.
* Set up a Core Location background session (`CLBackgroundActivitySession`) on iOS with fitness tracking constraints.
* Write a custom GPS filter utilizing a Kalman filter or basic speed-clipping to wipe out position "jumping" when stationary.
* Set up the local database layer with schema structures optimized for fast append writes.

### Milestone 2: Processing & Core Calculation
* Build the 54% turnaround calculations and register background system notification flags.
* Implement the dynamic velocity display conversion code.
* Expose the Broadcast Receivers to allow Tasker to issue `START` and `STOP` commands via broadcast intents or CLI commands.
* Register iOS `LongRunningIntent` structures to support remote background execution for Siri and Shortcuts.

### Milestone 3: Interface & Experience Flow
* Design a streamlined, permission-first onboarding flow that requests exact location permissions (Background and Foreground) and requests OS battery optimization exemptions.
* Select the local output backup folder via Storage Access Framework / iOS Documents selector.
* Develop the real-time activity and stats views using highly efficient canvas rendering instead of a complex array of heavy UI widgets.

### Milestone 4: Export Engines & Polish
* Write the streaming XML compiler for default background GPX generation.
* Build the comprehensive `.zip` backup pipeline.
* Document the public intent APIs within a clean, version-controlled markdown file in the project repository to encourage open-source community contributions.
