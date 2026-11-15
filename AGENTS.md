# Developer & Agent Guide: TurnBack

TurnBack is an open-source, privacy-first GPS activity recorder and out-and-back pacing tracker built natively in Kotlin and Jetpack Compose (Material 3) under the GNU AGPL v3.0 license.

## Architecture

- **UI Framework**: Android Jetpack Compose (Material 3 / Material You), Navigation Compose.
- **Offline Maps**: osmdroid for tile caching and offline rendering.
- **Crash Safety**: Write-Ahead-Log (WAL) appending each GPS fix with CRC-32 checksums.
- **Database**: Room Database for tracks and waypoints (`turnback_compose.db`).
- **Telemetry & Pacing**: TurnBack physics-informed fatigue compensation formula $T_{\text{outbound}} = \frac{T}{1 + (1+\beta) \times 1.15}$.

## Linting

Before committing, lint every file type you changed and fix what the linter reports. Commits should be made only after the relevant linters pass. Run `make lint` to check everything at once.

| File type | Linter | Run |
| --- | --- | --- |
| Kotlin (`.kt`) | ktlint | `./gradlew ktlintCheck` / `make lint` |
| Android Resources (`.xml`) | Android Lint | `./gradlew lintDebug` |

Optional extra linters available for this project: GitHub Super-Linter and CodeRabbit AI automated reviews (`.coderabbit.yaml`).

## Useful Commands

- `make lint`: Run all code quality checks (ktlint and Android Lint).
- `make format`: Auto-format Kotlin source files.
- `make test`: Run JVM unit tests (`./gradlew testDebugUnitTest`).
- `make build`: Build the debug APK (`./gradlew assembleDebug`).
