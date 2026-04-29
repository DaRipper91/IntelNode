# DaRipped Tiny Computer — Developer Debugging Reference

**App version:** 2.0.7 · **Package ID:** `com.daripper91.daripped` · **Target:** Android ARM64

> This is a developer/power-user reference. For end-user troubleshooting, see **[MANUAL.md §5](MANUAL.md#5-troubleshooting-guide)**.

---

## Table of Contents

1. [Key Paths](#1-key-paths)
2. [Getting Logs](#2-getting-logs)
3. [Inspecting the Container Filesystem via ADB](#3-inspecting-the-container-filesystem-via-adb)
4. [Common Initialization Failures](#4-common-initialization-failures)
5. [Shizuku / rish Debugging](#5-shizuku--rish-debugging)
6. [VNC / Display Debugging](#6-vnc--display-debugging)
7. [Filing a Bug Report](#7-filing-a-bug-report)

---

## 1. Key Paths

| Purpose | Path |
|---|---|
| App data root | `/data/user/0/com.daripper91.daripped/files/` |
| Container rootfs | `/data/user/0/com.daripper91.daripped/files/containers/0/` |
| Bootstrap binaries | `/data/user/0/com.daripper91.daripped/files/bin/` |
| Bootstrap libraries | `/data/user/0/com.daripper91.daripped/files/lib/` |

---

## 2. Getting Logs

### ADB logcat (filtered)

Stream only lines relevant to the app, proot, and VNC:

```bash
adb logcat -v time | grep -E "daripped|proot|TigerVNC"
```

For a broader sweep that also catches Flutter framework errors:

```bash
adb logcat -v time | grep -E "daripped|proot|TigerVNC|flutter|dart"
```

### Full ADB bug report

Captures logcat history, system state, ANR traces, and crash dumps:

```bash
adb bugreport bugreport.zip
```

Alternatively, on the device: **Developer Options → Take Bug Report**.

### Flutter logs during development

When running from source with a connected device:

```bash
flutter logs
```

Or combined with a run:

```bash
flutter run --verbose 2>&1 | tee flutter_run.log
```

---

## 3. Inspecting the Container Filesystem via ADB

### Browse the rootfs

```bash
adb shell
# Navigate to the container root
ls -la /data/user/0/com.daripper91.daripped/files/containers/0/
```

> **Note:** `adb shell` runs as the `shell` user (`uid=2000`). You may not have read access to app-private files without root or Shizuku. Use `rish` (see §5) for elevated access.

### Check bootstrap binaries

Verify that critical binaries exist and are marked executable:

```bash
adb shell ls -la /data/user/0/com.daripper91.daripped/files/bin/
```

Key binaries to look for: `proot`, `busybox`, `login`.

Check a specific binary:

```bash
adb shell file /data/user/0/com.daripper91.daripped/files/bin/proot
# Expected: ELF 64-bit LSB executable, ARM aarch64
```

### Verify LD_LIBRARY_PATH contents

```bash
adb shell ls -la /data/user/0/com.daripper91.daripped/files/lib/
```

Expected shared libraries: `libacl.so`, `libattr.so`, `libcap.so`, and their versioned symlinks.

To check what a binary resolves at runtime (requires root or rish):

```bash
rish -c "LD_LIBRARY_PATH=/data/user/0/com.daripper91.daripped/files/lib \
  /data/user/0/com.daripper91.daripped/files/bin/proot --version"
```

---

## 4. Common Initialization Failures

| Symptom | Likely Cause | Fix / Status |
|---|---|---|
| `Unable to load asset: "assets/patch.tar.gz"` | Asset missing from APK at build time | Rebuild APK; confirm `patch.tar.gz` is listed in `pubspec.yaml` under `assets:` |
| `LateInitializationError: G.currentContainer` | Container index accessed before initialization | **Fixed in v2.0.1** — update the app |
| `startnovnc: command not found (exit 127)` | Script called wrong command name in the Arch rootfs | **Fixed in v2.0.6** — update the app |
| VNC resolution not applying after settings change | Resolution passed before VNC process restarted | **Fixed in v2.0.6** — update the app |
| Blank screen on Pixel 10 Pro / Android 16 | `Future.delayed(Duration.zero)` blocked first Flutter frame; missing `colorSchemeSeed` fallback | **Fixed in v2.0.3** — update the app |
| `proot: cannot connect to namespace socket` | proot SELinux policy denial on Android 13+ | Enable Shizuku (see §5); see also [MANUAL.md §3.6](MANUAL.md#36-enabling-shizuku-for-enhanced-performance) |

### Diagnosing asset failures

If you see `Unable to load asset`, confirm the asset is declared and present:

```bash
# In the project root
grep -A 20 "assets:" pubspec.yaml
ls -lh assets/patch.tar.gz
```

Then verify it was bundled into the APK:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep patch.tar.gz
```

---

## 5. Shizuku / rish Debugging

Shizuku grants the app ADB-level shell access via the `rish` binary, bypassing many SELinux restrictions that block proot on stock Android.

### Verify rish is available

```bash
sh -c 'command -v rish'
# Should print the path to rish, e.g. /data/user/0/moe.shizuku.privileged.api/rish
```

### Test rish execution

```bash
rish -c 'id'
# Expected output: uid=2000(shell) gid=2000(shell) ...
```

### Confirm ShizukuHelper detected Shizuku

Filter logcat for the detection event:

```bash
adb logcat -v time | grep -i "shizuku"
# Look for: "Shizuku available" or "ShizukuHelper: bound"
```

If Shizuku is installed but not detected:
1. Confirm Shizuku is **running** (its persistent notification should be visible)
2. Reboot the device — Shizuku requires re-activation after each reboot via USB/wireless debugging
3. Grant the app Shizuku permission in the Shizuku app UI

---

## 6. VNC / Display Debugging

### Check VNC server process (inside the container)

Open the in-app terminal and run:

```bash
ps aux | grep vnc
```

A running TigerVNC server appears as something like:
```
tiny   1234  0.0  0.1  Xvnc :1 -rfbport 5901 ...
```

### Manually restart the desktop session

```bash
start-desktop &
```

This script starts both the VNC server and the window manager. If it fails, check its exit output directly:

```bash
start-desktop
# Runs in foreground so errors print immediately
```

### Test noVNC port from ADB shell

Without entering the container, verify the noVNC HTTP server is responding on Android:

```bash
adb shell curl -s http://127.0.0.1:36081/
# Should return HTML for the noVNC landing page
```

If `curl` is unavailable in the ADB shell, use `wget` or `nc`:

```bash
adb shell 'echo -e "GET / HTTP/1.0\r\n\r\n" | nc 127.0.0.1 36081 | head -5'
```

### VNC display environment

The VNC server runs on display `:1`. If apps inside the container aren't rendering:

```bash
# Inside the container
export DISPLAY=:1
xterm &   # baseline X11 connectivity test
```

---

## 7. Filing a Bug Report

### What to include

1. **Device model** (e.g., Pixel 10 Pro, Samsung Galaxy S26)
2. **Android version** (e.g., Android 16, API 36)
3. **App version** — visible in **Settings → About** (should be 2.0.7+)
4. **Exact reproduction steps** — numbered, minimal
5. **Logcat output** — filtered snippet (see §2) covering the failure window
6. **ADB bug report** — `adb bugreport bugreport.zip` attached to the issue
7. **Whether Shizuku is enabled** (yes / no / not installed)

### Submit

**https://github.com/DaRipper91/DaRipped_tiny_computer/issues**

Use the **Bug Report** issue template if available. Attach `bugreport.zip` and any relevant logcat snippets as code blocks.

> For end-user-facing troubleshooting steps, direct users to **[MANUAL.md §5](MANUAL.md#5-troubleshooting-guide)** rather than this file.

---

*Debug reference version: 2.0.7 · Last updated: 2025-07-14*
