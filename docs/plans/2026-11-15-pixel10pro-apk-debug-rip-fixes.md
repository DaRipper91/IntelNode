# Pixel 10 Pro / IntelNode - apk-debug-rip fix plan (2026-11-15)

Audit record with every raw file: `2026-11-15-pixel10pro-apk-debug-rip-audit.md` in this folder (critic: Clean pass? Yes).
Target: Pixel 10 Pro on **Android 17 Developer Preview (DP11)**, IntelNode `com.daripper91.daripped` v2.1.1 (debuggable). Log window 19:50-21:45 (1h55m): conclusions about logcat cover only that window.

## What is wrong (ranked) and what is not
1. **IntelNode's proot does not stay up** (ADR-1, high): one 8.6-min run (21:30:20-21:38:58), then 7 relaunches 1-3 s each (21:39:44-21:40:14), then no proot child while the app keeps running. No OS kill/crash event for any of them (phantom-process killer already disabled) -> proot/guest exits on its own. **Cause not yet known.**
2. **The app is silent** (ADR-2, med): no logcat output after 21:27:10 while using ~30% of a core.
3. **Phone memory-saturated** (ADR-6, high): 3.1 GB of 15.9 GB available, swap ~80% used, 2,001 LOW_MEMORY exit records. Not the cause of ADR-1 (the app process was never OS-killed) but a risk for every background proot/Termux session.
4. Bootstrap runs mkinitcpio/kernel hooks in proot (ADR-3), 1.5 GB stale `containers/0_staging` (ADR-4), harmless-looking procfs `setattr` denials (ADR-5).
5. Android 17 DP platform noise (BT stack aborts x11, face HAL x2, STK/externalstorage ANRs, 263 freezer exits, 879 failed one-way binder calls) - not fixable in the app (ADR-7/8).
**Ruled out:** seccomp/SIGSYS (0), UnsatisfiedLinkError (0), FATAL EXCEPTION (0), SELinux blocking exec from the data dir (312 `granted { execute }`), phantom-process killer (disabled), OS killing proot (no events).

## Tasks (do in order)
### F1 - Make the failure visible (ADR-1, ADR-2)  [highest value; decisive]
- Change: where the app launches proot, capture stdout+stderr and the exit status; write them to logcat (tag `IntelNode`, with pid and elapsed seconds) AND to `files/containers/0/tmp/stage2.log`.
- Verify: `adb -s <serial> logcat -d | grep IntelNode` shows `proot exited code=N after Ts` for every relaunch; N and the last stderr lines name the cause.
- Rollback: remove the logging lines (behaviour otherwise unchanged).

### F2 - Backoff and a ceiling on proot restarts (ADR-1)
- Change: exponential backoff (1 s, 2 s, 4 s ...) with a maximum attempt count; after the cap show a visible error with the last stderr instead of silently idling.
- Verify: a forced-failing guest produces at most N launches and a UI error; no burst like 7 relaunches in 30 s.

### F3 - Resolve the cause once F1 names it (ADR-1)
- Decision table: exit code 127/126 -> missing or non-executable guest binary; 1/2 with a path in stderr -> bind/mount target or proc setup (look at ADR-5 setattr/getattr paths first); 137 (SIGKILL) -> something killed it despite no logged event, check kernel OOM; 0 quickly -> guest command is not a long-running foreground process (proot exits when its command ends).
- Note: ADR-5's denials were present in the healthy 8.6-min run, so do not start by "fixing" them.

### F4 - Skip kernel/initramfs work in the rootfs bootstrap (ADR-3)
- Change: do not install kernel packages or run mkinitcpio/microcode/firmware hooks inside the container (e.g. pacman `--noscriptlet` for those packages, `IgnorePkg`, or a rootfs image without a kernel).
- Verify: `files/containers/0/var/log/pacman.log` has no `Creating gzip-compressed initcpio image` after a fresh bootstrap; bootstrap time drops.

### F5 - Clean up staging after a successful swap (ADR-4)
- Change: delete `containers/<n>_staging` once `containers/<n>` is committed.
- Verify: `adb shell run-as com.daripper91.daripped du -sk files/containers/*` shows no `_staging`; ~1.5 GB freed.

### F6 - Device-side (not code)
- Memory: close or freeze heavy background apps before a long bootstrap; leave the phantom-process setting as is (already disabled).
- Android 17 DP: report the Bluetooth abort (`bluetooth::log::fatal`) and face-HAL watchdog to Google with the tombstones; expect platform instability until a stable release.

## Still unknown (coverage gaps)
`/data/anr` traces unreadable; no dropbox; proot exit status never captured; PSI memory unreadable; only 1h55m of logcat. The audit deliberately did NOT clear logcat or touch the app, because another session is actively debugging it.
