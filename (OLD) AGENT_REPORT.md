# Agent Report

Hand-off from Claude Code (Sonnet 5.5) to agy. Date: 2026-11-16. Repo: `DaRipper91/IntelNode`
(local checkout `~/Projects/DaRipped_tiny_computer`). Everything below was verified against live
code, device output or test runs unless it is marked UNVERIFIED.

## Summary
Audited the remote repo, then debugged IntelNode on a Nothing Phone 2a (model A142, Android 16,
Magisk-rooted) and fixed why every non-Arch "New Container" install failed. Six local commits sit on
branch `fix/new-container-wrapper-dir` (stacked on `main` @ `ca9b5a0`). **Nothing is pushed.**

Commits, oldest first:
- `dc58490` fix(shell): every PTY shell now starts with `ENV=/dev/null`. Root cause: the phone's
  Magisk module **TermuxRootMods** replaces `/system/etc/mkshrc` with `exec /system/etc/shell`, a
  Termux-built binary that dies outside Termux (`CANNOT LINK EXECUTABLE ... libssl.so.3`). Android's
  `sh` sources mkshrc for interactive shells and a PTY is always interactive, so first run died at
  "Failed to link native library directory". New `lib/pty_shell.dart` (`startShell()`) replaces the
  five raw `Pty.start("/system/bin/sh")` calls; `test/pty_shell_test.dart` fails if one returns.
- `6d15fcd` fix(installer): new `ContainerInstaller.hoistWrapperDir`. The `termux/proot-distro`
  tarballs used for Debian, Fedora, openSUSE, Alpine, Void wrap the rootfs in one top-level folder
  (`fedora-aarch64/`); `extractScript` never stripped it, so proot started at an empty root and
  first-boot provisioning failed with exit 1 for every desktop. Arch and the Ubuntu cloud image are
  flat, which is why only they worked. Confirmed on the phone (leftover staging dir held only the
  wrapper folder) and after the fix (rootfs at the staging root).
- `06433a0` fix(ui): auto-scroll progress log. **Superseded** by `d25b4b1` (widget deleted there).
- `fab6f79` fix(installer): dnf installs use `--skip-broken --setopt=install_weak_deps=False`. The
  Fedora rootfs ships `excludepkgs=*selinux*` in `/etc/dnf/dnf.conf`, so desktop groups needing
  `libselinux-utils`/`python3-libselinux` aborted the transaction ("LXDE package failed with code 1").
  Added `ContainerInstaller.sessionCheckScript`; `installDesktop` verifies the session command exists
  after a dnf install (only dnf, since only it skips packages silently).
- `d25b4b1` feat(containers): New Container now uses the first-run visible terminal screen
  (`lib/container_install_page.dart`, `SetupSession` + `SetupTerminal`, Retry/Close). New
  `ContainerInstaller.install()` = `installBase` + `installDesktop` + register, with cleanup of an
  unregistered rootfs on failure. The old hidden-shell `execute()` and its dialog were deleted.
- `b558251` feat(containers): "Delete Containers" button (Control tab > New Container panel) with a
  checkbox dialog and a confirm step. `lib/container_manager.dart` (logic) and
  `lib/container_delete_dialog.dart` (UI). Containers are identified by their position in the
  `containersInfo` pref and live in `containers/<position>`, so a delete renumbers survivors and
  renames folders. Blocked: the running container, the default container, and anything below the
  running one (renumbering would move the running folder). Added `set defaultContainer` in
  `lib/settings.dart` and 5 keys in `lib/l10n/intl_en.arb` (only English; other locales fall back).

Other branches/artifacts:
- `docs/intelnode-audit-plan` @ `dd55b09`: `docs/plans/2026-11-16-intelnode-fixes.md`, the 23-task
  fix plan from a full rip-it-apart audit of `main`. Task 23 (git history rewrite) is gated on owner
  approval; do NOT run it.
- `docs/plans/2026-11-16-intelnode-audit-log.md` is the audit evidence log. It is **untracked** in the
  working tree of the current branch; commit it onto the docs branch or delete it.
- `fix/pty-skip-mkshrc` @ `dc58490` is just an earlier tip of the same stack.
- `~/Projects/IntelNode-fix` is a stale worktree on `fix/resilient-first-run`; `stash@{0}` (autostash)
  only touches `CLAUDE.md`/`.cursorrules`. Neither is mine; leave them.

## Feature / Task Status
- ✅ ENV=/dev/null shell fix: verified on the Nothing (first run completed, base + MATE installed).
- ✅ Wrapper-folder hoist: verified on the Nothing for Fedora (extraction exit 0, provisioning exit 0).
- ✅ dnf `--skip-broken`: verified on the Nothing up to "Transaction check/test succeeded" and a full
  1064-package install; see the dracut problem below for why it never finished.
- ✅ New terminal install screen: verified on the Nothing (downloads, steps, scrolls, Copy/Paste).
- 🔄 Delete Containers: dialog and disabled state verified on screen. **Deleting a real container is
  UNVERIFIED on a device** (only Arch exists, and it is protected). Logic is covered by tests on a real
  filesystem including read-only folders.
