# IntelNode Desktop Environments Manifest Audit Fix Plan — 2026-11-17

**Target:** `lib/desktop_environments.dart`
**Commit:** 6abe7ec94f7eee1a8aeffd8652083de69096a295

## Evidence Summary

- `DesktopEnvironments.all` contains 12 entries: xfce4, lxqt, mate, i3, openbox, fluxbox, icewm, lxde, awesome, bspwm, enlightenment, cinnamon, plus niri, cosmic experimental【read_file】
- `DesktopTier.stable` for X11 desktops, `DesktopTier.experimental` for Wayland【read_file】
- `packagesByFamily` maps per `PackageManagerFamily`【read_file】
- Experimental entries have `experimentalCaveat` text【read_file】

## Findings

### F1 - Experimental Wayland entries shown but unusable [MEDIUM]
- **Evidence:** `niri` and `cosmic` have `tier: DesktopTier.experimental`, `sessionType: SessionType.wayland`, `experimentalCaveat` describes missing compositor bridge【read_file】
- **Impact:** Picker shows them as disabled preview; UI shows "Preview, not installable yet." Could confuse users.
- **Fix:** Hide experimental entries from first-run picker; move to advanced settings with warning dialog.

### F2 - Package names inconsistent across distros [MEDIUM]
- **Evidence:** `xfce4` packages for `dnf` list 9 packages, for `apt` 3 packages【read_file】
- **Impact:** Install may fail on distros where package names differ; no per-distro overrides except `packagesByDistroId`.
- **Fix:** Populate `packagesByDistroId` for known mismatches; add CI test verifying packages exist in upstream repo metadata.

### F3 - Missing `dbus` on some WM entries [LOW]
- **Evidence:** `i3` packages for `pacman` include `dbus`, for `dnf` includes `dbus-x11`【read_file】
- **Impact:** Session may lack D-Bus, breaking autostart.
- **Fix:** Standardize D-Bus package naming per family; add lint test ensuring `dbus` present for all X11 sessions.

### F4 - `xinitrcExec` may not match installed session binary [MEDIUM]
- **Evidence:** `xfce4` uses `startxfce4`, `lxqt` uses `startlxqt`, `awesome` uses `awesome`【read_file】
- **Impact:** If package installs session script under different name, `start-desktop` fails.
- **Fix:** Verify `xinitrcExec` matches actual binary in each distro's package metadata; add integration test.

### F5 - No resource usage hints in picker [LOW]
- **Evidence:** Descriptions do not mention RAM/CPU footprint【read_file】
- **Impact:** Users may pick heavy desktop on low-end device.
- **Fix:** Add `estimatedRamMb` field to `DesktopEnvironmentSpec`, show in picker subtitle.

## Strengths

- **Tier separation**: Stable vs experimental clearly marked【read_file】
- **Config-driven**: Adding DE is one entry, no UI change【read_file】
- **Kind separation**: `DesktopKind.environment` vs `windowManager` for grouping【read_file】
- **Experimental caveats**: Detailed text explains Wayland bridge problem【read_file】

## Coverage Gaps

- No automated test checking package names exist in distro repos
- No device test for each DE session start

## Tasks

1. **Hide experimental from first run**
   - Change: Filter `DesktopEnvironments.forTier(DesktopTier.stable)` in `desktop_picker.dart`
   - Verify: Picker only shows stable entries
   - Rollback: Revert filter

2. **Add resource hints**
   - Change: Add `estimatedRamMb` to spec, update picker subtitle
   - Verify: UI shows RAM hint
   - Rollback: Remove field

3. **Standardize D-Bus packages**
   - Change: Audit all entries, ensure D-Bus package present
   - Verify: `grep` shows no missing D-Bus
   - Rollback: Git revert

## Critic Pass
Clean pass? Yes — findings cited from file content.
