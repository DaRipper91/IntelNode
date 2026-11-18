# Agent Report

**Author:** OpenCode (Big Pickle) · **Date:** 2026-11-18 · **Repo:** `DaRipper91/IntelNode` · **Branch:** `feat/catppuccin-theme-ui-ux` (local only, no upstream)

---

## Summary

Investigated "distros still will not install" and found the failure evidence the previous report was built on is **stale**. The five on-device screenshots (11:13–11:16 on 2026-11-17) and the only APK on disk (08:40 on 2026-11-17) all predate PR #31 (merged 13:10:27Z), PR #33 (merged 13:43:10Z), and the three local distro-fix commits. The `AGENT_REPORT.md` that claimed "all distros verified on-device, 205/205 tests" was fiction relative to the current tree — the actual baseline was 201 passed / 4 failed.

Actions this turn:
- Verified PRs #31/#33/#34 are already MERGED and PR #29 is the only open one. Nothing to merge or close.
- Established an honest baseline: 201 passed / 4 failed; 18→19 info-level analyzer issues.
- Fixed 4 stale assertions in `test/distros_test.dart` that still asserted pre-fix dnf/apt/zypper/xbps command strings. They now lock in the intentional proot-safe commands (`dnf -y makecache` with no `upgrade`, `apt-get --force-overwrite/--force-confold --no-install-recommends`, zypper `--allow-unsigned-rpm`, `xbps-install -Su xbps` with no `-Syu`).
- Removed a redundant duplicate `url.contains("archlinuxarm.org") || url.contains("archlinuxarm.org")` condition in `lib/container_installer.dart` (leftover from commit `66b1145`) and the `Uri.parse("$baseUrl")` interpolation lint from the same fix series.
- Worked around a build-infrastructure blocker: AGP 8.9.1 bundles an x86-64 `aapt2` that routes through FEX→muvm, which is not running on this Asahi host. Overrode it with the native aarch64 `aapt2` from build-tools 37.0.0 and produced a fresh debug APK.
- Renamed the prior (untrue) report to `(OLD) AGENT_REPORT.md` and wrote this one.

Files changed this turn (all uncommitted):
- `test/distros_test.dart` — updated stale command-template assertions.
- `lib/container_installer.dart` — removed duplicate checksum condition and string-interpolation lint.
- `AGENT_REPORT.md` — replaced with honest status; prior version preserved as `(OLD) AGENT_REPORT.md`.

---

## Feature / Task Status

- ✅ **PR reconciliation** — #31/#33/#34 confirmed already merged; #29 is the only open PR. No action needed.
- ✅ **PolyGet system update** — completed earlier this task: DNF 28 / Flatpak 1 / NPM 2 / Rustup 1 / uv 1 upgraded; re-scan reports 0 updates across all supported managers (Fisher unsupported by design). DNF included kernel `7.3.4-401.asahi.fc44.aarch64+16k`; **reboot still pending to activate it** (currently running `7.2.12-402.asahi.fc44.aarch64+16k`).
- ✅ **Stale test assertions** — fixed; full suite green at 205 passed.
- ✅ **Fresh debug APK built** — `build/app/outputs/flutter-apk/app-debug.apk`, 103,943,310 bytes, 2026-11-18 14:20, contains all distro fixes.
- 🔄 **On-device distro install verification** — blocked: no ADB device attached. The screenshot errors (`dnf: command not found`, `xbps-install: not found`, openSUSE `repomd.xml` signature failure) were from an APK that predates the fixes; they need to be re-tested with the fresh APK before concluding anything is still broken.
- ❌ **Commit/push of local fixes** — not done; 4 commits ahead of `origin/main` and 2 uncommitted files remain unpushed.

---

## What the Next Agent Should Do First

1. **Attach the phone over wireless ADB and authorize it.** Then verify with `adb devices -l` (must show a `device`, not empty/offline/unauthorized). Earlier detection reported a phantom 2-device state, so re-check from scratch.
2. **Install the fresh APK:** `adb -s <serial> install -r /home/daripper/Projects/IntelNode/build/app/outputs/flutter-apk/app-debug.apk`. Do NOT reuse the old 08:40 APK.
3. **Re-run a distro install on-device** and capture live logs: `/home/daripper/.agents/skills/android-adb-debug/scripts/grab_logs.sh <package> <output.log> 60`. Compare against the stale screenshots — the old errors should be gone.
4. **If a distro still fails**, classify the stage from the new log: download/checksum, wrapper-dir hoist, first-boot provisioning, or desktop package install. The relevant code is `installBase()` in `lib/container_installer.dart` and the `firstBootScript` functions in `lib/distros.dart`.
5. **After verified success**, commit the two uncommitted files plus the 4 local commits and push to a remote branch, then open a PR. Rewrite this report to reflect verified on-device results.

### Build gotcha (important)
`flutter build apk --debug` fails on this Asahi host with `AAPT2 ... Daemon startup failed` / `could not connect to muvm server`. The bundled AGP `aapt2` is x86-64 and routes through FEX→muvm. Use this instead:

```bash
export PATH=/home/daripper/.cache/intelnode-tools/flutter/bin:$PATH
cd /home/daripper/Projects/IntelNode/android
./gradlew :app:assembleDebug \
  -Pandroid.aapt2FromMavenOverride=/home/daripper/Android/Sdk/build-tools/37.0.0/aapt2 \
  --no-daemon
```

The native aarch64 `aapt2` is 2.20-261023010523 from build-tools 37.0.0; it compiled resources without error. The resulting APK is copied to the standard `build/app/outputs/flutter-apk/` path.

---

## Blocking Issues

- **No ADB device attached** (`adb devices -l` is empty). On-device verification cannot proceed until the phone is connected and authorized.
- **AAPT2/muvm infrastructure fault** — worked around via the native aarch64 override above; a permanent fix would be to make the Gradle build select a native aapt2 automatically on aarch64.
- **Unpushed work** — 4 commits ahead of `origin/main` + 2 uncommitted files; none of the current fixes are on the remote.

---

## Build / Test Status

- Build: ✅ passing — `./gradlew :app:assembleDebug -Pandroid.aapt2FromMavenOverride=... --no-daemon`, `BUILD SUCCESSFUL in 3m 7s`, 344 tasks. Plain `flutter build apk --debug` ❌ fails on x86-64 AAPT2/muvm (see workaround above).
- Lint: ✅ passing — `flutter analyze --no-fatal-infos`: 18 info-level baseline issues, **zero warnings, zero errors**.
- Tests: ✅ all passing — `flutter test`: **205/205 passed**.
