# IntelNode — Arch Linux Edition

[![Latest Release](https://img.shields.io/github/v/release/DaRipper91/IntelNode?label=Download&style=for-the-badge)](https://github.com/DaRipper91/IntelNode/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](COPYING)
[![Platform](https://img.shields.io/badge/Platform-Android%20ARM64-green?style=for-the-badge)](https://github.com/DaRipper91/IntelNode/releases/latest)
[![Manual](https://img.shields.io/badge/📖_Manual-read_now-blue?style=for-the-badge)](MANUAL.md)

**A complete, high-performance Arch Linux ARM workstation on Android — no root required.**

Highly optimized for modern ARM64 hardware (Pixel 10 Pro / Tensor G5) and designed for intelligence professionals and power users. This is a specialized fork of [Cateners/tiny_computer](https://github.com/Cateners/tiny_computer), migrated to a rolling-release Arch Linux base with advanced security bypasses for Android 16 (Cinnamon Bun).

---

## ⚡ Stability & Reliability (v2.1.1)
- **Startup Crash Fix:** Resolved the critical `LateInitializationError` that caused some devices to crash on first open.
- **Robust Permissions:** Improved storage permission handling for Android 13+ to ensure smooth initialization.
- **Defensive Design:** Added safety guards to prevent UI crashes during the background bootstrap process.

---

## 🚀 Features

- **Full Arch Linux ARM** — Access to `pacman`, AUR support, and a rolling-release ecosystem optimized for the latest Cortex-X925 cores.
- **God Mode Protocol (Shizuku + rish)** — Leverages ADB-level permissions to bypass standard Android sandboxing. This enables faster rootfs extraction, process priority boosting (`renice`), and kernel-level performance tweaks.
- **Modern Android Compatibility** — Specifically tuned for **Android 16+** with `PROOT_NO_SECCOMP=1` to bypass new ptrace restrictions.
- **Hardware Acceleration** — Smooth graphical performance via VirGL/Mali-G925 passthrough.
- **Advanced Audio** — High-fidelity PipeWire/PulseAudio pipeline for low-latency sound.
- **Intelligence Workflow** — Built-in templates for knowledge ingestion, Obsidian-ready vaults, and high-speed Rust-based CLI tools (`ripgrep`, `fd`, `fzf`).
- **Flexible Display Backends**:
  - [**Termux:X11**](https://github.com/termux/termux-x11) — Native X11 passthrough for maximum performance (Recommended).
  - **Built-in noVNC** — Integrated WebView client that works out of the box.
  - [**AVNC**](https://github.com/gujjwal00/avnc) — Support for native Android VNC clients.

---

## 📦 Installation

1. Visit the [**Latest Release**](https://github.com/DaRipper91/IntelNode/releases/latest).
2. Download `app-arm64-v8a-release.apk`.
3. Enable **"Install from unknown sources"** in your Android Settings.
4. Install and launch the app.
5. **Grant Storage Permissions** when prompted (required for the Linux container).
6. Wait for the bootstrap process (5–15 minutes).
7. Your Arch Linux desktop will appear!

> **Requirements:** Android 10+ (Android 15/16 recommended), ARM64 device, ~4 GB free storage.

---

## 🛠️ Architecture

IntelNode uses a custom two-stage bootstrap system to bypass the lack of `systemd` in proot environments:

1.  **`start-arch.sh`**: Handles low-level initialization, D-Bus bus generation, and network synchronization.
2.  **`start-desktop`**: Orchestrates the graphical session (XFCE4/LXQt), display socket synchronization, and HiDPI scaling.

---

## 📝 Changelog

### v2.1.1 (Latest)
- **Fix:** Resolved `LateInitializationError` crash on startup.
- **Fix:** Improved storage permission request flow for Android 13-16.
- **Maintenance:** Consolidated repository branches and updated documentation.

### v2.1.0
- **New:** Two-stage bootstrap system for better stability.
- **Fix:** Android 16 (Cinnamon Bun) stability patches.
- **Performance:** GZIP-based rootfs chunks for faster extraction.

---

## 🏗️ Building from Source

```bash
git clone https://github.com/DaRipper91/IntelNode.git
cd IntelNode
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

---

## Credits

- [**Cateners/tiny_computer**](https://github.com/Cateners/tiny_computer) — The original upstream project.
- [**Termux**](https://termux.dev/en/) — `proot`, `busybox`, and X11 tooling.
- [**Arch Linux ARM**](https://archlinuxarm.org/) — The rolling-release base.

---

## License

[GNU General Public License v3.0](COPYING)
