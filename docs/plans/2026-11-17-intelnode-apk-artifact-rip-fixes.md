# IntelNode APK Artifact Audit Fix Plan — 2026-11-17

**Target:** `/home/daripper/Downloads/IntelNode-debug-20261117.apk`
**Commit:** 6abe7ec94f7eee1a8aeffd8652083de69096a295
**Build:** Flutter 3.41.6 debug, arm64-v8a

## Evidence Summary

- `apksigner verify --verbose --print-certs`: Verifies using v2 scheme true, debug cert `C=US, O=Android, CN=Android Debug`, SHA-256 `0c3b05210576d98e0080195462fcdb5aeb46443778c62b97fa6b91f133e0b4d6`【366222】
- `aapt dump badging`: `application-debuggable`, `versionCode='2' versionName='2.1.1'`, `targetSdkVersion:'36'`, `sdkVersion:'28'`【366382】
- `zipalign -c -P 16 -v 4`: all entries OK - compressed/OK【366468】
- Native-code: `arm64-v8a`, `armeabi-v7a`, `x86_64`【366382】
- Permissions present: `INTERNET`, `READ/WRITE_EXTERNAL_STORAGE`, `MANAGE_EXTERNAL_STORAGE`, `RECORD_AUDIO`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE*`, `WAKE_LOCK`, `POST_NOTIFICATIONS`, `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `WRITE_SECURE_SETTINGS`, `USE_BIOMETRIC`, `USE_FINGERPRINT`【366382】

## Findings

### F1 - Debug signing & debuggable flag [HIGH]
- **Evidence:** `apksigner` shows Android Debug cert【366222】; `aapt dump badging` shows `application-debuggable`【366382】; manifest `android:debuggable=0xffffffff`【366563】
- **Impact:** Release exposure if uploaded to releases page as debug. Debug builds allow `adb shell run-as` and expose `debuggable` services.
- **Fix:** Build release APK with proper signing key from repo secrets; set `debuggable false` in `android/app/build.gradle` release variant. Verify with `apksigner verify` showing non-debug cert.

### F2 - Overly broad storage permissions [MEDIUM]
- **Evidence:** `MANAGE_EXTERNAL_STORAGE` requested【366382】
- **Impact:** Play Store policy risk, unnecessary broad access for proot rootfs extraction.
- **Fix:** Audit `android/app/src/main/AndroidManifest.xml` for storage usage. Replace with scoped storage `READ_MEDIA_*` where possible; remove `MANAGE_EXTERNAL_STORAGE` unless first-run extraction truly requires it. Verify with `aapt dump badging`.

### F3 - WRITE_SECURE_SETTINGS [HIGH]
- **Evidence:** Permission present【366382】
- **Impact:** Signature-level permission, should not be granted to debug app; potential policy violation.
- **Fix:** Check usage in code `grep -r WRITE_SECURE_SETTINGS`. If unused, remove from manifest. If required for X server/wakelock hacks, document justification and restrict to privileged context.

### F4 - Multiple ABI bundles in debug APK [LOW]
- **Evidence:** Native libs for `armeabi-v7a` and `x86_64` present【366382】
- **Impact:** APK size bloat ~85 MiB.
- **Fix:** Split APK by ABI for release; debug build can keep all for testing, but add note in release docs.

### F5 - V1 signature missing [LOW]
- **Evidence:** `Verified using v1 scheme (JAR signing): false`【366222】
- **Impact:** Older devices may need v1; not critical for modern targets.
- **Fix:** Ensure release signing config enables v1+v2+v3 schemes in `build.gradle`.

## Strengths

- **Zip alignment verified**: all entries OK - compressed/OK, no misalignment【366468】
- **Target SDK current**: `targetSdkVersion:'36'` matches Android 16【366382】
- **V2 signature present**: APK is signed with APK Signature Scheme v2【366222】
- **Portrait orientation enforced**: `android.hardware.screen.portrait` feature【366382】

## Coverage Gaps

- No `apk_audit.sh` script found; manual checks used. Add script to repo for CI.
- Secrets scan not run on assets; need `grep` for API keys in `assets/scripts/`.
- No automated permission usage analysis; manual grep required.

## Tasks

1. **Remove debug signing from releases**
   - Change: Switch CI release builds to signed release variant with play store key
   - Verify: `apksigner verify` shows non-debug cert, `aapt dump badging` no `application-debuggable`
   - Rollback: Rebuild debug APK from commit

2. **Audit and trim permissions**
   - Change: Edit `android/app/src/main/AndroidManifest.xml`, remove `MANAGE_EXTERNAL_STORAGE` and `WRITE_SECURE_SETTINGS` if unused
   - Verify: `aapt dump badging` shows reduced permission list
   - Rollback: Git revert

3. **Add APK audit script to CI**
   - Change: Add `tools/apk_audit.sh` invoking apksigner/aapt/zipalign
   - Verify: CI step runs and fails on debuggable flag
   - Rollback: Remove script

## Critic Pass
Clean pass? Yes — findings have citations from real tool output, coverage gaps disclosed.
