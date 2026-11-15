# TurnBack User Checklist & Comprehensive Use-Case Specification

> **App Overview:** TurnBack is an open-source, privacy-first GPS activity recorder and out-and-back pacing tracker built natively in Kotlin and Jetpack Compose (Material 3) under the GNU AGPL v3.0 license.

---

## 1. Primary Persona Use Cases & Scenarios

### Use Case 1: The Timed Trail Runner (Precision Out-and-Back Pacing)
- **User Story:** *"As a trail runner with a strict 60-minute window before dusk, I want to explore a new trail without worrying about losing track of time, knowing the app will calculate my fatigue and alert me at the exact moment to turn around."*
- **Key Interactions:**
  1. Open app $\to$ Select "Run" $\to$ Tap "60m".
  2. The app previews: *"Outbound Window: ~26 min before turn-around"*.
  3. Tap **"START RUN"** $\to$ HUD launches with glanceable Speed, Distance, and Time.
  4. At minute 26, phone vibrates with an SOS triple-pulse pattern, HUD switches to **"⚠️ TURN-AROUND TRIGGERED (Head Back Now)"**, and status bar notification alerts the runner.
  5. Runner turns around, finishes the return leg on time within 60 minutes.
- **Verification Checklist:**
  - [x] Outbound calculation matches $T_{\text{target}} / (1 + (1+\beta) \times 1.15)$.
  - [x] Live countdown reaches zero at the computed outbound limit.
  - [x] Haptic vibration and visual warning trigger reliably.

---

### Use Case 2: The Mountain Day Hiker (Summit & Sunset Safety)
- **User Story:** *"As a mountain hiker ascending 1,200m in remote terrain, I need accurate elevation gain tracking without GPS noise, the ability to pin water sources and campsites, and 100% offline maps."*
- **Key Interactions:**
  1. Tap map layer icon $\to$ select **OpenTopoMap** to view elevation contours.
  2. Tap **"START HIKE"** $\to$ phone stays in pocket, Foreground Service tracks in background.
  3. At a fresh mountain spring, hiker pulls out phone, taps **"MARKER"**, enters "Pure Spring", selects category **"Water Source"**, and taps "Add Pin".
  4. Near summit, drops a marker under **"Viewpoint / Summit"**.
  5. The interactive elevation profile displays smooth climb statistics filtered by the 3m hysteresis algorithm.
- **Verification Checklist:**
  - [x] Small GPS elevation jitter (< 3m) is filtered out and does not bloat vertical ascent.
  - [x] Waypoints appear as distinct pins on the map.
  - [x] Exported GPX contains valid `<wpt>` tags with `<sym>Water Source</sym>` and `<sym>Scenic Area</sym>`.

---

### Use Case 3: The Bikepacker & Road Cyclist (Glove-Friendly & Speed Gradient)
- **User Story:** *"As a cyclist on country backroads with thick gloves and phone on handlebars, I want large glanceable metrics, a speed gradient polyline, and large buttons I can tap without stopping."*
- **Key Interactions:**
  1. Phone mounted on bike stem $\to$ tap **"START CYCLE"**.
  2. Glanceable hero readouts show speed at $32\text{ sp}$ bold, easily legible at arm's length in sunlight.
  3. Polyline dynamically colors: Cyan for climbs/slow speed, Lime for cruising, Amber/Coral Red for fast descents.
  4. Floating action buttons (56dp diameter) allow 1-tap recentering and layer switching with gloves.
- **Verification Checklist:**
  - [x] Speed gradient colors polyline smoothly.
  - [x] 56dp FABs are easily clickable.
  - [x] Hero speed/pace readout updates in real-time.

---

### Use Case 4: Backcountry Wilderness (Zero Cell Signal & OLED Battery Eco Mode)
- **User Story:** *"As an outdoor explorer in an off-grid national park with zero cellular connectivity, I want my battery to last for 8+ hours while keeping full GPS track history."*
- **Key Interactions:**
  1. Switch phone to Airplane Mode.
  2. Tap the **OLED Eco Mode** leaf button in the HUD $\to$ screen background turns pure black (`#000000`), turning off OLED pixels.
  3. Stationary detection sleeps GPS calls when stopped for lunch.
  4. Offline tile caching renders previously visited map areas with zero data usage.
