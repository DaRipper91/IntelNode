# Agent Report

## Summary
Installed an Android SDK/native ARM64 toolchain and **built IntelNode's debug APK successfully on this M1/Fedora Asahi laptop**. Preserved the uncommitted XFCE rendering fixes on branch fix/xfce-rendering. No APK installation, app-data deletion, commit, push, PR or release.

New documentation: docs/asahi-apk-build.md records exact source archives/hashes, host setup, local build launcher, build failure/recovery, artifact validation and remaining native/runtime gaps. AGENT_REPORT.md is this report; (OLD) AGENT_REPORT.md preserves the prior performance-fix report. The performance plan was updated to supersede the missing-SDK blocker. Application code was not changed during this SDK/build task.

## Feature / Task Status
- Local Android toolchain: installed and executed successfully. SDK at /home/daripper/Android/Sdk; API 36 plus plugin APIs 33/34/35; ARM64 build-tools 37.0.0 with aapt2 override; exact NDK 27.0.12077973 from custom r27; official ARM64 CMake 3.22.1; existing Java 17 / Ninja.
- Local debug APK: built successfully, includes current uncommitted rendering fixes. Successful build: 184.8 s; 65,566,685 bytes. Download copy: /home/daripper/Downloads/IntelNode-xfce-rendering-local-debug-20261116.apk.
- Signature and ZIP alignment: verified, local debug key and APK v2 signature; zipalign -c -P16 4 passed.
- Tests: 167 passed after the build; analysis retains 18 pre-existing infos. pubspec.lock unchanged.
- XFCE freezes: unresolved/unmeasured on device. Previous three configuration fixes remain in working tree; see (OLD) AGENT_REPORT.md and performance plan.
- Release/profile builds: not verified; downloaded Android release gen_snapshot is x86-64. Debug success does not establish release/profile host compatibility.
- Native 16 KiB ELF alignment:3 of 24 AArch64 ELF files have 4 KiB PT_LOAD alignment. No claim of complete 16 KiB-native compatibility or successful phone startup.

## What the Next Agent Should Do First
1. Read docs/asahi-apk-build.md and current git status. Reuse /home/daripper/.cache/intelnode-tools/build-intelnode-apk.sh debug for a bounded local build. The ignored android/local.properties points to SDK/Flutter/CMake. No tracked Gradle config or CI changes were needed.
2. The launcher applies 1.5 GiB Gradle heap, one worker, Kotlin in-process, native aapt2, and a narrow Jetifier ignore regex for Flutter's native-only debug JAR; systemd memory cap 3 GiB and swap cap 3 GiB. Avoid the project's tracked 16 GiB default heap on this 8 GiB machine. Full setup receipt: /home/daripper/.cache/intelnode-tools/toolchain-sources.json.
3. Before updating an existing phone app, compare installed and new signing certificates. This APK is locally debug-signed; it is not assumed to share CI's stable signing key. Never uninstall or clear app data to bypass a signing mismatch without user authorization.
4. Restore physical-phone access or set up an explicitly chosen local Android runtime, then reproduce the same XFCE menu/window actions. Preserve logs, verify device identity, and test compositor changes one at a time. Never am start MainActivity over a live X11 screen.
5. For full 16 KiB support, investigate/rebuild libXlorie.so, libexec_getifaddrs_bridge_server.so and libnative-socket.so; ZIP alignment passing alone does not fix ELF alignment. For release/profile, supply a compatible host AOT compiler before claiming support.

## Blocking Issues
No blocker to local debug compilation remains. No physical-phone/emulator runtime verification. Earlier Tailscale/KDE Connect access failed; not reconfigured in this SDK task. Local debug signing compatibility with the installed phone APK is unknown. Three native libraries retain 4 KiB ELF alignment. Release/profile AOT host tooling remains unverified.

## Build / Test Status
- Build: PASS, local debug ARM64 Flutter target, exit 0. /home/daripper/.cache/intelnode-tools/build-debug-20261116T190031Z.log.
- Initial build:failed after dependency resolution due to Jetifier Java heap exhaustion; verified offending JAR contains only two native libs/no Java/XML. Narrow local ignore rule resolved it with unchanged memory limits.
- Tests: PASS, 167 tests, flutter test --no-pub --concurrency=1.
- Lint:flutter analyze --no-pub --no-fatal-infos, same 18 existing infos, no new issues.
- Artifact SHA256: ca221abae0e601dcf91fbc988754b6ff36d9ad954846e55863b1e12e7a196d2d.
- Local signing cert SHA256: 0c3b05210576d98e0080195462fcdb5aeb46443778c62b97fa6b91f133e0b4d6.
- Lock SHA256 unchanged:88d280c82f85236b96a8c8079c365e2ee7e8488e80e8e2a837aa03680af168fa.
- Device/emulator: NOT RUN. Source remains uncommitted on fix/xfce-rendering.
