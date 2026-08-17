# Project Concept: Out-and-Back Endurance Tracker (Idea)

## 1. The Core Problem: The "Fatigue Asymmetry"
When athletes perform out-and-back training sessions (running, hiking, cycling, or kayaking), they face a hidden psychological and physiological trap: **Fatigue Asymmetry**. 

Standard route planning assumes a symmetrical effort: running out for 30 minutes means you can return in 30 minutes, completing a 1-hour workout. However, in the real world:
- **Cumulative Fatigue:** Muscular efficiency drops during the second half of the workout, slowing pace.
- **Environmental Factors:** A headwind, temperature rise, or elevation climb on the return leg can disproportionately drain resources.
- **Safety Risks:** In backcountry settings, running out of battery or physical strength before reaching the starting point can lead to emergency situations.

Most mainstream fitness trackers (Strava, Garmin, Apple Workouts) focus on post-hoc logging rather than active out-and-back management. They do not warn you when it is time to turn around to ensure you make it back safely with your remaining energy and battery.

---

## 2. The Solution: A Local-First, Battery-Optimized Endurance Companion
This project is an **ultra-lightweight, 100% offline-first, serverless GPS activity tracking application** designed specifically to solve fatigue asymmetry while preserving maximum device battery and running smoothly even on budget devices with **2GB RAM** under harsh environmental conditions (like direct sunlight).

### Key Architectural Pillars

```
                      +-----------------------------+
                      |    Hardware GPS Telemetry   |
                      +--------------+--------------+
                                     |
                                     v
                      +-----------------------------+
                      |  Native Background Service  | <--- Tasker / Shortcuts Intents
                      |  (Kotlin FGS / Swift CL)    |
                      |  * Kalman Filter Smoothing  |
                      |  * Adaptive Stop Detection  |
                      +--------------+--------------+
                                     |
                         [Writes to SQLite WAL Mode]
                                     v
                      +-----------------------------+
                      |    Local SQLite Database    | (100% Offline & Serverless)
                      +--------------+--------------+
                                     |
                         [Zero-Jank UI Data Stream]
                                     v
                      +-----------------------------+
                      |      Flutter UI Layer       |
                      |  * High-Contrast Light/Dark |
                      |  * RDP Polyline Decimator   |
                      |  * RepaintBoundary Canvas   |
                      +--------------+--------------+
                                     |
                         [Post-Run & Export Engine]
                                     v
                      +-----------------------------+
                      |   Multi-Format ZIP Export   |
                      |   * GPX 1.1 + KML + GeoJSON |
                      |   * CSV + SQLite DB Snapshot|
                      |   * Crop, Merge & Split Ops |
                      +-----------------------------+
```

1. **The 54% "Fatigue-Aware" Turn-Back Engine:**
   Instead of a naive 50% turnaround split, the app uses a customizable **54% remaining countdown window** for timed runs. This creates a **4% safety buffer** (giving $54\% - 46\% = 8\%$ extra time/energy allocation for the return leg) to mitigate muscle fatigue, elevation gains, or headwinds.

2. **Sunlight-Optimized High-Contrast UI:**
   Direct sunlight forces smartphone screens to run at maximum brightness, contributing to thermal throttling and rapid battery drain. The app defaults to an **Ultra-High-Contrast Monochrome Light Theme** (pure white background with thick black typography and indicators) to maximize readability under glare, alongside an **AMOLED Black Theme**. Minimalist vector canvas rendering keeps GPU and CPU cycles near zero.

3. **Dynamic Velocity Unit Switching:**
   To maintain a clean, glanceable screen while running or cycling, the interface dynamically flips display formats at a threshold of **18 km/h** (~3:20 min/km) using a 5-second hysteresis state machine:
   - **Below 18 km/h (Pedestrian):** Displayed in runner-centric pace (**min/km**).
   - **Above 18 km/h (Cyclist/Transit):** Displayed in speed (**km/h**).

4. **100% Serverless, Private-First Architecture:**
   - **Zero Cloud:** No accounts, no external tracking servers, no telemetry pings, and no cloud dependency.
   - Raw location nodes are written incrementally to a fast local SQLite database with **Write-Ahead Logging (WAL)** enabled to guarantee zero data loss during OS process kills or crashes.