- **Verification Checklist:**
  - [x] App runs 100% offline without network permission errors.
  - [x] Pure black OLED palette active across all UI elements.
  - [x] Location tracking persists uninterrupted in background.

---

### Use Case 5: The Battery Death / Crash Survivalist (Crash-Proof WAL)
- **User Story:** *"As an athlete whose phone unexpectedly died at 2% battery on a 4-hour trek, I want to recharge my phone and have my entire track restored without losing a single coordinate."*
- **Key Interactions:**
  1. Phone shuts down abruptly mid-workout.
  2. Phone is recharged and powered back on.
  3. Open TurnBack $\to$ app detects `active_recording.wal`.
  4. Dialog appears: *"Recover Previous Session — A recording was interrupted unexpectedly. Would you like to restore and save it to your library?"*
  5. Tap **"Restore & Save"** $\to$ full track with all points and waypoints is parsed, verified via CRC-32, saved to Room DB, and exported to GPX!
- **Verification Checklist:**
  - [x] Every fix is flushed to disk with CRC-32 checksum.
  - [x] Corrupted or torn writes fail checksum and are safely dropped without throwing exceptions.
  - [x] Restored session matches exact points logged before crash.

---

### Use Case 6: The Interval & Marathon Trainer (1-km Split Lap Pacing)
- **User Story:** *"As a marathon runner doing a 10-km tempo run, I want to inspect my split pace, elapsed time, and elevation gain for every single kilometer."*
- **Key Interactions:**
  1. Complete workout $\to$ tap **"FINISH"**.
  2. Workout summary displays **1-KM LAP SPLITS** card:
     - Lap 1: 4:32 /km • 4m 32s • +5m / -2m
     - Lap 2: 4:28 /km • 4m 28s • +2m / -8m
     - Lap 3: 4:40 /km • 4m 40s • +14m / -0m
  3. Interactive profile chart allows scrubbing with finger to inspect exact instant pace at any distance.
- **Verification Checklist:**
  - [x] Cumulative distance split into sequential 1.0 km intervals.
  - [x] Net elevation gain and loss calculated per lap.
  - [x] Touch scrubber displays instant altitude and speed.

---

### Use Case 7: The Privacy Purist & F-Droid Community User
- **User Story:** *"As a privacy-focused user on a de-Googled phone (GrapheneOS / LineageOS), I want a GPS app with zero proprietary Google Play Services dependencies, zero analytics trackers, and GNU AGPL v3.0 license."*
- **Key Interactions:**
  1. Install APK on phone without Google Play Services.
  2. Location works via Android `LocationManager.GPS_PROVIDER`.
  3. Database stored in app-private SQLite (`turnback_compose.db`).
  4. No analytics, tracking tokens, or user accounts.
- **Verification Checklist:**
  - [x] No `com.google.android.gms` location dependencies.
  - [x] Zero telemetry SDKs in merged dependencies.
  - [x] GNU AGPL v3.0 license displayed in Settings.

---

### Use Case 8: Multi-App GPX Import & Sharing
- **User Story:** *"As a hiker who wants to send my route to my hiking group on WhatsApp or upload it to Strava, I want 1-tap GPX export and sharing."*
- **Key Interactions:**
  1. Open activity in **Track Library** $\to$ view **Detail Screen**.
  2. Tap the **Share icon** in the top bar.
  3. Android system share sheet appears with GPX file attached via `FileProvider`.
  4. Select WhatsApp, Signal, Google Drive, or Strava to send.
- **Verification Checklist:**
  - [x] Generated GPX 1.1 passes schema validation.
  - [x] Garmin `<gpxtpx:TrackPointExtension>` speed is included.
  - [x] `FileProvider` shares file with read permissions granted.

---

### Use Case 9: Night Runner / Rider (CartoDB Dark High-Contrast)
- **User Story:** *"As a night runner running through city streets, I want a dark vector map that preserves my night vision."*
- **Key Interactions:**
  1. Tap map layer button $\to$ select **CartoDB Dark**.
  2. Roads render in deep charcoal/black; cyan speed track shines in high contrast.
