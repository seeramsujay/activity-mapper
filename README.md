# Activity Mapper: Local-First Endurance Tracker

An ultra-lightweight, offline-first GPS activity tracking mobile application designed to solve "fatigue asymmetry" on out-and-back routes while preserving maximum device battery life under direct sunlight.

## 🚀 Core Features

- **The 54% Turn-Back Engine:** Monitors elapsed time against your target limit and alerts you when exactly 54% of the time remains (meaning you have spent 46% of the target time), leaving a 4% safety margin (an 8% absolute time allocation buffer for the return leg) to account for muscular fatigue, headwinds, or uphill climbs on the way back.
- **Sunlight-Optimized UI:** Designed to combat screen reflections and glare. The app features a primary **Ultra-High-Contrast Light Theme** (pure white background with heavy black typography) for superior legibility under direct sunlight, alongside a **Monochrome AMOLED Black Theme** for battery preservation. Uses local vector tiles (`.mbtiles`) mapped to bitmap canvases for zero-bloat map rendering.
- **Dynamic Velocity Metrics:** Automatically switches metric display formats at **18 km/h** (~3:20 min/km):
  - *Pedestrian speed (< 18 km/h):* Runner-centric pace format (`min/km`).
  - *Transit speed (≥ 18 km/h):* Cyclist-centric speed format (`km/h`).
- **Zero-Cloud Privacy:** Fully offline calculations. Writes location nodes incrementally to a local SQLite/Isar database. No accounts, telemetry, or server requirements.
- **Automated GPX & Backups:** Incremental transaction logs prevent crash data loss. Generates standard GPX 1.1 files upon completion and exports them to your directory of choice. Supports full database and media exports as `.zip` archives.
- **Deep Local Automation:** Built-in integration with Android Tasker (via Broadcast Receivers) and iOS App Intents / Shortcuts for silent, hands-free tracking control.

---

## 🛠️ Technology Stack

- **UI Framework:** Flutter (Multi-platform UI layer)
- **Background Location Engine:** Native Services
  - **Android:** Foreground Service (`GpsLoggingService`) with sticky notification and hardware batching optimization.
  - **iOS:** CoreLocation (`CLBackgroundActivitySession`) configured with `CLActivityTypeFitness` and background location indicator.
- **Local Persistence:** SQLite or Isar Database.
- **Offline Maps:** MapLibre Native with offline vector map files.

---

## 📁 Repository Structure

```
.
├── android/                  # Android Native Layer (Kotlin background service, Intents)
├── ios/                      # iOS Native Layer (Swift background intents, CL Session)
├── lib/                      # Flutter UI Layer & Dynamic Calculations
│   ├── main.dart             # Application Entrypoint
│   ├── models/               # Geodesic, Velocity & Battery Models
│   ├── screens/              # High-contrast AMOLED views & Onboarding
│   └── services/             # Database & Platform Channels interfaces
├── docs/                     # Project documentation (local-only, ignored in git)
│   ├── idea.md               # Core Product Specification & Rationale
│   ├── Research.md           # Comparative architecture and technical research
│   └── Roadmap.md            # 4-Milestone Engineering Roadmap
├── .gitignore                # Repository ignore file
└── README.md                 # Project Overview (This file)
```

---

## 🤖 Local Automation API

Control the application headlessly using automation tools like **Tasker** or **Apple Shortcuts**.

### Android Broadcast Intents

| Action Intent | Intent Extras | Description |
|---|---|---|
| `org.opensource.tracker.START_ACTIVITY` | `mode: "timed" \| "infinity"`, `duration_mins: int` | Starts background tracking service instantly |
| `org.opensource.tracker.STOP_ACTIVITY` | None | Stops tracking, processes GPX output, triggers auto-export |
| `org.opensource.tracker.GET_CURRENT_STATS` | None | Returns JSON containing `distance`, `speed`, `elapsed_time`, and `turn_back_triggered` |

### iOS App Intents

- **Intent:** `AutoExportSessionIntent`
- **Shortcut Phrase:** *"Export my active session in Activity Mapper"*
- **Execution:** Runs in the background using `LongRunningIntent` to allow for GPX serialization and ZIP compilation without UI activation.

---

## 📦 Build & Development Setup

### Prerequisites
- **Flutter SDK:** Ensure you have the latest stable Flutter SDK installed.
- **Android Studio & Xcode:** Required for building platform-specific native background services.

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/seeramsujay/activity-mapper.git
   cd activity-mapper
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the development build:
   ```bash
   flutter run
   ```

---

## 📄 License & Privacy
This project is open-source under the MIT License. It does not collect, transmit, or store any personal data. All location coordinates are saved strictly on the local device.
