# Hand-off to agy: IntelNode new-container work

From: Claude Code (Sonnet 5.5) · Date: 2026-11-16 · Repo: `~/Projects/DaRipped_tiny_computer`
(GitHub `DaRipper91/IntelNode`) · Branch to continue on: `fix/new-container-wrapper-dir` (7 commits
ahead of `main`, **nothing pushed**).

Full detail is in `AGENT_REPORT.md` (read it first, it is short). This brief is the task order,
acceptance criteria and guardrails.

## Where things stand (30 seconds)
IntelNode runs Arch Linux ARM in proot on Android (Flutter). "New Container" installs other distros.
Every non-Arch install used to fail. Three root causes were found and fixed on the Nothing Phone 2a:
1. A Magisk module on that phone hijacks interactive shells (`mkshrc`): fixed by `ENV=/dev/null`.
2. proot-distro tarballs wrap the rootfs in one folder: fixed by hoisting it after extraction.
3. Fedora's `excludepkgs=*selinux*` broke dnf desktop *groups*: fixed with `--skip-broken` plus a
   session-command check.
Also added: a first-run-style terminal install screen, and a Delete Containers button. Tests: 200/200,
analyzer at the 18-info baseline. Fedora + XFCE got through download and a full package install on the
phone, then sat on `dracut` (kernel initramfs) for 10+ minutes before the owner stopped it.

## Your first task: replace the five dnf desktop groups with explicit package lists
`lib/desktop_environments.dart`, dnf entries for `xfce4` (line 78), `lxqt` (95), `mate` (112),
`lxde` (236), `cinnamon` (308). Each is currently `@<name>-desktop-environment` + `dbus-x11`.
That group installs about 1064 packages (kernel, GPU/Wi-Fi firmware, VPN, plymouth) that a proot
container cannot use. i3, openbox, fluxbox, icewm, awesome, bspwm and enlightenment already use explicit
lists; match their style.

Steps:
1. Fetch the Fedora 40 aarch64 package index and use it as the source of truth:
   `https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/40/Everything/aarch64/os/repodata/`
   (the file ending `-primary.xml.gz`). Fedora 40 is end of life, so the plain mirrors no longer serve it.
2. For each desktop, choose the minimum that gives a usable session: session manager, window manager,
   panel, settings, terminal, file manager, and a font/icon theme. Confirm every package name exists in
   the index, and that the package providing the session command is in your list:
   `startxfce4`, `startlxqt`, `mate-session`, `startlxde`, `cinnamon-session` (the primary index lists
   `/usr/bin/*` files). LXQt and LXDE need a window manager, so include `openbox`.
3. Add a guard test so groups cannot come back: no `PackageManagerFamily.dnf` entry may start with `@`.
   Keep the existing desktop-manifest tests green.
4. Do not weaken `sessionCheckScript`; it is what stops `--skip-broken` from faking a successful install.

## Acceptance criteria
- `flutter test` passes (200 today, plus yours) and `flutter analyze --no-fatal-infos` stays at 18 infos.
- On the Nothing Phone 2a, New Container with **Fedora + XFCE4** completes (terminal screen reaches
  "ready"), no `kernel-core`/`dracut` in the log, and the whole install is clearly smaller and faster than
  1064 packages. Then repeat for at least one other desktop from the five.
- The new container appears in the app, and **Delete Containers removes it** (this deletion path has
  never been run on a real device).
- Report the result honestly in `AGENT_REPORT.md`; do not mark a desktop done unless it started on the phone.

## After that
Debian, openSUSE, Alpine, Void and Kali installs have never been run on a device; expect per-distro
failures. Kali's tarball layout was never checked, and the Debian fallback URL in `lib/distros.dart`
returns 404. Non-Arch downloads have no checksum. Then work `docs/plans/2026-11-16-intelnode-fixes.md`
(23-task audit plan, on branch `docs/intelnode-audit-plan`) in risk order.

## Guardrails
- **Do not push, open PRs, or force-push** without the owner's explicit say-so. Task 23 of the audit plan
  (rewriting git history to remove a 3 GB pack) needs the owner's approval; do not start it.
- **Do not touch the phone's `/system`, Magisk modules or `TermuxRootMods`.** The fix lives in the app.
- **Do not delete the Arch container** (it is the only one, and the running default). Uninstalling the app
  wipes it, and local debug builds will not upgrade over CI-signed ones (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
- **Build from a clean detached worktree**, with `DIRECTORY_INDEX.md` files deleted first (an hourly timer
  puts them in `android/.../res/` and Gradle rejects them). Do not run `flutter test` while Gradle builds.
  Judge a build by the APK existing, not by a "completed" notification.
- Never `pkill`/`killall` opencode. Use `pacman`/`yay`, never `apt`/`dnf` on the host.
- Write all code and comments in English; use absolute `package:da_ripped_tiny_computer/...` imports; read
  settings through `Util.getGlobal` or `G.settings`. Keep diffs minimal: do not run `dart format` over whole
  files (it reflowed unrelated lines once and had to be reverted).
- End your turn by updating `AGENT_REPORT.md` (rotate the old one to `(OLD) AGENT_REPORT.md`).

## Reaching the phones
- Install a local build with `adb -s <serial> install -r <apk>`. App id `com.daripper91.daripped`.

## Paste this to start agy
> Read `~/Projects/DaRipped_tiny_computer/docs/HANDOFF-agy-2026-11-16.md` and `AGENT_REPORT.md`, then do
> the first task: replace the five dnf desktop groups in `lib/desktop_environments.dart` with explicit,
> index-verified Fedora 40 package lists, add the no-groups guard test, and verify on the Nothing Phone 2a.
> Work on branch `fix/new-container-wrapper-dir`. Do not push.
