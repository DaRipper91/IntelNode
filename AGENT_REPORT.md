# Agent Report

## Summary
Branch `rebase/arch-multidistro-on-upstream` (rebased on `origin/master` v2.2.5). Earlier turns: audit fixes
(workflow.dart parse error, `.deb`-on-Arch install path, dnf/zypper, package-manager persistence), a debug-only CI
workflow, README refresh, ARM64 container harness. This turn diffed our native layer against upstream Tiny
Computer v4.2.2 (`jniLibs.zip`, byte hashes + ELF NEEDED) and fixed first-run bootstrap bugs found that way.

Commits this session: `dfc66ae` (applib `ln -sfn`, sequential chunk copy, scrollable error text),
`dea4b9b` (below). Files modified in `dea4b9b`:
- `lib/workflow.dart`
  - `libtalloc.so.2` is now staged from `applib/libtalloc.so` (proot NEEDs `libtalloc.so.2`; SONAME matches).
  - `Util.rootfsExtractCommand()`: `cat xa* | busybox unxz | tar x`. CORRECTION: an earlier claim (and the commit
    message of `dea4b9b`) that busybox has no `xz` applet is WRONG — it has `xz`, `unxz`, `xzcat` (a `strings -n 3`
    search had skipped the 2-char name). Upstream's `tar x -J` works; unxz is equivalent and merely avoids the fork.
  - Extraction script now exits non-zero if proot/tar fails or `usr/bin/env` / `etc/passwd` is missing (the exit
    code used to come from the trailing `rm`, so failures showed "Installation Complete").
  - `G.updateText` default caption `"小小电脑"` -> `"IntelNode"`.
- `test/workflow_test/rootfs_extract_command_test.dart` — NEW (3 tests; the round-trip case skips without host busybox).

Evidence (native layer vs upstream v4.2.2): tar, busybox stub, both proot loaders, talloc, acl, attr, iconv, pcre2,
android-selinux are byte-identical. `libexec_proot.so` matches none of upstream's three proot builds
(classic / latest / classic-debug).

### Device findings (Pixel 10 Pro, Android 17 DP11, USB adb; `dea4b9b` installed)
- First verified run: bootstrap + chunk copy OK, proot loads, `busybox unxz | tar x` extracts the full Arch rootfs
  (~12 min), "Installation Complete" is real. Running the boot command by hand via `run-as` (script in
  `~/.cache/tiny-orig/builds/dea4b9b/boot.sh`) booted bash/start-arch.sh inside proot.
- Boot blockers found there (fixed in the working tree, NOT yet built/committed): (1) `su - tiny` prompts for a password
  because uid 1000 is the stock `alarm` user (tiny is 1001) -> `Util.swapAlarmTinyIdsCommand`, start-arch.sh skips `su`
  when non-root; (2) `/etc/resolv.conf` is a dangling symlink into /run/systemd -> `rm -f` first; (3) start-desktop is
  copied without +x -> run via `bash`.
- Boot parity with upstream: removed the Termux `/tmp` bind; added `cap_last_cap` + fake /proc files (`lib/fake_proc.dart`,
  generated under `$DATA/fakeproc` every launch); stored container `boot` was the literal text `${Workflow.getBootCommand()}`.
- OPEN: the in-app X server never starts. `waitForXServer` polls TCP 127.0.0.1:7897; nothing listens, `libXlorie` is not
  mapped, no `.X11-unix` socket. App writes nothing to logcat on this phone, so the cause is unknown (call is
  `X11Flutter.launchXServer`, args `[":4","-extension","MIT-SHM"]` vs upstream `[":4"]`). Next: read x11_flutter /
  termux-x11 `CmdEntryPoint` for the 7897 listener, try dropping the extra args.
- Correction: busybox DOES have an `xz` applet (a `strings -n 3` search missed the 2-char name); upstream's `tar -J` works.

## Feature / Task Status
- ✅ applib relaunch bug (reproduced, test red-green)
- ✅ libtalloc staging, busybox unxz extraction, extraction-failure detection — unit tested (string/shape), NOT run on device
- 🔄 Silent app close after picking XFCE — attributed to the concurrent 1.3 GB chunk copy (fixed in `dfc66ae`);
  no logcat evidence either way
- 🔄 README hardware claims ("Cortex-X925"/"Mali-G925") look wrong; no real screenshots
- ❌ On-device end-to-end boot (proot load, extraction, XFCE) — never observed working
- ❌ WPS / Edraw / QQ / DingTalk install-uninstall container tests (WeChat verified)

## What the Next Agent Should Do First
1. Get logcat from the phone (USB `adb`, or wireless-debug port; `pixel10` was offline on Tailscale so Taildrop
   failed with 502). Install the CI artifact of the latest commit; uninstall the old build first (debug keystore differs per runner).
2. If proot still fails: try upstream's `proot-classic` / `proot-latest` from `~/.cache/tiny-orig/v4.2.2/jni/` (v4.2.2 jniLibs.zip).
3. Local `assets/` has 10 untracked stale chunks `xaaa`..`xaaj`; `cat xa*` would splice them into the stream. CI is
   unaffected (clean checkout). Delete them (needs user OK) before any local build.
4. Consider upstream v4's design: small shell APK + on-demand rootfs (`container_installer.dart` already downloads
   ArchLinuxARM tarballs) to drop the 1.3 GB asset copy.
5. `flutter-build.yml` / `release.yml` still use floating Flutter `stable` (Gradle 9.3.1 vs wrapper 8.11.1); debug
   workflow pins 3.41.6. Protected CI files — not touched.
Constraints: never run `dart format` repo-wide (reformats unrelated files); `.cursorrules`/`CLAUDE.md` are uncommitted
symlinks; debug-build workflow cancels in-progress runs on a new push.

## Blocking Issues
- No device logs; phone unreachable over Taildrop. Fixes above are inferred from ELF headers and applet strings.
- Untracked `GEMINI.md`, `PROJECT_REPORT.md`, `REALITY_CHECK.md` are auto-generated stubs, not ours.

## Build / Test Status
- Build: ✅ CI debug APK succeeded for `dfc66ae`; run `43712280712` for `dea4b9b` succeeded (artifact `14161665910`, 1399 MiB)
- Lint:  ✅ 0 errors (`flutter analyze`: 18 info/warnings, pre-existing, none introduced here)
- Tests: ✅ 81/81 passing
