# Agent Report

## Summary
`fix/resilient-first-run` is MERGED with origin/main (incl. daripper-01's BootLog, 144 tests pass) and pushed to `main`. CI builds come from `debug/resilient-first-run`. Newest green APK before the merge: c84791b (run 43803702039) with the X-server ANR fix (reflection launch) - NOT yet run on a device: the Pixel was offline on Tailscale on 2026-11-16.
Device-verified on a Pixel 10 Pro (Android 17): two-stage first run works end to end (download with resume, md5 check, extract,
pacman -Syu under proot, uid-1000 user, verify, picker, XFCE4 install, session file, in-app X server starts).
Device-found bugs fixed on the branch: busybox needs LD_LIBRARY_PATH (checksum/finalize); tar needs --delay-directory-restore
(read-only dirs); HTTP 416 on a complete tarball; gpg-agent kept proot alive (EXIT trap) and `set -e` leaked into the trap (set +e);
`userdel -r` exits 12 under proot; Debian logo replaced with a new node-graph "N" logo.
VERIFIED ON DEVICE 2026-11-16 (build 6133f9c, Pixel 10 Pro, Android 17): the whole first run works and the XFCE4 session starts
(processes seen: xfce4-session, xfwm4, xfce4-panel, xfsettingsd, Thunar, session dbus; boot.log shows `Launching startxfce4`, no errors).
Two device-found blockers fixed after the first-run work: (1) ANR/kill ~25 s after the X11 page opened: UI thread stuck in
`CmdEntryPoint.main -> Looper.loop()` (x11_flutter calls it on the main thread); fixed by running it on its own looper thread via
reflection in MainActivity (`launchXServer`), failures reported back as `xServerLaunchFailed`; (2) every chdir/getcwd in the booted
container returned ENOSYS (dbus-daemon "Could not chdir() to root directory", so no desktop): caused by `PROOT_NO_SECCOMP=1` in the
boot command; removed it (provisioning proot runs never set it). NOT yet seen: a screenshot of the XFCE desktop (phone was in use);
icon theme warnings (`Could not load a pixbuf from icon theme`) suggest an icon theme package is missing.
Unexplained: files on the phone written ~23:52 on 2026-11-15 by another agent/session (a modified files/tiny/extra/start-arch.sh with an
extra `cd` line and a compiled getifaddrs_bridge_client_lib.so); not in this repo or patch.tar.gz.

## Feature / Task Status
- ✅ Two-stage install (base + picker + desktop) — verified on device through XFCE4 install
- ✅ XFCE4 session running on device (processes verified, boot.log clean); 🔄 visual confirmation (screenshot) pending
- ✅ Merged into `main` (the ANR fix is unverified on a device)
- ❌ New pre-release APK
- ❌ Items in docs/plans/2026-11-15-intelnode-fixes.md marked OPEN / NEEDS-USER-DECISION

## What the Next Agent Should Do First
1. Check CI for the newest `debug/resilient-first-run` run (merged tree incl. BootLog; logs go to logcat prefix IntelNode and files/boot.log); if green, `adb connect 100.83.49.113:5555` (Tailscale), `adb install -r -g` the APK, launch with monkey (do NOT `am start` MainActivity over the X11 page: it kills the process), watch for XFCE.
2. If it still ANRs or the X server never connects, pull a bugreport (`adb bugreport`) and read FS/data/anr for the main-thread stack.
3. Once XFCE shows, merge the branch to `main`, publish a pre-release, and update README status.
4. Debug evidence: ~/.cache/tiny-orig/br (bugreport), keystore backup ~/.cache/tiny-orig/signing (back it up elsewhere).
Constraints: debug keys are now stable (CI secrets set); never screenshot unless IntelNode is focused; plan file lists open decisions.

## Blocking Issues
- None known. Follow-ups: icon theme package, `am start` on a running app re-runs the workflow and starts the X server twice (crashes), BootLog README text still describes the old 60 s timeout.

## Build / Test Status
- Build: ✅ 6133f9c green (run 43879730575)
- Lint:  ✅ flutter analyze --no-fatal-infos clean (18 infos)
- Tests: ✅ 144 passing locally (merged tree)
