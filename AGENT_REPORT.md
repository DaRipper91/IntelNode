# Agent Report

## Summary
Boot/X-server logging was added and hardened; the README redesign and the push were NOT done (usage limit reached).

- `ad49a08` feat: new `lib/boot_log.dart` (`BootLog`) mirrors the container terminal's output (TermPty), shell exit codes, `launchXServer` and `waitForXServer` events to logcat (prefix `IntelNode`) and a rolling `files/boot.log` (readable with `run-as` on debuggable builds). Hook sites in `lib/workflow.dart`.
- `ab6e2d9` fix: hardening from a full `rip-it-apart-file` audit of `lib/boot_log.dart` (4 stages, critic "Clean pass? Yes"). Tasks 1, 2, 4, 5, 6 of `docs/plans/2026-11-15-boot_log.dart-fixes.md` implemented: logging can never change caller control flow (every public method absorbs failures; a throwing logger used to turn a real exit code into -1 inside `Util.execute`), new line budget per `attachFile`, UTF-8 rollover accounting, dropped-character marker, tighter escape stripping, file-disabled notice names the path.
- Tests: `test/boot_log_test.dart` (25 tests; the original 13 untouched). Full suite 131/131 (baseline 106). `flutter analyze --no-pub` identical to the pre-change baseline (19 pre-existing infos).
- Audit scratch archived at `.audit/files/history/lib-boot_log.dart-SCRATCH-2026-11-15.md`.
- Earlier this session (not committed): Pixel 10 Pro `apk-debug-rip` audit, untracked in `docs/plans/2026-11-15-pixel10pro-apk-debug-rip-{audit,fixes}.md`. NOTE a correction to that audit: the "proot restart storm" is most likely the app's normal sequence of short `_prootRun` steps (container_installer.dart), and the 8.6-min process most likely the extraction/first-boot step; the real known failure is the one already documented here ("X server did not start within 60 seconds"). The audit's no-OS-kill, no-seccomp and exec-granted findings stand.

## Feature / Task Status
- ✅ BootLog + hooks + tests, committed locally (2 commits ahead of origin/main, NOT pushed)
- ✅ rip-it-apart-file chain on lib/boot_log.dart finished; fix plan tasks 1, 2, 4, 5, 6 done
- 🔄 Fix-plan Task 3 (logcat lag/loss under process death) is documentation only; the on-device gate (flood the pty, kill -9 mid-flood, compare logcat to boot.log) is NOT run: it needs a debuggable build and would uninstall the app another session is using. Nothing here has run on a device yet.
- ❌ README redesign (owner asked for a distinctive README with new assets drawn from ideas in the AI_Agentic, OmniMap, hexmind, PolyGet repos) - not started beyond research
- ❌ `debug/README.md` still says "the app writes almost nothing to logcat" - outdated once a build with `ab6e2d9` is installed; update it (and mention `adb logcat -d | grep IntelNode` and `run-as ... cat files/boot.log`)
- ❌ Push

## What the Next Agent Should Do First
1. README (owner's request: make it as unique as possible). Planned, IntelNode-specific assets (all hand-written animated SVG in the existing Catppuccin Mocha palette, no copies from other repos): (a) `sandbox-anatomy.svg`, a cross-section Android kernel -> `untrusted_app_34` sandbox -> libproot -> Arch rootfs -> in-app X server (127.0.0.1:7897, 0x1ED9) -> XFCE, annotated only with observed facts (exec from the app data dir is `granted`; setattr on /proc and /sys directories is denied); (b) `wait-for-x-server.svg`, 60 ticks = the 60 one-second probes of `Util.waitForXServer`, ending in its TimeoutException; (c) `first-run-timeline.svg`, observed events of one real first run (install 19:08, update 21:27:05, rootfs tar 829,367,415 bytes by 21:29, longest proot 8.6 min, seven short proot runs 21:39:44-21:40:14, no OS kill events), labelled "Pixel 10 Pro, Android 17 DP11, 2026-11-15; stage labels inferred"; (d) `logcat-card.svg`, an animated `adb logcat -d | grep IntelNode` card labelled "illustrative format, not captured"; (e) a prompt-cursor divider. Do NOT draw a disk-usage treemap: the sizes measured so far (files/ 3.73 GB vs containers/0 2.91 GB + 0_staging 1.49 GB) were taken at different moments and do not add up. Also add a "Reading a failed boot" section, list `lib/boot_log.dart` and `test/boot_log_test.dart` in Repo layout, and note logging is unverified on device.
2. Push `main` to origin (owner asked). Pushing `main` triggers NO workflow (workflows run on `master`, `wip/**`, `rebase/**`, `debug/**` and `v*` tags), so it is CI-inert; a build for the device needs a push to a `debug/**`-style branch.
3. Commit only your own files. `PROJECT_REPORT.md`, `REALITY_CHECK.md` and `docs/` are untracked work from another session; leave them. This report (and `(OLD) AGENT_REPORT.md`) are modified but uncommitted.
4. Constraints: never run `dart format` repo-wide; always `--no-pub`; do not use `-c core.hooksPath=/dev/null` (I did once by habit; the repo has no hooks, so nothing was bypassed); do not touch the phone while another session is debugging it.

## Blocking Issues
None. (Local builds are still blocked by stale untracked `assets/xaa*`; deleting them needs the owner's OK.)

## Build / Test Status
- Build: not run locally (blocked as above); not applicable to this change
- Lint:  ✅ `flutter analyze --no-pub`: identical to baseline (19 pre-existing infos, no errors or warnings)
- Tests: ✅ 131/131 passing
