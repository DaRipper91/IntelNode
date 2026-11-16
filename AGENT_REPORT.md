# Agent Report

## Summary
`fix/resilient-first-run` is MERGED with origin/main (incl. daripper-01's BootLog, 144 tests pass) and pushed to `main`. CI builds come from `debug/resilient-first-run`. Newest green APK before the merge: c84791b (run 43803702039) with the X-server ANR fix (reflection launch) - NOT yet run on a device: the Pixel was offline on Tailscale on 2026-11-16.
Device-verified on a Pixel 10 Pro (Android 17): two-stage first run works end to end (download with resume, md5 check, extract,
pacman -Syu under proot, uid-1000 user, verify, picker, XFCE4 install, session file, in-app X server starts).
Device-found bugs fixed on the branch: busybox needs LD_LIBRARY_PATH (checksum/finalize); tar needs --delay-directory-restore
(read-only dirs); HTTP 416 on a complete tarball; gpg-agent kept proot alive (EXIT trap) and `set -e` leaked into the trap (set +e);
`userdel -r` exits 12 under proot; Debian logo replaced with a new node-graph "N" logo.
VERIFIED ON DEVICE 2026-11-16 (build 3564ac1, Pixel 10 Pro, Android 17): clean first run (data cleared) works end to end AND the
XFCE4 desktop is on screen and stays up: panel with Applications menu, clock, user `tiny`, Home/File System icons, launcher dock, wallpaper
(screenshot taken; session survived 2+ minutes, 5 XFCE processes, no abort in boot.log).
Device-found bugs fixed, in order: busybox LD_LIBRARY_PATH; tar --delay-directory-restore; HTTP 416 on a complete tarball;
gpg-agent kept proot alive (EXIT trap + `set +e`); `userdel -r` exit 12; X server ran on the UI thread (ANR, fixed by MainActivity
`launchXServer` on its own looper thread); PROOT_NO_SECCOMP=1 made every chdir/getcwd ENOSYS (removed); Retry crashed on
`late final G.dataPath`; mirror timeouts (fallback mirrors); `awk` missing in start-desktop; and finally the XFCE session aborting ~30 s
in: gdk-pixbuf2 2.44 decodes images through glycin, which runs loaders in bubblewrap, and bwrap cannot work under proot, so no image
loaded, libwnck asserted and proot "vpid 1 terminated with signal 6". GLYCIN_DISABLE_SANDBOX is ignored by Arch's glycin; the fix is a
bwrap stand-in script (lib/guest_shims.dart) mounted at /usr/local/bin/bwrap.
Unexplained: files on the phone written ~23:52 on 2026-11-15 by another agent/session (a modified files/tiny/extra/start-arch.sh with an
extra `cd` line and a compiled getifaddrs_bridge_client_lib.so); not in this repo or patch.tar.gz. The glibc-linked lib makes Android's
getprop print a linker error under LD_PRELOAD (noise only).
Known leftovers: the X server stops answering new clients after a session crash (not seen once sessions stay up); `am start` on a running
app re-runs the workflow and double-starts the X server; polkit/upower/login1/DPMS warnings (no systemd) are expected; the 16 KB page-size
compatibility dialog lists upstream native libs (libXlorie, pulseaudio, getifaddrs server...) as unaligned.

## Feature / Task Status
- ✅ Two-stage install (base + picker + desktop) — verified on device through XFCE4 install
- ✅ XFCE4 desktop on screen on the device (screenshot seen, 3564ac1)
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
- Build: ✅ 3564ac1 green (run 43896571519)
- Lint:  ✅ flutter analyze --no-fatal-infos clean (18 infos)
- Tests: ✅ 153 passing locally