- 🔄 Fedora desktop packages: **stopped by the user mid-task, no code changed.** See next section.
- ❌ Debian, openSUSE, Alpine, Void, Kali new-container installs: never run on a device. Kali's tarball
  layout was never checked. They share the hoist fix but each may have its own failure.
- ❌ Checksums for non-Arch distros (only Arch md5 and Ubuntu SHA256SUMS are verified); the Debian
  fallback URL in `lib/distros.dart` returns 404.

## What the Next Agent Should Do First
1. **Read the rules**: `AGENTS.md` (symlinked as `CLAUDE.md`/`GEMINI.md`), then this file. Do not push or
   open PRs without asking the owner; master is PR-protected.
2. **Fedora desktop package lists** (the task that was interrupted). Five entries in
   `lib/desktop_environments.dart` still use dnf *groups*: `xfce4` (line 78), `lxqt` (95), `mate` (112),
   `lxde` (236), `cinnamon` (308). A group pulls ~1064 packages including `kernel-core`, GPU/Wi-Fi
   firmware, VPN tools and plymouth, and its `kernel-core` scriptlet runs `dracut` for 10+ minutes under
   proot. Replace each with an explicit package list (i3/openbox/etc. already are). Verify every name
   against the real index, not memory: Fedora 40 is EOL, metadata is at
   `https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/40/Everything/aarch64/os/repodata/`
   (the `*-primary.xml.gz`, which also lists `/usr/bin/*` files so you can confirm the package that
   ships each session command: `startxfce4`, `startlxqt`, `mate-session`, `startlxde`,
   `cinnamon-session`). Keep `dbus-x11`. The desktop-manifest tests in `test/` must stay green.
   Consider whether Fedora should move off the EOL 40 image; commit `a386c7e` had used a current
   `fedora:43` simplestreams image and `1579323` reverted it to the proot-distro tarballs.
3. **Retest on the Nothing** (see device section), Fedora + XFCE and one other distro, watching the
   terminal screen. Then delete the container with the new button to cover the UNVERIFIED path.
4. Walk the other distros one at a time (Debian, openSUSE, Alpine, Void, Kali); expect per-distro
   problems. Fix the Debian fallback 404.
5. Then work `docs/plans/2026-11-16-intelnode-fixes.md` (audit plan) in risk order. Highlights:
   `Bug_Reports/FS` (about 39 MB Android bugreport data) is in public history on `main`, 3 branches and
   23 tags, with an unopened 80 MB bugreport zip; non-Arch rootfs have no integrity check; `to_vault`
   reports success on failed writes and accepts `../` topics; `MANUAL.md` claims a Rust parsing stack
   and PipeWire that do not exist (audio is PulseAudio); mic streaming and `cmatrix` have no binary.
   Also stale: README says the desktop was "never seen on screen", but MATE ran on the Nothing.
6. Update `README.md`/`AGENTS.md` for the new flows (terminal install screen, Delete Containers).

## Environment and device notes (hard-won)
- **Builds**: an hourly systemd timer writes `DIRECTORY_INDEX.md` into every directory, including
  `android/app/src/main/res/*`, which breaks Gradle's resource merger. Build from a clean detached
  worktree and delete those files first:
  `git worktree add --detach <dir> <sha>; find <dir> -name DIRECTORY_INDEX.md -delete;`
  `flutter build apk --debug --target-platform android-arm64`. Do not run `flutter test` concurrently:
  the Gradle daemon was killed once ("disappeared unexpectedly"). Judge success by `BUILD_EXIT`/the
  APK existing, never by a background-task "completed" notice (it only means the wrapper exited).
- **Signing**: local debug-signed APKs do not upgrade over CI-built ones (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
  The Nothing currently runs a locally signed build from `b558251`; use `adb install -r` with local
  builds only. Uninstalling wipes the app's containers.
- **Nothing Phone 2a**: Tailscale `nothing2a` 100.88.63.39. adb over TCP :5555 is refused; use Wireless
  debugging. Pairing is done (guid `adb-000681455001135-ZjG10R`), but the **connect port changes
  whenever Wireless debugging is toggled** (last `192.168.1.113:46759`; find it with `adb mdns services`
  or from the phone). KDE Connect shows it paired but unreachable, and `kdeconnect-cli --ping-msg`
  fails with "No such object path" for both phones. It runs Magisk with TermuxRootMods, so any code
  that starts an interactive `sh` must go through `startShell()`.
- **Pixel 10 Pro**: adb `100.83.49.113:5555`, working Arch container, older CI build.
- **Disk**: the Claude temp volume hit its quota once; remove scratch builds you no longer need.
- Do not run `pkill`/`killall` against opencode (see global `CLAUDE.md`).

## Blocking Issues
None blocking. Open risks: delete-container path untested on a real second container; Fedora 40 is EOL
and its repos could change; one full-suite test failure occurred once under heavy load and could not be
reproduced in 3 clean reruns (which test is unknown).

## Build / Test Status
- Build: ✅ `flutter build apk --debug --target-platform android-arm64` succeeded from a clean worktree at `b558251`.
- Lint:  ✅ `flutter analyze --no-fatal-infos` reports 18 info-level items, the same baseline as `main`.
- Tests: ✅ `flutter test` 200/200 passed on `b558251` (baseline on `main` was 181).
