# Agent Report

## Summary
Audit of the previous multi-distro work found `lib/workflow.dart` did not parse (a dangling
`static String getBootCommand(...) {` spliced in above `wineCommands`), which also produced 100+
cascade errors in `lib/main.dart`. The previous report's "analyze passes" claim was false. This turn
fixed that and the defects found in the audit.

Files modified:
- `lib/workflow.dart` — removed stray line; added `D._debInstall()` helper; rewrote the Arch (`D.commands`,
  `D.commands4En`, `_commands4Pacman`) install/uninstall entries for WPS, EdrawMax, QQ, WeChat, DingTalk,
  CAJViewer; fixed dnf/zypper collections; `getCommandsForPackageManager(pm, {english})`; container init now
  derives the package manager from the distro name, persists `packageManager`, and picks the English set for
  non-`zh` locales. `D.commands`/`D.commands4En` changed `const` -> `final` (they now call the helper).
- `lib/models.dart` — added `packageManager` to `knownKeys` (it was duplicated via `additionalProps`);
  `fromJson` honours a valid stored value; mapping extracted to `ContainerInfo.packageManagerForDistro()`
  with word-boundary regexes (no more "Monarch" -> pacman by accident).
- `test/workflow_test/distro_commands_test.dart` — NEW, 13 tests (mapping, fallback, round-trip, no apt/`pacman -U`
  in Arch sets, rpm flag placement, bsdtar extraction).
- `pubspec.yaml`, `pubspec.lock` — reverted the unused `json_annotation` addition from the previous turn.
- `AGENT_REPORT.md` / `(OLD) AGENT_REPORT.md` — rotated per rules.

Design note: `pacman -U` cannot read `.deb` files. Vendor `.deb` payloads are now unpacked with
`bsdtar -xOf x.deb 'data.tar*' | sudo bsdtar -xf - -C /` (verified on synthetic xz and zstd debs). Uninstalls for
these are `rm -rf` of the install dirs because nothing is registered with the package manager.

## Feature / Task Status
- ✅ workflow.dart parses; project analyzes with 0 errors / 0 warnings (10 pre-existing infos)
- ✅ models.dart package-manager detection, persistence, round-trip — unit tested
- ✅ Arch command set: no apt, no `pacman -U`, no AppImage; WPS/Edraw/QQ/WeChat/DingTalk/CAJ via bsdtar extraction
- ✅ English pacman set used for non-zh locales at container init
- ✅ dnf/zypper flag placement and package names fixed; invalid 404 URLs (Edraw .rpm/.AppImage, WeChat png) removed
- 🔄 Uninstall paths: WeChat `/opt/wechat` + 2 desktop files VERIFIED against the real deb payload. EdrawMax,
  QQ, DingTalk paths come from the original author's own sed/postinst commands. WPS (`/opt/kingsoft/wps-office`)
  is UNVERIFIED (payload download was not completed).
- 🔄 dnf/zypper WPS/Edraw/WeChat/DingTalk use the same deb extraction (needs `bsdtar`, installed by the command);
  never run on a real Fedora/openSUSE proot.
- ❌ On-device boot test of the Arch proot flow

## What the Next Agent Should Do First
1. Run `flutter pub get && flutter analyze && flutter test` (expect 0 errors, 45 passing).
2. On the Pixel, boot the Arch container and try WeChat install/uninstall to confirm the extraction path works
   inside proot (sudo availability, `bsdtar` present in the Arch ARM rootfs).
3. Verify WPS/Edraw payload paths: `bsdtar -xOf x.deb 'data.tar*' | bsdtar -tf -`.
4. QQ's rpm key is read from the live `linuxConfig.js`; confirm it is still present when testing dnf/zypper.
5. Do NOT run `dart format lib test` repo-wide — the tree is not formatted and it rewrites unrelated files.

## Blocking Issues
None. Open risk: runtime behaviour of the new install commands inside proot is untested.

## Build / Test Status
- Build: ✅ `flutter analyze` — 0 errors, 0 warnings (project-wide). APK build not run.
- Lint:  ✅ 10 info-level hints, none new errors
- Tests: ✅ all passing (45, including 13 new)
