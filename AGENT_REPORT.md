# Agent Report

## Summary
Branch `fix/resilient-first-run` (worktree ~/Projects/IntelNode-fix, CI via `debug/resilient-first-run`) is AHEAD of `main`; none of it is merged yet.
Device-verified on a Pixel 10 Pro (Android 17): two-stage first run works end to end (download with resume, md5 check, extract,
pacman -Syu under proot, uid-1000 user, verify, picker, XFCE4 install, session file, in-app X server starts).
Device-found bugs fixed on the branch: busybox needs LD_LIBRARY_PATH (checksum/finalize); tar needs --delay-directory-restore
(read-only dirs); HTTP 416 on a complete tarball; gpg-agent kept proot alive (EXIT trap) and `set -e` leaked into the trap (set +e);
`userdel -r` exits 12 under proot; Debian logo replaced with a new node-graph "N" logo.
OPEN BLOCKER: ~25 s after the X11 page opens Android kills the main process (ANR, `bg anr`). ANR trace: UI thread stuck in
`CmdEntryPoint.main -> Looper.loop()` called by x11_flutter on the main thread. Fix written (MainActivity `launchXServer` runs it
on its own looper thread via reflection; Workflow.launchXServer calls it) but its CI build had a Kotlin compile error
(`Unresolved reference CmdEntryPoint`) in bd6a827; the reflection rewrite is committed next and UNVERIFIED (no build/device run yet).
Also: LD_PRELOAD for getifaddrs bridge now only set when the library exists (it is shipped nowhere).

## Feature / Task Status
- ✅ Two-stage install (base + picker + desktop) — verified on device through XFCE4 install
- 🔄 Desktop visible on screen — blocked by the X-server ANR fix awaiting a green build + device test
- ❌ Merge `fix/resilient-first-run` into `main`; release a new APK
- ❌ Items in docs/plans/2026-11-15-intelnode-fixes.md marked OPEN / NEEDS-USER-DECISION

## What the Next Agent Should Do First
1. Check CI for the newest `debug/resilient-first-run` run; if green, `adb connect 100.83.49.113:5555` (Tailscale), `adb install -r -g` the APK, launch with monkey (do NOT `am start` MainActivity over the X11 page: it kills the process), watch for XFCE.
2. If it still ANRs or the X server never connects, pull a bugreport (`adb bugreport`) and read FS/data/anr for the main-thread stack.
3. Once XFCE shows, merge the branch to `main`, publish a pre-release, and update README status.
4. Debug evidence: ~/.cache/tiny-orig/br (bugreport), keystore backup ~/.cache/tiny-orig/signing (back it up elsewhere).
Constraints: debug keys are now stable (CI secrets set); never screenshot unless IntelNode is focused; plan file lists open decisions.

## Blocking Issues
- Android 17 ANR in the in-app X server launch (fix pending verification). Nothing else known.

## Build / Test Status
- Build: ❌ bd6a827 failed (Kotlin unresolved reference); follow-up commit pending CI
- Lint:  ✅ flutter analyze --no-fatal-infos clean (18 infos)
- Tests: ✅ 119 passing locally
