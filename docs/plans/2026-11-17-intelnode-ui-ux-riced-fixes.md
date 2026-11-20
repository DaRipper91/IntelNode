# IntelNode UI/UX Ricing & Button Audit Fix Plan — 2026-11-17

**Scope:** UI/UX, icons, in-app terminals/windows, button functions
**Targets:** `lib/main.dart`, `lib/workflow.dart`, `lib/desktop_picker.dart`, `lib/container_setup_page.dart`, `assets/icons/`

## Theme Baseline from Other Repos

Scanning `/home/daripper/Projects` READMEs for theme hints: `storyforge` uses dark banner SVGs, `Scout-Organizer` mentions themes. No explicit Catppuccin/Nord references found in READMEs. Propose **Catppuccin Mocha** inspired palette as it is popular for riced Linux apps and matches terminal aesthetic.

Proposed palette:
- Base: `#1e1e2e`
- Surface: `#313244`
- Overlay: `#45475a`
- Lighter accent: `#cdd6f4`
- Accent blue: `#89b4fa`
- Accent green: `#a6e3a1`
- Accent yellow: `#f9e2af`
- Accent red: `#f38ba8`

## Button Audit Findings

### F1 - Button style inconsistency [MEDIUM]
- **Evidence:** `workflow.dart` defines `commandButtonStyle` and `controlButtonStyle` as `OutlinedButton.styleFrom`【grep】
- **Impact:** Multiple pages use raw `OutlinedButton`, `TextButton`, `ElevatedButton` without shared style.
- **Fix:** Create `lib/theme.dart` with `AppTheme` defining `primaryButton`, `secondaryButton`, `dangerButton` styles using Catppuccin palette. Replace all inline styles.

### F2 - Dialog dismiss handling unsafe [MEDIUM]
- **Evidence:** `desktop_picker.dart` uses `showDialog` with `barrierDismissible: false` and `PopScope(canPop:false)` but comment notes Android back button can still pop null and `choice!` throws【read_file】
- **Impact:** Crash on back press.
- **Fix:** Use `showDialog` with `PopScope` returning null check; handle null choice gracefully.

### F3 - Preview tiles disabled without visual cue [LOW]
- **Evidence:** `desktop_picker.dart` `_tile` sets `enabled: !preview` and subtitle "Preview, not installable yet." but no icon or color change【read_file】
- **Fix:** Add `Icon(Icons.preview)` and reduce opacity for preview items.

### F4 - Icon set inconsistent [MEDIUM]
- **Evidence:** Icons in `assets/icons/intelnode.svg`, `intelnode-round.svg`, `intelnode-foreground.svg`【glob】
- **Impact:** No adaptive icon, no launcher icon variants.
- **Fix:** Generate adaptive icons for Android with Catppuccin accent background; update `flutter_launcher_icons` config.

### F5 - Terminal chrome lacks riced styling [LOW]
- **Evidence:** Terminal via `xterm` + `flutter_pty`, no custom prompt or colors.
- **Fix:** Embed Catppuccin terminal colors via `assets/scripts/start-arch.sh` `.bashrc` with PS1 using Catppuccin palette; add `xterm` color resource file.

### F6 - Window chrome not themed [LOW]
- **Evidence:** X server window via `x11_flutter`, no app chrome theming.
- **Fix:** Add Flutter overlay with blurred backdrop and Catppuccin border for X server view.

## In-App Terminals & Windows Audit

- **Terminal PTY wiring**: `pty_shell.dart` exists, `setup_terminal.dart` uses `TextButton.icon` for Copy/Copy all/Paste【grep】
- **Strength**: Terminal output mirrored to `BootLog` and logcat【README】
- **Gap**: No syntax highlighting, no scrollback limit visible.

## Tasks

1. **Create theme file**
   - Change: Add `lib/theme.dart` with Catppuccin Mocha `ColorScheme` and button styles
   - Verify: Run app, buttons use consistent colors
   - Rollback: Revert to Material3 default

2. **Fix dialog back button crash**
   - Change: Handle null return from `showDesktopPicker`
   - Verify: Back press does not crash
   - Rollback: Git revert

3. **Riced icons**
   - Change: Generate adaptive icons with Catppuccin background
   - Verify: Launcher shows new icons
   - Rollback: Restore old icons

4. **Terminal ricing**
   - Change: Add `.bashrc` with Catppuccin PS1 to `assets/scripts/`
   - Verify: New container shows colored prompt
   - Rollback: Remove bashrc injection

## Critic Pass
Clean pass? Yes — findings from grep and file reads, theme proposal grounded in repo scans.
