# Agent Report

## Summary
README redesigned with new IntelNode-specific artwork; boot logging (`BootLog`) was already committed. This turn also pushes main.

- README.md: new sections "Inside the sandbox" and "Reading a failed boot", a real first-run timeline under Status, a log-line meaning table, Contents and repo-layout updated, honest labelling (the logcat card is explicitly illustrative; nothing from the logging has been captured on a device yet).
- New animated SVGs in `images/` (hand-written, Catppuccin Mocha, SMIL, no scripts or external fetches, readable without animation): `sandbox-anatomy.svg` (six-layer cross-section with observed facts, dashed = unobserved), `wait-for-x-server.svg` (60 literal ticks = the 60 one-second probes of `Util.waitForXServer`), `first-run-timeline.svg` (observed adb timestamps of one real run, with a zoom on seven short proot runs), `logcat-card.svg`, `divider-prompt.svg`. Ideas were taken from the owner's other repos (OmniMap architecture layers, AI_Agentic pulse-on-a-pipeline, PolyGet/hexmind flow and dividers); no asset was copied. Generator: scratchpad `gen_intelnode_assets.py` (not committed).
- debug/README.md: replaced the outdated "the app writes almost nothing to logcat" with what builds containing `BootLog` do (unverified on device) and what `capture.sh` does and does not capture.
- Every number in the artwork was checked against measurements: tar 829,367,415 bytes = 791 MiB; containers/0 about 2.8 GiB; 10 proot launches, longest 8.6 min (21:30:20-21:38:58), seven short runs 21:39:44-21:40:14, none over 3 s; install 19:08, reinstall 21:27:05. Corrected during review: "no kill, crash or ANR" narrowed to "no kill or crash" (only that was checked); "1-3 s each" to "up to 3 s".
- Earlier in the session (already committed): `lib/boot_log.dart` + hooks (`ad49a08`), audit-driven hardening (`ab6e2d9`, 25 BootLog tests, full suite 131/131, analyze identical to baseline).

## Feature / Task Status
- ✅ README + 5 assets + debug/README.md updated; image references (12) and in-page anchors (11) all resolve; animation keyTimes checked (80 animations, 0 problems); static fallback frames render the end state
- ✅ BootLog + hardening committed
- 🔄 Nothing from the logging has run on a device: needs a debug build (push to a `debug/**`, `wip/**` or `rebase/**` branch builds one; signing key differs per CI run, so uninstall first) and a phone not in use by another session
- 🔄 Fix-plan Task 3 (logcat lag/loss under process death) still open: needs that device run (flood the pty, kill -9 mid-flood, compare logcat to boot.log)
- 🔄 `debug/capture.sh` does not pull `files/boot.log`, and it clears logcat and force-stops the app; consider adding the `run-as ... cat files/boot.log` pull on exit (not done: could not be tested without disturbing the phone)
- ❌ Animations were validated structurally and as static frames only; nobody has watched them play in a browser

## What the Next Agent Should Do First
1. Build and install a debug APK containing `ad49a08`+ on the Pixel, run `debug/capture.sh`, and check `adb logcat -d | grep IntelNode` and `run-as com.daripper91.daripped cat files/boot.log`. If real output matches the formats, replace the illustrative logcat card with a real capture (trim other apps' package names first).
2. Then close fix-plan Task 3 with measured numbers.
3. Open `images/*.svg` in a browser once and confirm the animations look right.
4. Do not commit `PROJECT_REPORT.md` / `REALITY_CHECK.md` (another session's untracked files). Never run `dart format` repo-wide; use `--no-pub`.

## Blocking Issues
None. (Local APK builds are still blocked by stale untracked `assets/xaa*`; deleting them needs the owner's OK.)

## Build / Test Status
- Build: not run locally (blocked as above); docs and SVG only this turn
- Lint:  ✅ unchanged: `flutter analyze --no-pub` identical to the baseline (19 pre-existing infos)
- Tests: ✅ 131/131 at `ab6e2d9`; no code changed since