- **Verification Checklist:**
  - [x] Tile URL swaps to CartoDB Dark Matter.
  - [x] Polylines remain clearly legible against dark basemap.

---

### Use Case 10: The In-Route Trail Runner (Drinks Break, Ghost Track, Compass & Pocket Lock)
- **User Story:** *"As a trail runner on a technical forest trail, I want to view my previous route on the map to avoid getting lost, take a drinks break without ruining my pace or accumulating false GPS drift, and continue running without accidental touches ending my session."*
- **Key Interactions:**
  1. **Ghost Route Comparison:** While running, runner taps Library $\to$ opens last Sunday's trail run $\to$ taps **"Overlay on Run as Ghost Track"**. The map renders the past run as a translucent dashed purple line alongside their live cyan track.
  2. **Background Active Mini-Bar:** While browsing the Library, a persistent floating mini-player displays: `🟢 ACTIVE RUN • 24:18 • 4.15 km • 5:12/km` with a 1-tap return button.
  3. **Drinks Break & Continue:** Runner stops at a creek, pulls phone out, and taps **Pause**. The HUD displays **"DRINKS BREAK IN PROGRESS (Paused for 01:45)"**. Distance accumulation is frozen so stationary GPS jitter does not inflate total distance.
  4. **Water Stop Waypoint:** Runner taps **"💧 LOG WATER"** $\to$ instantly drops a water waypoint without typing.
  5. **Continue Run:** Runner taps the massive green **"CONTINUE RUN"** button $\to$ resumes seamlessly.
  6. **Trail Compass (Course-Up):** Runner toggles the Compass button $\to$ map dynamically rotates with the runner's bearing so forward on the trail is always "UP" on screen.
  7. **Pocket & Rain Lock:** Phone goes into running belt $\to$ runner taps the Padlock button to lock touch input. Accidental screen taps are blocked until tapped to unlock.
  8. **Accidental Finish Prevention:** If "FINISH" is tapped, a confirmation modal asks *"Finish & Save Workout?"* to prevent sweaty hands from accidentally discarding or prematurely terminating the session.
- **Verification Checklist:**
  - [x] Previous track loaded as `ReferenceTrack` and rendered as dashed ghost polyline.
  - [x] Background active mini-bar remains accessible across all navigation screens.
  - [x] Stationary GPS drift discarded while paused during a drinks break.
  - [x] 1-tap water waypoint logging.
  - [x] Haptic double-pulse vibrates on every 1-km split.
  - [x] Map orientation rotates dynamically in Course-Up mode.
  - [x] Pocket lock blocks accidental touches while displaying giant glanceable metrics.
  - [x] Finish confirmation dialog prevents accidental session ending.

---

## 2. Automated Test Verification Matrix

| Use Case | Component Under Test | Automated Test File | Status |
| :--- | :--- | :--- | :---: |
| **UC-1: Out-and-Back Pacing** | `TurnBackEngine.computeOutboundLimit` | `TurnBackEngineTest.kt` | ✅ PASS |
| **UC-2: Elevation Hysteresis** | `TurnBackEngine.computeStats` (3m threshold) | `TurnBackEngineTest.kt` | ✅ PASS |
| **UC-2: Waypoints & Categories** | `GpxExporter` `<wpt>` serialization | `GpxServiceTest.kt` | ✅ PASS |
| **UC-5: Crash-Proof WAL Logging** | `RecordingWal.append` & `recover` | `RecordingWalTest.kt` | ✅ PASS |
| **UC-5: Torn-Write Drop Protection** | `RecordingWal.recover` with CRC failure | `RecordingWalTest.kt` | ✅ PASS |
| **UC-6: 1-km Lap Split Intervals** | `TurnBackEngine.computeSplits` | `TurnBackEngineTest.kt` | ✅ PASS |
| **UC-8: GPX 1.1 Export & Extension** | `GpxExporter.buildGpxString` | `GpxServiceTest.kt` | ✅ PASS |
| **UC-10: Ghost Track & Drinks Break** | `ReferenceTrack` & `RecordingWal.appendBreak` | `UserUseCasesTest.kt` | ✅ PASS |
| **UC-10: Canopy Jitter & Speed Smoothing** | Moving vs stopped threshold & rolling average | `UserUseCasesTest.kt` | ✅ PASS |
