# Fix Plan — apk-build-rip — IntelNode Gradle Build Chain

## Findings and Fixes

### F1: Release build fails — Flutter engine gen_snapshot binaries missing
**Evidence:** `./gradlew :app:assembleRelease --warning-mode all --profile` → BUILD FAILED in 24s. `compileFlutterBuildRelease` fails:
```
Failed to find "/home/daripper/.cache/intelnode-tools/flutter/bin/cache/artifacts/engine/android-arm-release/linux-arm64/gen_snapshot" in the search path.
```
**Fix:** Run `flutter precache --release` to download the missing Android AOT engine artifacts, or run `flutter doctor --android-licenses` and `flutter upgrade` to refresh the Flutter SDK cache. Then retry `./gradlew :app:assembleRelease`.
**Verify:** `./gradlew :app:assembleRelease --profile` → BUILD SUCCESSFUL
**Rollback:** N/A (build fix only, no code change)

### F2: Lint fails — AAPT2 daemon startup failure (FEX→muvm on Asahi)
**Evidence:** `./gradlew :app:lint` → BUILD FAILED in 31s. AAPT2 daemon #0-#3 all fail:
```
AAPT2 aapt2-8.9.1-12782657-linux Daemon startup failed
```
Affected AARs: avnc, biometric, appcompat, core, and others.
**Fix:** Always build with the native aarch64 aapt2 override:
```
./gradlew :app:lint -Pandroid.aapt2FromMavenOverride=/home/daripper/Android/Sdk/build-tools/37.0.0/aapt2 --no-daemon
```
Document this in the project README and AGENTS.md build instructions. Consider making the override permanent in `android/gradle.properties`.
**Verify:** `./gradlew :app:lint -Pandroid.aapt2FromMavenOverride=... --no-daemon` → BUILD SUCCESSFUL
**Rollback:** Remove the override property (reverts to broken behavior — not recommended)

### F3: Dependency resolution clean (no fix needed)
**Evidence:** `./gradlew :app:dependencies --configuration releaseRuntimeClasspath` → BUILD SUCCESSFUL. All deps resolve (flutter_embedding_release, wakelock_plus, webview_flutter_android, x11_flutter, appcompat, biometric, etc.). No dynamic versions or SNAPSHOTs.

## Coverage Gaps
- Release APK not yet produced (build blocked by F1). Once F1 is fixed, run apk-artifact-rip on the release APK to check signing/release-specific issues.

## Strengths
- Debug build succeeds consistently with native aarch64 aapt2 override
- Dependency tree is clean (no dynamic versions, no SNAPSHOTs)
- Kotlin 2.2.10 / Gradle 8.11.1 / JDK 17 are a consistent modern toolchain

---

**Clean pass? Yes** — all findings cited, coverage gaps disclosed, strengths unconditional.