I have a Flutter application that I want to structure into two distinct build flavors within the same repository:
1. `offline`: Purely local/offline execution with zero cloud/sync dependencies and minimal footprint.
2. `colab`: Adds collaboration, cloud sync, and network hooks on top of the shared offline base.

I develop on a dual-core 2017 MacBook Air (8GB RAM, 256GB SSD) and test exclusively on a physical ARMv8 (64-bit ARM / `android-arm64`) device. I need build efficiency, fast iteration times, and no redundant compilation steps.

Please implement the following architecture:

### 1. Flutter Multi-Entrypoint Architecture
- Create `lib/main_offline.dart` (entrypoint for the Offline flavor) and `lib/main_colab.dart` (entrypoint for the Colab flavor).
- Structure the dependency injection or app configuration such that Dart compiler tree-shaking drops all Colab/network dependencies when compiling `main_offline.dart`.
- Use deferred loading (`deferred as`) or conditional adapter injection for heavy collaboration modules in `main_colab.dart`.

### 2. Android Product Flavors Configuration (`android/app/build.gradle`)
- Configure `flavorDimensions "default"` (or `"mode"`).
- Define two product flavors:
  - `offline`:
    - `applicationId`: `com.app.offline`
    - `manifestPlaceholders = [appName: "App (Offline)"]`
    - `versionNameSuffix "-offline"`
  - `colab`:
    - `applicationId`: `com.app.colab`
    - `manifestPlaceholders = [appName: "App (Colab)"]`
    - `versionNameSuffix "-colab"`
- Ensure both APKs can be installed side-by-side on the same physical phone.

### 3. Build & Memory Tuning for Dual-Core / 8GB RAM Mac
- Configure `android/gradle.properties` optimized for a dual-core CPU and limited RAM:
  - Cap JVM heap (`org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC`).
  - Restrict workers (`org.gradle.workers.max=2`).
  - Enable caching (`org.gradle.caching=true`) and disable parallel tasks (`org.gradle.parallel=false`).
- Ensure debug configurations use `minSdkVersion 21+` to enable instant native multidex and prevent legacy dex compilation overhead.

### 4. Fast CLI Build/Run Commands & Scripts
Provide exact CLI commands and a lightweight helper script / Makefile / aliases for:
- Fast debug running on the connected phone targeting only ARMv8 (`--target-platform android-arm64`):
  - `flutter run -t lib/main_offline.dart --flavor offline --target-platform android-arm64`
  - `flutter run -t lib/main_colab.dart --flavor colab --target-platform android-arm64`
- Building release single-ABI APKs:
  - `flutter build apk -t lib/main_offline.dart --flavor offline --target-platform android-arm64`
  - `flutter build apk -t lib/main_colab.dart --flavor colab --target-platform android-arm64`

Generate the complete configuration files, file directory structure, and boilerplate code to implement this setup immediately.
