# XFCE interaction freezes: evidence and ordered work

Baseline: main `172c51d07a4d37e0aba1c5402b6e5094578dc229` (working XFCE startup confirmed by the user). Audit: `.audit/perf-rip/SCRATCH.md`, independent critic **Clean pass? Yes**. Skills applied: android-adb-debug, apk-debug-rip, perf-rip, systematic-debugging. Date: 2026-11-16.

## Current conclusion

The user's menu/window freezes have **not been reproduced or explained**. No latency improvement has been measured. Source investigation reproduced two optional VirGL configuration defects and found an existing-install update gap; these are distinct from a proven cause of the freeze. VirGL is disabled by default, so fixing that path alone cannot be presented as solving default-session freezes.

The local checkout is a shallow sparse clone under `/home/daripper/Projects/IntelNode`, on `fix/xfce-rendering`. No APK installed, app data cleared, app relaunched, logcat cleared, or phone settings changed during the audit.

## 1. Capture the freeze and isolate the responsible layer — PERF-3/PERF-4

- **Change:** No production setting change yet. Restore an ADB connection, pin its serial, verify model/ABI/SDK/fingerprint and installed package/build type. Check for another debugging session before interacting with the app. Preserve current log buffers. Capture a bounded logcat window, ApplicationExitInfo, guest session log, app/PRoot/xfwm4/glycin processes and thread state before and during a menu/window freeze. Request bugreport traces if accessible and needed. Record Android kills separately from guest session exits.
- **Measure:** Repeat a fixed sequence (open menu, close menu, open file manager, close window) on the same desktop/resolution; record counts, visible recovery time and CPU/memory. Flutter gfxinfo alone does not measure the embedded native X11 desktop. Determine whether guest input handling, window manager, X11 requests, or Android activity is unresponsive.
- **Isolated experiment:** Read and save actual XFCE `use_compositing` and `vblank_mode` via the running session's D-Bus environment. Disable compositing temporarily for one comparison; restore the recorded value afterwards. Do not change driver, scaling and compositor together. If changing compositor does not improve the same reproducer, discard the hypothesis. No persistent default without evidence.
- **Verify:** Same bounded action sequence before/after, no new app/guest crashes or missing windows, measured recovery/latency; validate using the actual installed build and later a profile/release build.
- **Rollback:** Restore original xfconf values; leave the existing working APK/container untouched.
- **Current blocker:** Both Tailscale ADB attempts timed out; coordination-server HTTPS timed out; KDE Connect paired Pixel is unreachable. NetworkManager says `full` while Tailscale netcheck reports `CaptivePortal: true`, so captive-portal diagnosis itself is unconfirmed. Local service restarted with configuration retained, but connectivity not restored.

## 2. Correct configured rendering, without enabling acceleration — PERF-1/PERF-5

- **Exact change:** In desktop startup, respect an explicit `GALLIUM_DRIVER`; retain software fallback when none is selected. Resolve only supported `$CONTAINER_DIR` / `${CONTAINER_DIR}` placeholders in VirGL argument tokens before shell quoting. Continue quoting every final argument; never use eval or expand arbitrary shell expressions. Preserve the current off-by-default acceleration setting and native X11 startup. Do not assume Mali/Adreno capabilities from the handset name.
- **Verify:** Regression tests execute the actual script with controlled display-readiness and session commands, and confirm `virpipe`, explicit software drivers, legacy flag behavior, default fallback and session exit propagation. Execute generated server arguments through a shell capture stub and check the socket is one concrete absolute-path argument, including paths containing spaces/quotes/dollar characters. Check unrelated shell expressions remain literal and have no side effects.
- **Device gate:** With explicit user-selected acceleration on suitable hardware, verify native server socket creation, guest renderer info and the original action sequence; desktop-startup tests do not prove GPU performance.
- **Rollback:** Revert the narrow command/driver changes; default software rendering remains available.

## 3. Deliver the managed desktop script to existing containers — PERF-2

