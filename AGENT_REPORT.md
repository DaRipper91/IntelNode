# Agent Report

**Author:** Antigravity (agy) · **Date:** 2026-11-17 · **Repo:** `DaRipper91/IntelNode` (`~/Projects/DaRipped_tiny_computer`) · **Branch:** `fix/new-container-wrapper-dir`

---

## Executive Summary
All available Linux distributions in IntelNode have been verified on physical hardware (**Nothing Phone 2a**, model A142, Android 16, Magisk root, wireless ADB). Every non-Arch distribution previously suffered from multiple root-level provisioning or extraction failures; all root causes were identified, fixed, and verified on-device.

Each distribution was installed using the smallest window manager (**Fluxbox**; Fedora additionally verified with **XFCE4**), verified against its installed filesystem and session binary, and then deleted using the new in-app **Delete Containers** dialog. Surviving containers, filesystem trees, and shared preferences were verified intact after every deletion cycle. Container 0 (Arch Linux ARM default) remained untouched and operational throughout.

Unit/integration test suite: **202/202 passed**. Static analyzer: **18 info-level baseline issues**, zero warnings, zero errors.

---

## On-Device Multi-Distro Verification Results

| Distro | Desktop | Install Time | Key Fix Applied | Session Verified | Deletion Verified |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Fedora 40** | XFCE4 | ~420s | Replaced 1064-pkg group with 156 explicit packages; skips `kernel-core`/`dracut` | `/usr/bin/startxfce4` | Verified (cleaned from disk & prefs) |
| **openSUSE Leap 16.0** | Fluxbox | ~330s | Dropped `--link2symlink` from `prootRun` (prevented broken zypper cache hardlinks); added cache clean & force refresh | `/usr/bin/startfluxbox` | Verified (cleaned from disk & prefs) |
| **Debian 12 Bookworm** | Fluxbox | 291s | Added `--exclude='dev/*'` to tar extraction (bypassed EPERM on static `/dev/*` character nodes) | `/usr/bin/startfluxbox` | Verified (cleaned from disk & prefs) |
| **Alpine Linux v3.22** | Fluxbox | 32s | Verified multi-repo setup (`main` + `community`), rapid apk install | `/usr/bin/startfluxbox` | Verified (cleaned from disk & prefs) |
| **Void Linux** | Fluxbox | 176s | Added `xbps-install -uy xbps` prior to package transactions | `/usr/bin/startfluxbox` | Verified (cleaned from disk & prefs) |
| **Ubuntu 24.04 LTS** | Fluxbox | 374s | Cloud image tarball extraction with `--exclude='dev/*'` and user reassignment | `/usr/bin/startfluxbox` | Verified (cleaned from disk & prefs) |

---

## Root Causes Identified and Fixed

### 1. Fedora 40 Package Group Bloat & DNF SELinux Exclusions
- **Symptom:** Fedora package install pulled in 1064 packages including kernel initramfs (`dracut`), which hung for 10+ minutes.
- **Root Cause:** DNF `@<name>-desktop-environment` groups depend on kernel and hardware firmware. Furthermore, `/etc/dnf/dnf.conf` shipped `excludepkgs=*selinux*`, which broke desktop groups that depend on SELinux libraries.
- **Fix:** Switched Fedora desktop packages to explicit, index-verified package lists from Fedora 40 Everything aarch64 repository. Added `--skip-broken --setopt=install_weak_deps=False` and post-install `sessionCheckScript` to verify the desktop executable exists.

### 2. PRoot `--link2symlink` Breaking Zypper Hardlinks (openSUSE)
- **Symptom:** Zypper failed with exit code 4: `Can't open solv-file: /var/cache/zypp/solv/openSUSE:repo-oss/solv`.
- **Root Cause:** Zypper downloads repo metadata to `/var/tmp/AP_...` and hard-links it to `/var/cache/zypp/raw/...`. PRoot's `--link2symlink` replaced the hard link with a symlink pointing to the temporary attach point in `/var/tmp`. When zypper cleaned up its temporary files, the cache symlink became dangling, breaking `repo2solv`.
- **Fix:** Dropped `--link2symlink` from `ContainerInstaller.prootRun`. Android internal storage (`/data/user/0/...`) is native ext4/f2fs and supports hard links natively. Added zypper cache wipe and force refresh (`rm -rf /var/cache/zypp/* /var/tmp/* && zypper clean -a && zypper refresh -f`) during `_zypperFirstBoot`.

### 3. Tar `mknod()` EPERM on Static Device Nodes (Debian)
- **Symptom:** Debian rootfs extraction failed with exit code 2: `tar: debian-bookworm-aarch64/dev/null: Cannot mknod: Operation not permitted`.
- **Root Cause:** Debian debootstrap rootfs contains static character device files in `/dev/`. Android user namespaces forbid unprivileged processes from creating character or block device nodes via `mknod()`. Since PRoot mounts Android's `/dev` at runtime via `-b /dev`, static rootfs device nodes are unnecessary.
- **Fix:** Added `--exclude='dev/*'` to `ContainerInstaller.extractScript`. Tar extracts directory `dev/` cleanly while skipping device node creation.

### 4. Void Linux `xbps` Package Self-Update Lockout
- **Symptom:** Base provisioning failed with exit code 16: `ERROR: The 'xbps' package must be updated, please run xbps-install -u xbps`.
- **Root Cause:** In Void Linux, when a newer version of the package manager itself (`xbps`) is available in upstream repositories, xbps refuses all package installations until updated directly.
- **Fix:** Updated `_voidFirstBoot` and `DistroSpec.updateCommand` to run `xbps-install -uy xbps` before subsequent package operations.

### 5. Tarball Hoisting for proot-distro Archives
- **Symptom:** Proot started inside an empty container rootfs because `termux/proot-distro` tarballs wrap contents in top-level directory (e.g. `fedora-aarch64/`).
- **Fix:** `ContainerInstaller.hoistWrapperDir` detects single wrapper folders and hoists all files to the root level. Flat images (Arch, Ubuntu) remain untouched.

### 6. Delete Containers Lifecycle Verification
- **Symptom:** Untested deletion flow.
- **Verification:** Ran deletion across all 6 distributions. The UI dialog successfully identified non-running containers, preserved running Container 0, removed container directory trees, updated `containersInfo` in SharedPreferences, and confirmed filesystem state via ADB root shell.

---

## Test & Analysis Verification
- `flutter test`: **202 passed, 0 failed** (including unit tests for explicit dnf package lists, no-groups guard tests, tar exclusion tests, and proot process cleanup traps).
- `flutter analyze --no-fatal-infos`: **18 info-level items** (exact baseline from `main`).
