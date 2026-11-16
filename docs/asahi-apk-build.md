# Building IntelNode on Fedora Asahi ARM64

Local setup date: 2026-11-16. Host: M1 MacBook Air, Fedora Asahi 44, 16 KiB kernel pages, 8 GB RAM. Android Studio and Waydroid are not required for APK compilation.

## Installed toolchain

| Component | Version / location | Source |
|---|---|---|
| Flutter / Dart | 3.41.6 / 3.11.4, `/home/daripper/.cache/intelnode-tools/flutter` | Pinned official Flutter tag, matching CI |
| Java | Temurin 17.0.10, existing system installation | `/usr/bin/java` |
| Android SDK | `/home/daripper/Android/Sdk` | [ARM64 SDK build](https://github.com/HomuHomu833/android-sdk-custom/releases/tag/37.0.0) |
| SDK platform | Android API 36 | Google SDK Manager |
| Build tools | Official 35.0.0 plus native ARM64 37.0.0 | SDK Manager and ARM64 SDK archive |
| Resource compiler | ARM64 `build-tools/37.0.0/aapt2` | Per-build Gradle override; avoids Maven's x86-64 binary |
| NDK | **27.0.12077973**, `Sdk/ndk/27.0.12077973` | [ARM64 r27 build](https://github.com/HomuHomu833/android-ndk-custom/releases/tag/r27) |
| CMake | **3.22.1**, `/home/daripper/.cache/intelnode-tools/installed/cmake-3.22.1-linux-aarch64` | [Official Kitware ARM64 release](https://github.com/Kitware/CMake/releases/tag/v3.22.1) |
| Ninja | 1.13.2, existing `/usr/bin/ninja` | Fedora |

The NDK's actual `source.properties` reports revision 27.0.12077973, matching the project. Its `linux-arm64` compiler is an AArch64 static executable; its provided `linux-x86_64` path is a compatibility symlink to that native toolchain, not an emulated compiler. Native `clang --version`, CMake and aapt2 were executed successfully.

Downloaded archives were SHA-256 checked before extraction:

| Archive | SHA-256 |
|---|---|
| android-sdk-aarch64-linux-musl.tar.xz, SDK 37.0.0 | `0d5d5455871591dfbf82959d433ecdd6fed0c5c97bec757f2e79657bad27b75c` |
| android-ndk-r27-aarch64-linux-musl.tar.xz | `10a851646fe065895c40becb9b7b9f8480d9ad44b7d77322706689fca9fd0bf8` |
| cmake-3.22.1-linux-aarch64.tar.gz | `601443375aa1a48a1a076bda7e3cca73af88400463e166fffc3e1da3ce03540b` |

SDK/NDK digests came from GitHub release asset metadata; CMake was checked against Kitware's release checksum file. Archives and a machine-readable receipt are under `/home/daripper/.cache/intelnode-tools/`.

## Local configuration

The ignored `android/local.properties` contains this host's `sdk.dir`, `flutter.sdk`, and `cmake.dir`. The existing tracked Gradle configuration, pinned NDK version, lock file and CI workflows are preserved.

The host launcher is `/home/daripper/.cache/intelnode-tools/build-intelnode-apk.sh`. It accepts `debug`, `profile`, or `release` (default: `debug`) and targets Android ARM64. A build mode being accepted by the launcher does not establish that mode has been verified on this host.

The launcher sets the SDK and tool paths, selects native aapt2 through `ORG_GRADLE_PROJECT_android.aapt2FromMavenOverride`, and requests Kotlin compilation in-process. It overrides the project's 16 GB Gradle heap **locally** with a 1536 MB heap, one Gradle worker, and no parallel project builds. The build runs through the existing `capped` helper in a user systemd scope with MemoryHigh=2300M, MemoryMax=3G and MemorySwapMax=3G. Host D-Bus/network access is necessary for this scope and dependency downloads.

The first build downloads Gradle/Maven dependencies. Subsequent builds can reuse that cache. SDK Manager may install additional required platform packages during configuration.

## Verification and artifact

**Debug build succeeded locally**, exit 0, on 2026-11-16. The successful retry took 184.8 seconds with dependencies cached. Log: `/home/daripper/.cache/intelnode-tools/build-debug-20261116T190031Z.log`.

The first attempt failed with Java heap exhaustion in JetifyTransform. Inspection of Flutter's ARM64 debug JAR found only two native `.so` entries, totaling 600,595,144 uncompressed bytes, and no Java/XML to migrate. The launcher now sets `android.jetifier.ignorelist=.*arm64_v8a_debug.*` only for this local build environment, avoiding unnecessary transformation of that native-only archive. Jetifier remains enabled for other dependencies and tracked Gradle configuration is unchanged. With the same heap/scope limits, the retry succeeded. SDK platforms 33, 34 and 35 were also installed automatically for plugin modules.

Artifact: `build/app/outputs/flutter-apk/app-debug.apk`; convenient copy: `/home/daripper/Downloads/IntelNode-xfce-rendering-local-debug-20261116.apk`.

- Size: **65,566,685 bytes** (62.53 MiB).
- SHA-256: `ca221abae0e601dcf91fbc988754b6ff36d9ad954846e55863b1e12e7a196d2d`.
- APK signature: `apksigner verify --verbose --print-certs` passed, APK v2, local Android Debug key. Certificate SHA-256: `0c3b05210576d98e0080195462fcdb5aeb46443778c62b97fa6b91f133e0b4d6`.
- ZIP alignment: `zipalign -c -P 16 4` passed.
- Updated start-desktop asset exactly matches source; ARM64 libnative-socket.so is present.
- Packaged native directories include arm64-v8a, armeabi-v7a and x86_64 from dependencies; the Flutter engine target is ARM64. Other architectures are not validated runtime targets.
- Post-build full suite: **167 tests passed**. Analysis: 18 pre-existing informational findings, no new issues. Lock file unchanged.

**ELF alignment remains distinct from ZIP alignment.** Of 24 AArch64 ELF files checked, three have 4 KiB PT_LOAD alignment: libXlorie.so, libexec_getifaddrs_bridge_server.so and libnative-socket.so. The embedded libproot-loader32.so is an ARM32 helper. The build is not claimed fully 16 KiB-native compatible; no phone/emulator runtime test has been performed.

## Runtime coverage

Compiling/signing an APK does not verify the user's XFCE menu/window freeze. Keep the working phone installation and app data intact until an explicit device test. A local APK uses the available local signing configuration; upgrade compatibility with CI APKs requires matching certificates.

Release/profile AOT tooling also needs a compatible host `gen_snapshot`. The downloaded Flutter Android ARM64 release `linux-x64/gen_snapshot` is x86-64; release/profile compilation has not been established by the SDK installation alone. Debug compilation is the first target.
