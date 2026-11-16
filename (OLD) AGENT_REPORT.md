# Agent Report

## Summary
Branch `rebase/arch-multidistro-on-upstream`, mirrored to `main`. Goal: IntelNode = Tiny Computer with Arch Linux ARM,
one APK, no Termux steps. This turn (all on Pixel 10 Pro, Android 17 DP11):
- `8be852d`: boot fixes. Root cause of the permanent "Installation Complete" freeze was `await setupAudio()` (pulseaudio
  runs in the foreground of its pty and never returns); now `unawaited`. Also tiny=uid 1000, resolv.conf replaced,
  start-desktop run via bash, fake /proc + cap_last_cap, Termux /tmp bind removed, stored boot string fixed.
  DEVICE RESULT: startup now reaches `waitForXServer` and fails "X server did not start within 60 seconds".
- `3e661ca`: Arch ships `usr/share/X11/xkb` as an ABSOLUTE symlink to `/usr/share/xkeyboard-config-2`; it dangles outside
  proot, so the in-app X server had no keymaps, and `createDirFromString` over the link threw inside an un-awaited call.
  Added `Workflow.xkbRoot()`, no mkdir over a link, launch error text in the timeout message. Test:
  `test/workflow_test/xkb_root_test.dart`. NOT yet confirmed on device.
- Docs/tooling (this commit): `README.md` rewritten with honest status, `images/pipeline.svg`, new `debug/`
  (`README.md`, `capture.sh`, git-ignored `logs/`). Raw logs are deliberately not committed (other apps' package names).
- Releases: `v2.2.6-debug.1` (8be852d, fails at X server step). `v2.2.6-debug.2` (3e661ca) uploaded as pre-release.

## Feature / Task Status
- ✅ Bootstrap, chunk copy, extraction (busybox unxz | tar x) — verified on device
- ✅ Startup no longer hangs on audio — verified on device (error screen reached)
- 🔄 In-app X server — xkb fix shipped, awaiting device result
- ❌ XFCE visible on screen — never observed
- ❌ noVNC/AVNC path on Arch — no server wired
- ❌ WPS / Edraw / QQ / DingTalk container tests

## What the Next Agent Should Do First
1. Run `debug/capture.sh 192.168.1.68:5555` with `v2.2.6-debug.2` installed (uninstall older first). Check port 7897
   (`1ED9` in /proc/net/tcp) and `containers/0/tmp/.X11-unix`.
2. If the X server still fails: read the new "(launch failed: …)" text on the error screen; then try dropping
   `-extension MIT-SHM` (upstream passes only `:4`); then inspect `com.termux.x11.CmdEntryPoint` in the x11_flutter plugin.
3. Local `assets/` has stale untracked `xaaa`..`xaaj`; delete (needs user OK) before local builds.
4. README hardware claims were removed; protected CI files still use floating Flutter `stable` in
   `flutter-build.yml`/`release.yml` (debug workflow pins 3.41.6).
Constraints: debug keys differ per CI run (uninstall first); never run `dart format` repo-wide; do not screenshot a locked phone.

## Blocking Issues
- No confirmation yet that the X server or desktop starts. Everything past the xkb fix is unverified.

## Build / Test Status
- Build: ✅ CI debug APK green for 8be852d (run 43718769069) and 3e661ca (run 43768736251)
- Lint:  ✅ no errors (pre-existing infos only)
- Tests: ✅ 91/91 passing
