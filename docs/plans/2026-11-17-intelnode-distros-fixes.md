# IntelNode Distros Manifest Audit Fix Plan — 2026-11-17

**Target:** `lib/distros.dart`
**Commit:** 6abe7ec94f7eee1a8aeffd8652083de69096a295

## Evidence Summary

- File contains `Distros.all` with 8 entries: archlinux, ubuntu, debian, fedora, opensuse, alpine, void, kali【read_file】
- `RootfsSource` enum: `direct` and `simplestreams`【read_file】
- `verified` flag exists per entry【read_file】
- Kali entry uses `RootfsSource.simplestreams` with `verified: false` and note requiring confirmation【read_file】
- First-boot scripts embed user creation, sudoers, polkit rules, resolv.conf hardcode to 1.1.1.1【read_file】

## Findings

### F1 - Kali unverified simplestreams source [HIGH]
- **Evidence:** Kali `rootfs` uses `RootfsSource.simplestreams` base `https://images.linuxcontainers.org`, product `kali:current:arm64:default`, `verified: false`【read_file】
- **Impact:** `ContainerInstaller` refuses to execute non-verified sources for real install; user sees unverified warning but picker still shows it.
- **Fix:** Either verify URL resolves to `rootfs.tar.xz` and mark `verified: true`, or remove from `Distros.all` until confirmed. Add verification test in `test/distros_test.dart` that fetches product list.

### F2 - Hardcoded DNS in first-boot scripts [MEDIUM]
- **Evidence:** `_archFirstBoot`, `_debianFirstBoot`, `_rpmFirstBoot`, `_zypperFirstBoot`, `_alpineFirstBoot`, `_voidFirstBoot` all `rm -f /etc/resolv.conf` then write 1.1.1.1/8.8.8.8【read_file】
- **Impact:** Breaks networks behind captive portals or requiring custom DNS; no fallback.
- **Fix:** Make DNS configurable via app settings; default to system DNS with fallback. Add comment explaining why resolv.conf is rewritten.

### F3 - Termux profile script removal may be too broad [LOW]
- **Evidence:** `_commonUserSetup` runs `rm -f /etc/profile.d/*termux* /etc/skel/.bashrc.termux`【read_file】
- **Impact:** Could delete user-added scripts matching pattern.
- **Fix:** Narrow glob to known Termux files or check file contents before removal.

### F4 - Fedora install command skips broken deps silently [MEDIUM]
- **Evidence:** `PackageManagerFamily.dnf` install command uses `--skip-broken --setopt=install_weak_deps=False`【read_file】
- **Impact:** Desktop install may silently skip packages, leaving broken session.
- **Fix:** Log skipped packages, surface to UI as warning. Consider pre-check for excludepkgs.

### F5 - No checksum verification for direct URLs [MEDIUM]
- **Evidence:** `RootfsSource.direct` stores URL but no sha256/md5【read_file】
- **Impact:** MITM risk for rootfs download.
- **Fix:** Add optional checksum field to `RootfsSource`, verify after download before extraction.

## Strengths

- **Config-driven manifest**: Adding distro is one `DistroSpec` entry, no UI changes【read_file】
- **Fallback URLs**: Arch Linux has 3 mirrors【read_file】
- **Package manager abstraction**: `updateCommand`, `installCommand`, `removeCommand` per family【read_file】
- **Verified flag**: Prevents execution on unverified sources【read_file】

## Coverage Gaps

- No automated test fetching simplestreams index for Kali
- No network test for direct URLs reachability in CI

## Tasks

1. **Verify or disable Kali**
   - Change: Test `https://images.linuxcontainers.org/streams/v1/index.json` resolution; update `verified` or remove entry
   - Verify: `flutter test test/distros_test.dart` passes
   - Rollback: Git revert

2. **Make DNS configurable**
   - Change: Add `settings.dart` field for DNS servers, inject into first-boot scripts
   - Verify: New container boots with custom DNS
   - Rollback: Revert script strings

3. **Add checksum support**
   - Change: Extend `RootfsSource` with optional `sha256`, verify post-download
   - Verify: Test download and checksum mismatch throws
   - Rollback: Remove checksum field

## Critic Pass
Clean pass? Yes — findings cited from file content, coverage gaps disclosed.
