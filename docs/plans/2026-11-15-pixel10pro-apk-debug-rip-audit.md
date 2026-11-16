# apk-debug-rip audit - Pixel 10 Pro (wireless adb) - 2026-11-15

## Known fragile areas / intent
Owner's apps: proot-based Linux-on-Android (IntelNode / DaRipped_tiny_computer, com.daripper91.daripped). Another session had a logcat attached earlier; logcat is NOT cleared by this audit.

## 01 Recon
Device: Pixel 10 Pro (`blazer`), **Android 17 (SDK 37) Developer Preview DP11.261030.003** (`blazer_beta`), security patch 2026-10-05, arm64-v8a only, wireless adb (the address changed during the session). Uptime 1d 3h, load 5.5, 40.3 C, battery 48% on AC. Evidence: raw/recon.txt.
Installed owner apps: IntelNode `com.daripper91.daripped` v2.1.1 (versionCode 2, targetSdk 36, **DEBUGGABLE**, first install 19:08, updated 21:27 today), Termux 0.118.3 (targetSdk 28 => SELinux `untrusted_app_27`), storyforge.
**Another session is actively driving IntelNode on this phone** (adbd log: `run-as com.daripper91.daripped ...`, `am force-stop` at 21:27:06). This audit therefore did NOT clear logcat, launch or stop anything.

