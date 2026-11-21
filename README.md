<p align="center">
  <img src="assets/logo.svg" alt="TurnBack logo" width="120" height="120" />
</p>

<h1 align="center">TurnBack</h1>

<p align="center">
  A privacy-first, fully offline GPS activity recorder with an out-and-back "turn around now" alarm,
  and serverless, end-to-end encrypted group tracking.
</p>

TurnBack is a native Android app written in Kotlin and Jetpack Compose (Material 3). There is no account, no cloud and
no tracking: your tracks live on your phone as standard GPX files plus a local database.

## Features

### Recording that survives the real world

- **Foreground GPS service** with a partial wake lock, so recording continues with the screen off.
- **Crash-proof write-ahead log:** every fix is appended to disk with a CRC-32 checksum. If the app is killed or the
  battery dies, the next launch offers to recover the session.
- **GPS health banner:** missing permission, GPS switched off, searching for a fix and weak signal are all shown,
  never silently ignored.
- **Record profiles and filters** (Settings): sampling interval, accuracy tolerance, minimum distance, and optional
  speed/jump sanity filters. Stationary jitter is kept out of your moving time.
- Activity types: run, hike, cycle, walk and car. Optional haptic and audio alerts.

### Out-and-back turn-around alarm

Set how long you want to be out in total. TurnBack computes when to turn around so the slower return leg still fits:

```text
T_outbound = T_total / (1 + (1 + buffer) x fatigue)
```

The fatigue factor and safety buffer are configurable. The alarm fires once, even with the screen off.

### Maps

- OpenStreetMap, topographic, dark and humanitarian layers, with offline tile download for a region.
- Live track, "follow me" that stops when you pan away (Recenter to resume), course-up or north-up.
- Ghost track: overlay a previous activity to race your past self.
- Waypoints with categories and a one-tap water-stop marker.

### Library and analysis

- Saved activities with route map, elevation profile and per-kilometre splits.
- **GPX import and export:** open a `.gpx` from any app, or use the import button in the library. Multi-segment files
  are handled correctly (gaps between segments never count as distance or climbing).
- Metric or imperial units, light, dark, system and OLED themes.

### Group tracking (no server)

Host a group or join one by QR code or invite link and see everyone live on the map:

- Teammate markers with breadcrumb trails, distance and speed.
- **Gap alert** when someone falls behind more than a distance you choose.
- One-tap messages (regroup, water, sprint, hazard, SOS) and shared pins that appear on every map.
- Works over the same Wi-Fi or phone hotspot automatically. Across networks, the host's invite carries its public
  address (found with STUN); if a carrier blocks the return path, scan a teammate's code to open it.
- Everything is encrypted with AES-256-GCM using a key that only exists in the invite. Anyone holding the invite can
  join, so share it only with people you trust. Invite links look like `turnback://mesh?...`.
- The protocol is wire-compatible with the earlier Flutter build of this project.

## Install

Download the APK for your device from the project's Releases page, or from the `turnback-debug-apk` artifact of the
latest successful CI run. Allow installing from unknown sources if prompted.

Permissions: precise location (recording), notifications (the recording notification), and optionally the camera
(only to scan a group QR code). Internet is used solely for map tiles and STUN.

## Development

Builds, linting and tests run on GitHub Actions, not locally. Every pull request is checked by:

| Check | What it does |
| --- | --- |
| Kotlin Linter and Test | ktlint, JVM unit tests, and a debug APK uploaded as an artifact |
| MegaLinter | Secrets, workflow and config validity, links, shell and YAML hygiene |
| CodeQL, GitGuardian | Static analysis and secret scanning |
| CodeRabbit | Automated code review (see `.coderabbit.yaml`) |

Project layout:

```text
app/src/main/java/org/opensource/tracker/
  data/        Room database, GPX import/export, write-ahead log, offline maps, settings, group mesh
  domain/      Track model, statistics, the turn-back engine
  service/     Foreground recording service
  ui/          Compose screens: map, library, detail, settings, group sheet
```

See `AGENTS.md` for contributor conventions.

## License

GNU Affero General Public License v3.0. See `LICENSE`.

Created by Sujay Seeram.
