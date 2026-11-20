# Agent Report

**Author:** Claude Code (orchestrator + Sonnet implementers) · **Date:** 2026-11-19 · **Branch:** `fix/audit-2026-11-19` (local, off `origin/main` d0eaa99, uncommitted, not pushed)
**Source of truth for scope:** `docs/plans/2026-11-19-intelnode-fixes.md` (55 tasks from a rip-it-apart audit; final ledger: 0 critical, 0 high, 13 medium, 5 low-medium, 37 low).

## Summary
Round 1 and 2 of the audit fix plan were implemented. Nothing was built with Gradle and nothing was run on a device; verification is `flutter analyze` + `flutter test` only.

- **Exposure (S11):** removed device-connection lines and network identifiers from `(OLD) AGENT_REPORT.md` (now rotated), `docs/HANDOFF-agy-2026-11-16.md`, `debug/README.md`, `debug/capture.sh` (now takes `$DEVICE_IP`). Deleted `OWNERS` (held only an upstream author's email; nothing referenced it).
- **SAF provider (S1, S2):** new `android/.../DocumentPathGuard.java`; `TinyDocumentsProvider.java` now confines paths canonically, rejects `..` and prefix siblings, sanitises displayName, fails search closed, null-guards `listFiles`/`getParentFile`, refuses to delete the root.
- **Manifest / X11 bridge (S10, partial):** `X11KeyboardReceiver` and `Signal9Activity` set `exported=false`; receiver socket has `reuseAddress`, 64-char line cap, 2 s read timeout, 4-client cap. New `test/android_manifest_exports_test.dart`.
- **Docs (S13):** "Trust model" in `README.md` and `MANUAL.md` section 2.3 (docs only, no runtime change).
- **Rootfs trust (S3, S4, F9, S5):** `lib/distros.dart` + `lib/container_installer.dart`: per-URL SHA-256 pins for all 12 fixed URLs, explicit `checksumKind`, fail-closed on unpinned/unknown tar extension, partial tarballs named by source, `--gpg-auto-import-keys` removed except one first-boot refresh, `.deb` third-party installs hash-gated. Install quick commands for CAJViewer, EdrawMax, QQ, WeChat, DingTalk removed (uninstall kept). Provenance table: `~/agent-config-review/intelnode-fix-notes-B.md`.
- **Boot-line escaping (S14):** `Workflow.envAssignmentArguments()` in `lib/workflow.dart`.
- **Runtime bugs (F4, F19, F20, F12, F5, F6, F18):** JNI symbols in `android/app/src/main/cpp/native-socket.cpp` renamed to `Java_com_daripper91_daripped_AudioStream_*`; `MainActivity.kt`/`AudioStream.kt` reply on streaming calls, no `!!`, state hardened; `copyAsset(..., executable:)` chmods `to_vault` etc.; `to_vault` reads device/OS from `getprop`; `_registerContainer` records the real package manager via `ContainerInstaller.containerInfoFor`; default commands fixed (sudo on pacman/apt update, `uname -a` replaces neofetch); launch-path futures awaited or `unawaited(...catchError)` + `BootLog`.
- **Tests added/changed:** `android_manifest_exports_test`, `distros_pins_test`, `rootfs_verify_test`, `package_trust_test`, `workflow_test/env_options_test`, `audio_stream_jni_test`, `workflow_test/{to_vault,register_container,distro_commands}_test`.
- Plan file copied into `docs/plans/2026-11-19-intelnode-fixes.md`.

## Feature / Task Status
- ✅ S11, S1, S2, S13, S3, S4, S14, F4, F19, F20, F12, F5 — implemented, unit-tested where the repo allows; **not device-verified**
- 🔄 S10 — `usesCleartextTraffic` left true (depends on F2: `workflow.dart` still uses `http://localhost:36082`); `com.termux.x11.MainActivity` untouched
- 🔄 S5 — `--gpg-auto-import-keys` kept on one first-boot `zypper refresh -f` (rootfs key presence unconfirmed on device; allow-listed in `test/package_trust_test.dart`)
- 🔄 F9 — partial naming done; "delete unverified tarball after failed extraction" not implemented (unreachable: downloads are verified or refused before extraction)
- 🔄 F6 — items a, b done; item c (`wget` on Arch base) unconfirmed
- 🔄 F18 — `launchGUIBackend` awaited, others handled via `catchError`; `G.homePageStateContext` sites carry per-site `// ignore:` because a `mounted` check is impossible on a global context
- ❌ F24 (operator precedence in `getCurrentProp` legacy VNC-password migration) — edit was denied and conflicts with "leave VNC code alone"; proposed fix: `keyIsVnc && (!hasProp || stored.isEmpty || stored == "12345678")`; needs owner OK
- ❌ Protected, need explicit owner go-ahead: S6, S7, S8, F32, F33, workflow parts of F35 (`.github/workflows/*`); S13 narrowing and anything touching `AGENTS.md`/`.github/copilot-instructions.md`
- ❌ Owner decisions pending: F1 (`boot` setting), F2 (dead VNC path: remove or restore), F3 (guest commands not shipped), F10 (container delete atomicity / stable IDs), F7, F11
- ❌ Not started: remaining Phase 2-4 tasks per the plan task index

## What the Next Agent Should Do First
1. Read `docs/plans/2026-11-19-intelnode-fixes.md` (coverage statement and "Needs device confirmation" table) and the notes in `~/agent-config-review/intelnode-fix-notes-{A,B,C}.md`.
2. **Device confirmation before trusting anything here** (Pixel 10 Pro): mic streaming toggle (JNI link, F4), `to_vault` exec bit, SAF `..`/`../../x` behaviour (S1), guest `am broadcast` still reaching the unexported X11 receiver (S10), openSUSE first boot with narrowed key import (S5), a real install of a pinned distro, Void from repo-default.
3. Do NOT commit or push without the owner's say-so; `git filter-repo` history purge (identifiers + `assets/xaa..xae` rootfs chunks, ~3 GB) is an owner decision and a force-push to a public repo. The ADB pairing record, tailnet host/IP and wireless-debug address that were exposed in history should be revoked/rotated by the owner.
4. Five SHA-256 pins are trust-on-first-use (computed 2026-11-19): Debian v4.17.3 and v4.7.0, Fedora v4.15.0, openSUSE and Void v4.6.0 builds. They prove integrity from now on, not original authenticity. Re-pin from a vendor source if one appears.
5. Respect: `.github/workflows/`, `AGENTS.md` and its symlinks, lock files are protected.

## Blocking Issues
None blocking the implemented work. Open items: F24 owner approval; protected-file tasks; F1/F2/F3/F10/F7/F11 decisions; CAJViewer/EdrawMax/WeChat hosts timed out from the build machine so their pins could not be obtained (quick commands dropped instead).

## Build / Test Status
- Build: ❓ Gradle build NOT run (only `flutter analyze`/`flutter test` and standalone compile checks of the Java provider and Kotlin receiver; NDK clang++ `-fsyntax-only` on `native-socket.cpp`).
- Lint:  ✅ `flutter analyze --no-fatal-infos`: 0 errors, 0 warnings, 10 infos (CI baseline at d0eaa99 was 18 infos).
- Tests: ✅ `flutter test`: 279 passing, 0 failing (CI baseline at d0eaa99: 205). Flutter 3.41.6 / Dart 3.11.4 installed at `~/src/flutter` for this work.