## 02 Evidence (raw files in raw/ and census/)
- raw/crash_buffer.txt (2 lines: empty), raw/warn_plus.txt (2,435 W+ lines), raw/all_buffers.txt (log window **19:50:53 -> 21:45:30, ~1h55m**, 37,988 lines)
- raw/tomb/* + raw/tombstones.json (32 tombstones, 2026-09-01 .. 2026-11-13); census/summary.json (script re-run)
- raw/exit_info_all.txt + census/exit_info.txt (2,863 ApplicationExitInfo records, 235 packages, 2026-03-31 .. 2026-11-15)
- raw/meminfo.txt, raw/top.txt; IntelNode guest log read via run-as: files/containers/0/var/log/pacman.log

## 03 Findings
### ADR-1  IntelNode's proot does not stay up after extraction            severity: high   status: timeline VERIFIED, cause LEAD
- Claim: IntelNode launched proot 10 times in the window: one run lasted **21:30:20 -> 21:38:58 (8.6 min)**, then **7 relaunches 21:39:44 -> 21:40:14 each living 1-3 s, spaced 1-3 s**; afterwards no proot child exists under the app (pid 31574) although it keeps running.
- Evidence: raw/all_buffers.txt (auditd lines `comm="proot" ... app=com.daripper91.daripped`, grouped by pid); `ps -A` shows only 31574 (18-19 min, 30% of one core) and two unrelated proot (Termux-side, 1d 1h and 2h38m old). No am_kill / Killing / am_proc_died / am_crash / am_anr line names any of those pids or occurs in 21:39:40-21:40:20.
- Impact: the container never reaches a running state; matches the owner's "won't boot" report.
- Hypotheses, ranked: (H1) proot/guest exits by itself with a non-zero status (most consistent: short lives, no OS kill) - needs proot's stderr/exit code; (H2) a retry supervisor in the app relaunches without backoff (shape of the burst) - amplifies H1; (H3) setattr/getattr denials turn fatal in some code path - WEAKENED: the 8.6-min run had 255 of them and survived; (H4) OS killed it - DISPROVED (no events; phantom-process monitor disabled); (H5) exec blocked by SELinux - DISPROVED (see ADR-5).
- Verify/disprove next: have the app tee proot's stdout/stderr + exit code to logcat and to files/containers/0/tmp/stage2.log (see fix plan F1); a failing run then names the cause directly.

### ADR-2  The app is silent while busy                                      severity: med    status: VERIFIED
- `logcat --pid=31574` ends at 21:27:10; at 21:48 the process has used ~30% of one core (381 user + 62 sys ticks in 15 s) with no log line for 18+ minutes. Evidence: raw (pid log tail), CPU tick sample in the transcript of this audit. Impact: crashes/loops are invisible, which is why ADR-1's cause cannot be read off the log.

### ADR-3  Rootfs bootstrap runs kernel/initramfs hooks inside proot          severity: med    status: VERIFIED (facts), impact LEAD
- guest pacman.log (UTC 02:52-02:55:57 = 20:52-20:55 CST): `mkinitcpio` builds `/boot/initramfs-linux.img`, hooks warn "architecture 'aarch64' not supported", "Possibly missing firmware for module ...", dbus hook "Failed to check for chroot() environment". A kernel and initramfs are useless in proot and cost minutes of CPU.
- NOT established: that this explains the 8.6-min proot run (21:30-21:38) - pacman.log's last write (20:55) predates it.

### ADR-4  Leftover staging directory                                         severity: low    status: VERIFIED
- files/containers/0 = 2,914,750 KB and files/containers/0_staging = 1,488,905 KB both present, neither growing (du identical 10 s apart); files/ total 3.73 GB. ~1.5 GB reclaimable if staging is stale. Cause LEAD (interrupted or never-cleaned swap).

### ADR-5  SELinux in IntelNode's own domain (untrusted_app_34)               severity: low    status: VERIFIED counts, effect LEAD
- DENIED: setattr 287 (name="/" dev=proc; fd dev=proc; sysfs /; /proc/sys; /proc/net), getattr 25, search 10. GRANTED: execute 312 on `app_data_file` (ld-linux-aarch64.so.1, bash, cp, ln, touch, find, cmp ...). So exec from the data dir works; proot's attempts to chmod/utimens procfs directories are denied.
- The 139 `read on tcp` denials are from domain **runas_app** (the other session's `run-as ... cat /proc/net/tcp`), not from the app.

### ADR-6  The phone is memory-saturated                                       severity: high   status: VERIFIED
- /proc/meminfo: 15.9 GB total, 0.9 GB free, **3.1 GB available**, swap 7.96 GB with **1.64 GB free (~80% used)**, zram 2.2 GB; top: 770 tasks, 14.7/15.5 GB used. ApplicationExitInfo: **2,001 of 2,863 exits are LOW_MEMORY** across ~200 packages (incl. Termux x6, termux.styling, storyforge). CPU is NOT the bottleneck (511% idle of 800%).
- Impact: background proot/Termux sessions are the kind of process this kills. IntelNode itself has not been OS-killed (only deliberate force-stop 21:27:06). PSI memory unreadable (permission) - pressure not measured directly.

### ADR-7  Freezer exits and failed one-way binder calls                        severity: med    status: VERIFIED occurrence, link LEAD
- 263 FREEZER exit records / 67 package groups (latest 2026-11-15 19:34; systemui x8). 879 `ActivityManager: pid 1585 system sent binder code 1 with flags 1 and got error -2147483646` (FAILED_TRANSACTION, one-way) from system_server (pid 1585) between 20:10:21 and 21:41:29 (~10/min). Target unidentified (binder failed_transaction_log needs root).

### ADR-8  Platform instability on a Developer Preview build                   severity: med    status: VERIFIED
- Tombstones: Google Bluetooth **SIGABRT x11** (`bluetooth::log::fatal` in libbluetooth_jni.so; 2026-09-04 .. 10-30), face HAL **SIGABRT x2** ("[Watchdog] RgbCamera::Open has timed out."). ANR records: 16, all system/modem components and "bg anr" (non user-perceptible): phone/stk **broadcast ANR** (StkCmdReceiver) recurring, connectivitythermalpowermanager x4, shannon imsservice, system_server once (10-11 10:30); the two traces dated 2026-11-10 18:46/18:47 correspond to **com.android.externalstorage** (exit-info), not readable directly. None involve the owner's apps; not fixable in the app.

### ADR-9  Third-party native crashes (not the owner's)                         severity: low    status: VERIFIED
- Third-party app native crashes (app names omitted on purpose): one app SIGSEGV x13 (top frames in libwebviewchromium.so; 2026-09-01 .. 11-04), another SIGTRAP x2 (11-13), two more SIGSEGV x1 each.

### ADR-10  Suspects checked and NOT found (this evidence is window-limited)
- seccomp / SIGSYS / "bad system call": 0 lines; UnsatisfiedLinkError / dlopen failed: 0; FATAL EXCEPTION involving IntelNode: 0 - **in a 1h55m log window and a ~2.5 h-old install**. Tombstones/exit-info (months) contain **0 records from the owner's own apps** except routine Termux/storyforge LOW_MEMORY/SIGNALED exits.

## COVERAGE GAPS (carried to the report)
1. /data/anr traces listable but unreadable (Permission denied); dropbox denied; /proc/pressure/memory denied; binder failed_transaction_log needs root.
2. Logcat window only 1h55m; no lmkd kill lines in it; crash buffer empty. Java crashes are invisible (no dropbox).
3. ApplicationExitInfo retains 16 records/package; crash/ANR history is pushed out by LOW_MEMORY churn.
4. 2 of 32 tombstones unparsed by the script (one is `<debuggerd signal>` = a dump request, one blank).
5. proot's exit status/stderr not captured anywhere; reproducing would change device state while another session is active, so it was NOT attempted. grab_logs.sh / triage_crash.sh were deliberately NOT run (grab_logs clears logcat).
6. No root-cause work on the third-party or Bluetooth crashes (third-party/platform).

## 04 Strengths
- Phantom-process killer is already disabled (`settings_enable_monitor_phantom_procs=false`, `max_phantom_processes=2147483647`): the usual Android 12+ proot-tree killer is ruled out by a deliberate owner fix.
- IntelNode: targetSdk 36 with only arm64-v8a native libs - no link errors; exec from the data dir works; rootfs tar (829 MB) extracts to 2.9 GB and the files stop growing (extraction completes); build is debuggable so `run-as` inspection works without root.
- The owner's apps show no native crash or ANR records in 8 months of exit-info; system_server itself was stable (no watchdog/ANR in the window).
- adb over Tailscale works and the serial can be pinned; the other session's logs are rich enough to reconstruct its actions.

## Corrections log (my own errors, found and fixed during this audit)
1. First claimed 304 `execute` DENIALS (and an SELinux/W^X cause): the lines were `granted`; hypothesis disproved and removed.
2. First claimed "0 ANR/CRASH records in 2,572 exit records": my parser dropped records; the lens script found 2,863 incl. 16 ANR and 263 FREEZER. Corrected.
3. A per-pid kill check silently never ran (zsh `$p[^0-9]`); re-run correctly -> 0 events.
4. Several greps used one space where audit lines have two; replaced with a parser.

## 05 Critic pass
Re-derived every headline number from raw files and checked citations and retractions (critic.txt): 16/16 checks PASS.

Clean pass? Yes

---
Note: the raw evidence files cited above (raw/, census/: logcat dumps, tombstones, exit-info) were kept in the session scratchpad and are not archived here; re-create them with `python3 ~/.claude/skills/apk-debug-rip/scripts/crash_summary.py <serial> <outdir>`.
