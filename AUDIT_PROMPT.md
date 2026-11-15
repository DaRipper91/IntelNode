# Audit Prompt: IntelNode Multi-Distro Support

## Overview
This prompt instructs the next agent to audit the Arch Linux and multi-distro support implementation for the IntelNode project. The previous agent implemented changes to support Arch Linux and other Linux distros instead of only Debian.

## Files to Audit
- `lib/models.dart` - PackageManager field and distro detection
- `lib/workflow.dart` - Distro-aware command generation
- `AGENT_REPORT.md` - Report of changes
- `AGENTS.md` - Universal agent ruleset

## Audit Checklist

### 1. Verify models.dart Changes
- [ ] `packageManager` field exists in `ContainerInfo` class
- [ ] `packageManager` defaults to `'pacman'`
- [ ] `fromJson()` maps distro names to package managers correctly:
  - Arch/Arch Linux → pacman
  - Fedora → dnf
  - OpenSUSE/Tumbleweed/Leap → zypper
  - Ubuntu/Debian/Trixie → apt
  - Default (no name field) → pacman
- [ ] `hasProp()`, `getProp()`, `setProp()`, and `toJson()` support `packageManager`
- [ ] No new analyze errors introduced (only pre-existing main.dart errors allowed)

### 2. Verify workflow.dart Changes
- [ ] `getCommandsForPackageManager(String packageManager)` method exists
- [ ] Four command collections present:
  - `_commands4Pacman` - Arch Linux commands (all use pacman, EdrawMax uses AppImage)
  - `_commandsForApt` - Debian/Ubuntu commands
  - `_commandsForDnf` - Fedora commands
  - `_commandsForZypper` - OpenSUSE commands
- [ ] WPS install command: `sudo pacman -S --noconfirm wps-office` (no .deb)
- [ ] EdrawMax install command: AppImage instead of .deb
- [ ] Default boot command: `pacman -Syu --noconfirm` (not apt)
- [ ] Container initialization uses distro-aware commands
- [ ] No apt/apt-get commands remain outside `_commandsForApt` constant

### 3. Verify AGENT_REPORT.md
- [ ] Present in project root
- [ ] Follows required format (Summary, Feature/Task Status, What Next Agent Should Do First, Blocking Issues, Build/Test Status)
- [ ] Accurately reflects all changes made
- [ ] No mention of incomplete work as complete

### 4. Verify Pre-existing Conditions
- [ ] 7 `undefined_getter` errors in `main.dart` remain unchanged (these are pre-existing and unrelated)
- [ ] No new errors introduced in `lib/models.dart` or `lib/workflow.dart`
- [ ] Build passes with `dart analyze` for modified files only

## What the Next Agent Should Do First

1. Run `dart analyze lib/models.dart lib/workflow.dart` and verify no new errors
2. Verify all package manager mappings are correct in models.dart
3. Verify all command collections are present and correct in workflow.dart
4. Verify no apt/apt-get commands remain outside the APT constant
5. Verify AGENT_REPORT.md format and accuracy
6. Test the proot boot flow with Arch Linux specifically (if environment allows)
7. Ensure container data persists correctly with new distro-aware commands

## Blocking Issues
- Pre-existing 7 `undefined_getter` errors in `main.dart` are unrelated to these changes
- WPS and EdrawMax may need additional ARM64 package alternatives (not critical for core functionality)
- Full testing not yet completed (environment-dependent)

## Build / Test Status
- Build: `dart analyze` passes for `lib/models.dart` and `lib/workflow.dart` 
  (only pre-existing main.dart errors)
- Lint: Pre-existing issues in main.dart only
- Tests: Not yet run for new functionality (environment-dependent)

## Audit Notes
- Changes integrate new distro support into existing architecture without rewriting
- All modifications follow existing naming conventions and file organization
- Pre-existing errors in main.dart are preserved and not attributable to this work
- Implementation is modular and extensible for future distro additions