- **Exact change:** After bootstrap exists and any requested reinstall completes, refresh only the app-owned `tiny/extra/start-desktop` asset before starting the container. Do not reinstall the rootfs, overwrite user XFCE configuration, or refresh the separate start-arch.sh in this task.
- **Verify:** Start with an old installed start-desktop, replace it from an injected asset copy in a temporary directory, assert new bytes and that adjacent files/user configuration survive. Propagate copy failures rather than booting with an undisclosed stale script. Run full Flutter tests and analyze; compare analysis to the existing 18 informational findings.
- **Rollback:** Revert the targeted refresh. If device testing had installed the new managed script, restore the saved previous script; no container deletion needed.

## 4. Act on helper back-pressure only if observed — PERF-4

- **Exact change:** First measure output volume and blocked pipe writers for executeBackground daemons. If reproduced, drain stdout/stderr through bounded, nonblocking handling and log unexpected exits. Do not add unbounded log queues or blindly suppress diagnostics.
- **Verify:** Pipe-saturation reproduction and long menu/window workload; check helper survival, memory bound and shutdown behavior.
- **Rollback:** Revert helper stream-handling change independently of renderer changes.

## Coverage gaps and strengths

No connected phone, freeze reproduction, live compositor state, active GPU/driver state, crash census, ANR trace, CPU/memory series, latency percentiles, or profile/release performance comparison. No claim that missing device errors were searched and absent. Browser web vitals and Python import timing do not apply. Android SDK initially absent; the pinned local Flutter toolchain is now installed. Baseline and final results are recorded below and in AGENT_REPORT.md.

Preserve: dedicated native X-server Looper thread; known working PRoot/installer lifecycle; per-launch compatibility shims; capped/rotating diagnostic logs. Do not replace the bwrap shim or change syscall/seccomp policy without new evidence.


## Implementation checkpoint

Tasks 2 and 3 implemented locally on `fix/xfce-rendering`: explicit drivers survive desktop startup; supported container-path placeholders are resolved before quoting VirGL arguments; normal startup refreshes only the managed desktop asset. Settings, compositor policy, scaling, and rootfs are unchanged. Source review found no concrete regressions.

Verification: full Flutter suite **167 passed** (153 baseline + 14 regression tests); analysis exit 0 with the same **18 pre-existing infos**; shellcheck, Bash syntax, and Git whitespace checks pass. The regression tests were observed failing against the prior behavior before implementation. pubspec.lock checksum unchanged. APK build attempted and stopped with **No Android SDK found**. No APK or runtime test performed; the user's freeze remains unresolved.

### Local Android test target

Waydroid is not installed. The live Asahi kernel is `7.2.12-402.asahi.fc44.aarch64+16k`, with `CONFIG_ANDROID_BINDER_IPC=y`, `CONFIG_ANDROID_BINDERFS=y`, and `CONFIG_MEMFD_CREATE=y`. A custom ARM64 Android image supporting 16 KiB pages and Asahi graphics is required. Primary references: [Waydroid architecture](https://docs.waydro.id/), [Asahi image build guide](https://github.com/UtkarshVerma/waydroid-on-asahi). The previously popular [prebuilt-image repository](https://github.com/yuk1n0w/waydroid-on-asahi) now says its maintainer no longer uses Asahi; do not assume it is maintained. No custom image was downloaded, installed or initialized.

Waydroid could supply repeatable installer/session/interaction coverage once actual PRoot/ptrace and X11 compatibility is verified. Because it shares the host kernel and uses different graphics/Android userspace, passing there cannot establish Pixel-specific performance, Android 17 ANR behavior or native-driver compatibility. Keep physical-phone validation as a separate gate.


## Subsequent local SDK/build checkpoint

The missing Android SDK blocker is resolved: native ARM64 SDK/NDK/CMake installed and the debug APK built locally (exit0,184.8s after caches). See ../asahi-apk-build.md for the exact toolchain, narrow local Jetifier workaround, artifact hash/signature and16KiB ELF limitations. Post-build suite167 passed; analysis remains18 pre-existing infos. Phone/emulator freeze reproduction and measured improvements remain outstanding.
