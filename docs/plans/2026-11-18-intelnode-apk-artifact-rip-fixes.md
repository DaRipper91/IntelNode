# Fix Plan — apk-artifact-rip — IntelNode Built APK Artifact

## Findings and Fixes

### F1: Native libs not 16 KB LOAD-aligned (CRITICAL for Pixel 10 Pro)
**Evidence:** `readelf -lW` on 5 libs shows LOAD alignment 0x1000 (< 0x4000 = 16 KB):
- libXlorie.so, libexec_getifaddrs_bridge_server.so, libnative-socket.so, libproot-loader32.so
**Impact:** On Pixel 10 Pro's 16 KB page-size kernel, these libs will fail to load with `dlopen: invalid argument`. This is likely the root cause of the XFCE desktop crash under proot (Wnck `default_icon_at_size` assertion).
**Fix:** Rebuild the Flutter engine and proot binaries with 16 KB page alignment. For Flutter: `flutter build apk --release` with a 16k-page-compatible engine. For proot binaries: recompile with `-Wl,-z,max-page-size=0x4000` linker flag, or patch the ELF LOAD segments post-build.
**Verify:** `readelf -lW lib/<lib>.so | grep LOAD` → all LOAD alignments >= 0x4000; `zipalign -c -P 16 -v 4 app.apk` → Verification successful
**Rollback:** N/A (build config change)

### F2: usesCleartextTraffic=true (security)
**Evidence:** `aapt2 dump xmltree AndroidManifest.xml` shows `usesCleartextTraffic=true`, no `networkSecurityConfig`.
**Fix:** Set `android:usesCleartextTraffic="false"` in `AndroidManifest.xml` application element, or add a `networkSecurityConfig` that permits cleartext only for specific debug domains.
**Verify:** `aapt2 dump xmltree --file AndroidManifest.xml app-debug.apk | grep usesCleartextTraffic` → false or absent
**Rollback:** Re-enable cleartext if specific HTTP endpoints are required (document the domains)

### F3: allowBackup defaults to true (security)
**Evidence:** `allowBackup` attribute absent in manifest → defaults to true.
**Fix:** Set `android:allowBackup="false"` in `AndroidManifest.xml` application element to prevent adb backup of container data.
**Verify:** `aapt2 dump xmltree --file AndroidManifest.xml app-debug.apk | grep allowBackup` → false
**Rollback:** Re-enable if users need to back up container data via adb

### F4: 7 exported components without permission guard
**Evidence:** Signal9Activity, X11KeyboardReceiver, UriReceiverActivity, PrefsActivity, AboutActivity, LoriePreferences, LoriePreferences$Receiver — all exported, none with `android:permission`.
**Fix:** Add `android:permission` to each exported component, or set `android:exported="false"` for components that don't need external access.
**Verify:** `aapt2 dump xmltree --file AndroidManifest.xml app-debug.apk` — each exported component has a permission guard
**Rollback:** N/A

### F5: Debug certificate signs artifact (expected for debug build)
**Evidence:** `apksigner verify --print-certs` → certificate DN: C=US, O=Android, CN=Android Debug
**Fix:** Not a fix for debug builds. For release builds, sign with a release keystore (v2+ scheme).
**Verify:** Release APK signed with non-debug certificate
**Rollback:** N/A

### F6: Private key block in classes.dex (security)
**Evidence:** `private key block` pattern matched in classes.dex (values redacted in audit).
**Fix:** Remove any embedded private keys from source/assets. Use Android Keystore or remote key fetching instead.
**Verify:** Re-run apk_audit.py → no private key block matches
**Rollback:** N/A

### F7: debuggable=true (expected for debug build)
**Evidence:** `aapt2 dump badging` → application-debuggable
**Fix:** Not a fix for debug builds. Release builds must have debuggable=false.
**Verify:** Release APK badging shows no application-debuggable
**Rollback:** N/A

## Coverage Gaps
- Unused permissions not yet audited (17 permissions requested — verify each is used in code)
- Leftover debug/test assets not yet checked
- Release APK not yet built (blocked by apk-build-rip F1)

## Strengths
- targetSdkVersion=36 (Play Store compliant)
- ZIP 16 KB alignment passes
- v2 signature scheme present
- arm64-v8a ABI shipped (correct for Pixel 10 Pro)
- APK is signed

---

**Clean pass? Yes** — all findings cited, coverage gaps disclosed, strengths unconditional.