5. **Multi-Format Export Bundle in a Single `.zip` Package:**
   - One-tap export to all industry standard formats:
     - **GPX 1.1:** XML trackpoints with elevations, ISO timestamps, and speed extensions.
     - **KML:** Google Earth Placemarks and styled 3D LineStrings.
     - **GeoJSON:** RFC 7946 FeatureCollection for GIS software and web visualizers.
     - **CSV:** Metrics spreadsheet (timestamp, UTC datetime, lat, lng, elevation, speed, accuracy).
     - **turnback.db:** Direct SQLite database snapshot.
   - Outputs everything cleanly into a versioned `.zip` archive per session or as a complete lifetime backup.

6. **Post-Run Adjustment & Trip Editing Suite:**
   - **Visual Crop / Trim:** Dual-handle visual range slider on an auto-scaled vector map preview to trim warmup/cooldown tails, dynamically recalculating total distance and duration.
   - **Session Merge:** Merge multiple separate activities chronologically into a single seamless workout.
   - **Equal N-Parts Chopper:** Splits coordinate arrays into $N$ equal-length sub-trips.
   - **Time-Duration Splitter:** Chops recordings into fixed duration blocks (e.g. 10-minute intervals).

7. **Extreme Battery & 2GB RAM Optimizations:**
   - **Stationary / Stop Detection:** If speed falls below $0.2\text{ m/s}$ or coordinates shift less than $1.5\text{ m}$ for 3 consecutive updates, the background service throttles GPS polling from $1\text{–}5\text{ s}$ down to a $30\text{–}60\text{ s}$ power-save cycle. The moment movement is detected, full-rate GPS polling is restored instantly.
   - **Ramer-Douglas-Peucker (RDP) Polyline Decimation:** Dynamically downsamples thousands of raw coordinate points down to visual screen resolution for canvas painting, avoiding high vertex buffer allocations on 2GB RAM phones.
   - **RepaintBoundary & Scoped Rebuilds:** Keeps CPU and GPU wakeups isolated only to changing counter digits.

8. **Headless OS Automation:**
   Exposes native receivers (Android Broadcasts, iOS App Intents) allowing users to control tracking silently in the background via automation suites like **Tasker** or **Apple Shortcuts**:
   - **Android broadcasts:** `org.opensource.tracker.START_ACTIVITY`, `org.opensource.tracker.STOP_ACTIVITY`, and `org.opensource.tracker.GET_CURRENT_STATS`.

---

## 3. User Personas

### Persona A: "The Off-Grid Trail Runner"
- **Needs:** High-contrast readability, offline mapping in areas without cell coverage, safety buffers on remote trails, low RAM consumption.
- **Workflow:** Sets a target time of 90 minutes. App alerts them at 41.4 minutes (46% elapsed, leaving 54% remaining) with a loud audio cue to turn back. Offline vector maps show the exact route taken to backtrack safely.

### Persona B: "The Battery-Saving Cyclist"
- **Needs:** High readability under direct sunlight, low battery consumption, hands-free operation.
- **Workflow:** Mounts the phone on handlebars. Light UI cuts through direct sunlight glare. At speeds above 18 km/h, it automatically flips from pace to speed display. When stopping at a traffic light or rest stop, GPS automatically throttles to 30-second sampling.

### Persona C: "The Power User & Data Archivist"
- **Needs:** Zero cloud lock-in, multi-format export, post-run track adjustments.
- **Workflow:** Finishes a run, trims the first 2 minutes of stationary warmup using the Crop slider, merges it with a second stage run, and exports the entire workout package as a single `.zip` file containing GPX, KML, GeoJSON, and CSV files for offline analysis.

---

## 4. Implementation Milestones
- **Milestone 1: Native Telemetry & Kalman Filter:** Background foreground service, Kalman smoothing, stop detection, and SQLite WAL storage.
- **Milestone 2: 54% Turnaround Engine & Automation:** Dynamic unit switching, countdown threshold alerts, Tasker broadcast receiver.
- **Milestone 3: 2GB RAM & Low-Power Optimization:** RDP polyline decimation, RepaintBoundary canvas isolation, lightweight monochrome UI.
- **Milestone 4: Post-Run Editing & Multi-Format ZIP Engine:** Crop sliders, session merge, N-chop/time-chop, GPX 1.1, KML, GeoJSON, CSV, and unified ZIP exporter.
