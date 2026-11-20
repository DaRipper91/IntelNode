# Rip-It-Apart Audit — IntelNode — 2026-11-20

## Summary
The tree is in reasonable shape. The rootfs download path is fail-closed, and path confinement and shell quoting are sound. No Critical or High item survived the critic pass: nothing demonstrated is remotely exploitable, and the most serious proven items are Medium. There are 11 Medium and 18 Low tasks in the main list, plus 4 back-burner tasks (3 Low, 1 Medium sub-item), for 33 in total. The most severe finding is M-5 (the unauthenticated PulseAudio TCP listener); M-3 (Alpine LXDE, Cinnamon and Enlightenment cannot install) is the most visible functional break.

**Environment limits (read before acting).**
- No APK was built and nothing ran on a device. No Android SDK was available, so Kotlin, Java and Gradle compile, proot, X11 and `apk add` behavior are unexercised.
- Stage 2 ran Flutter 3.41.6 on an earlier tree: `flutter test` passed 297, and `flutter analyze` reported 10 info-level issues with no warnings or errors. HEAD (`ef0621f`) has since merged #37-#39 (a Kotlin brace fix, a PR build workflow and a gradle.properties change). Those results were not re-run on HEAD.
- Line numbers were re-grepped on the working tree at HEAD `ef0621f`. Some stage citations were a few lines off and are corrected below.

**Evidence tags used per task.**
- `[executed]` means a test, probe, harness, byte inspection or index parse was actually run.
- `[read]` means confirmed only by reading code or config.
- `[reasoned]` means inferred from code and platform behavior and not exercised. Treat these as hypotheses to check before editing.

**Priority-scope index** (Arch, Debian, Fedora, Alpine, Void; XFCE4, LXQt, MATE, LXDE, Cinnamon, Enlightenment). These tasks come first in each severity section where they apply:
- M-3 (Alpine LXDE, Cinnamon, Enlightenment), M-7 (XDG variables for MATE and Cinnamon), M-8 (sudo on Debian and Void), L-2 and L-3 (Arch rootfs integrity and availability), L-4 (checksum tests).
- Back-burner items (Ubuntu, openSUSE, Kali, window managers) are in their own section near the end and are not ranked against these.

## Critical
None. The critic pass found no demonstrated, exploitable Critical-class defect.

## High
None. Stage 3's three Highs (B-1, B-2, B-3) were re-rated Medium by the critic. Each is either conditional on operator error, or inferred and unexercised, or a functional rather than security break.

## Medium

### M-1 Silent default fallback masks container-record corruption (B-9) [read]
- **Files:** `lib/workflow.dart:338-340` (`getCurrentProp` catch returns `_getDefaultProp`; the default `boot` is the Arch command and `name` is "Arch Linux", at ~343+); `lib/desktop_environments.dart:373-374` (`byId` falls back to `all.first`, i.e. XFCE4, via `orElse`).
- **Problem:** `getCurrentProp` swallows every exception (bad index, corrupt JSON). A corrupt record on an Alpine or Void container then boots with the Arch command, with no error. An unknown desktop id silently becomes XFCE4.
- **Why it matters:** this is the foundation for the other state fixes (M-2, L-1). Wrong-distro boots look like unrelated bugs.
- **Fix direction:** catch only the specific expected exceptions. Log through `BootLog`, and surface an error state for the container instead of returning Arch defaults. Make `byId` return null or throw, and have callers handle an unknown id. Keep `getCurrentProp` side-effect free (see L-1).

### M-2 Stale `containersInfo` snapshot loses concurrent updates (B-12) [read]
- **Files:** `lib/container_installer.dart:122-125` (snapshot `existing`, `containerIndex = existing.length`), `:148` and `:730-735` (`[...existing, new]` written after a multi-minute install), `:229` (`finalizeScript` `rmrf` of the container dir). `lib/container_install_page.dart:43` (no re-entrancy guard seen). The critic's severity label was Medium-Low.
- **Problem:** anything that changes `containersInfo` during an install (a delete, the `getCurrentProp` migration write, a second install) is overwritten. Two concurrent installs pick the same index, and one `rmrf`s the other's directory.
- **Fix direction:** re-read `containersInfo` immediately before the write. Allocate the index under a lock, or recompute it at registration time. Disable the install action while one is running.

### M-3 Alpine LXDE, Cinnamon and Enlightenment cannot install but are offered as stable (B-3) [executed index parse; `apk add` not run]
- **Files:**
  - `lib/desktop_environments.dart:279` (`lxde-core`), `:333` (`enlightenment`, `terminology`) and `:361` (`cinnamon`), all `PackageManagerFamily.apk`.
  - Tiers are `DesktopTier.stable` (`:261`, `:325`, `:343`).
  - `lib/desktop_picker.dart:55` (`enabled: !preview` filters only by tier, not by distro).
  - `lib/container_installer.dart:531-533` (generic "install failed (exit code N)").
- **Problem:** stage 2 parsed the Alpine 3.21 and 3.22 main and community APKINDEX files. `lxde-core`, `cinnamon`, `enlightenment` and `terminology` are absent. `apk add` is atomic, so each install fails. The picker still offers them, and the error does not name the missing package. That is 3 of 6 priority desktops on a priority distro.
- **Fix direction:**
  - Use the existing `packagesByDistroId` override (`desktop_environments.dart:34-37`). Give LXDE real Alpine names (`lxsession lxterminal pcmanfm openbox` plus `dbus-x11`).
  - Add an "unsupported on this distro" marker, for Alpine Cinnamon and Enlightenment, that `desktop_picker.dart` honors by hiding or disabling the tile.
  - Include the stderr tail or package name in the install failure message.
  - Device-test each remaining Alpine desktop. Only XFCE4 was device-run on Alpine and Void.
  - Note Alpine `edge` carries `cinnamon` and `terminology` only in `testing`, which is not a safe substitute.
- **Preserve:** the config-driven manifest design (S-6).

### M-4 Startup retry re-runs the whole bootstrap and duplicates long-lived resources (B-6) [read; consequences reasoned]
- **Files:** `lib/main.dart:2446-2461` (`G.retryStartup = _initializeWorkflow`; the retry button is at `:1888`). `lib/workflow.dart:1643` (`G.termPtys = {}`), `:1701` (`Workflow.launchXServer()` un-awaited), `:1737` (`setupAudio` kills only `G.audioPty`), `:1815-1824` (virgl server started again, no kill of the earlier one), and `:1995-1996` (`initData` runs again).
- **Problem:**
  - The trigger is the 60 s `waitForXServer` TimeoutException (`:438-460`).
  - Retry orphans the running proot PTYs. It starts a second `CmdEntryPoint.main`, a possible second pulseaudio and a second virgl server.
  - `launchXServer()` is un-awaited, so a failure there is an unhandled async error.
- **Not verified:** whether the second X server really double-binds, or whether pulseaudio survives the PTY kill.
- **Fix direction:** split retry into "resume" and "full init". Guard `launchXServer`, `setupAudio` and virgl start with an "already running" check, or tear down the existing instance first. Await `launchXServer` and route its error into the startup-failed state. Kill the pulseaudio and virgl child processes, not just the shell.

### M-5 PulseAudio accepts anonymous TCP connections on all interfaces (B-1, critic-rated Medium) [executed byte inspection; reachability reasoned]
- **Files:** `assets/assets.zip` entry `bin/pulseaudio.conf:65` (`load-module module-native-protocol-tcp auth-anonymous=true port=4713`, with no `listen=` and no `auth-ip-acl`). `lib/workflow.dart:1744-1747` (the sed of 4713 to the audio port, default 4718, and the pulseaudio start). The guest connects via `PULSE_SERVER=tcp:127.0.0.1:4718` (`workflow.dart:1383`, `assets/scripts/start-desktop:6`).
- **Problem:** the module binds all interfaces by default. A peer on the same Wi-Fi or hotspot, or any local app, can connect without credentials and play audio or load modules.
- **Not supported by evidence:** the stage 3 claim that a peer can read mic sources via `module-opensles` and RECORD_AUDIO. The conf only shows the module loaded (`:118`, `:121`). That impact is inference and is excluded.
- **Fix direction:** add `listen=127.0.0.1` and `auth-ip-acl=127.0.0.1` to the module line. The loopback client does not need to change. The conf lives inside `assets.zip`, so repack the archive. Add a test that unpacks the zip and asserts those parameters. See L-9 for the residual loopback exposure.

### M-6 Release workflow publishes a debug-signed APK when signing secrets are missing (B-2, critic-rated Medium) [read]
- **Files:** `.github/workflows/release.yml:54-56` (warns, then `exit 0` when `KEYSTORE_BASE64` is empty), `:74-79` (`draft: false`, `prerelease: false`). `.github/workflows/flutter-build.yml:54-56` and `:101-102` (`prerelease: true`, `make_latest: true`). `android/app/build.gradle:79` and `:86` (fall back to `signingConfigs.debug`).
- **Problem:** on a `v*` tag push with no secrets (an operator error), a public non-draft release is published signed with a throwaway debug key. The claim that the signer differs per runner is plausible but not shown in the repo, so treat it as inference.
- **Out of scope:** a local `flutter build apk --release` falling back to the debug key is normal Android practice and is not a defect.
- **Fix direction:** in `release.yml`, replace `exit 0` with `exit 1` when the ref is a tag. Optionally publish as draft or prerelease when unsigned. Keep the warn-and-continue behavior in `flutter-build.yml` for PR and dev builds.

### M-7 `XDG_CURRENT_DESKTOP` and `XDG_SESSION_TYPE` are set only in `.xinitrc`, not on the real launch path (B-5) [reasoned; not run on device]
- **Files:** `lib/container_installer.dart:665-667` (exports in `.xinitrc`). `assets/scripts/start-desktop:542` (`exec dbus-launch --exit-with-session "$DE_EXEC"`, with no `XDG_` export; grep finds none). `DesktopEnvironmentSpec.xdgDesktopName` is unused at runtime.
- **Problem:** MATE (`mate-session`) and Cinnamon (`cinnamon-session`) rely on `XDG_CURRENT_DESKTOP` for OnlyShowIn autostarts and menus. LXQt and LXDE wrappers set their own.
- **Fix direction:** export `XDG_CURRENT_DESKTOP` and `XDG_SESSION_TYPE` in `start-desktop` before `exec dbus-launch`, from the same spec value written into the session file. Verify on device for MATE and Cinnamon first.

### M-8 sudo is assumed on Debian and Void, but the installer skips verifying it (B-11) [reasoned]
- **Files:** `lib/container_installer.dart:416-418` (`sudoCheck` skipped for `debian`, `opensuse` and `void`). `lib/distros.dart:277-278` (sudoers drop-in written regardless; the Debian and Void first-boot scripts install no sudo, per stage 3). `assets/scripts/start-arch.sh:22` (falls through to unprivileged `dbus-daemon --system`, which prints only a warning).
- **Problem:** if `sudo` is absent on these images, the sudoers and polkit config is dead and the system bus may not start. Cinnamon, MATE and LXQt depend on the system bus. The openSUSE part of this is in the back-burner section.
- **Fix direction:** check for `sudo` in the Debian and Void first-boot scripts, and install it if missing or assert it. Then remove those distros from the skip set, or replace the check with a distro-appropriate one. Make `start-arch.sh` report clearly when the system bus fails to start. A Void comment in `distros.dart` says an earlier xbps note was refuted on one phone only, so device-verify.

### M-9 Shipped assets do not match what the launcher references (B-8) [executed: `tar tzf` and zip extraction, run by stage 3 and the critic; proot behavior untested]
- **Files:**
  - `lib/workflow.dart:1799-1800` (`getifaddrs_bridge_client_lib.so`), `:1845` (`tiny/font` mount), `:1848` (`tiny/extra/cmatrix`) and `:1849` (`tiny/extra/tiny_virtual_mic`).
  - `lib/main.dart:1052` and `:1064` (`bash ~/.local/share/tiny/extra/install-hangover{,-stable}`), `:1154` and `:1196` (`tiny/extra/chn_fonts.reg`), `:1173-1174` (`tiny_virtual_mic`).
  - `assets/patch.tar.gz`.
- **Problem:**
  - `patch.tar.gz` ships `tiny/{build-arch-rootfs.*, cross/{chn_fonts.reg, install-hangover, install-hangover-stable}, getifaddrs_bridge/*, tiny_virtual_mic.c, turnip.patch, start-arch.sh, start-desktop, to_vault}`. `assets.zip` extracts to `bin/` only.
  - `tiny/extra/{tiny_virtual_mic, cmatrix}`, the bridge client lib and `tiny/font` are never produced. The Hangover and font scripts exist under `tiny/cross/`, not the `tiny/extra/` paths used.
  - The "virtual mic" toggle therefore starts native recording for a binary that does not exist. The Hangover buttons run `bash` on missing files. The bridge lib is silently never enabled (guarded by `bridgeLibPresent`).
  - The patch also carries stale copies of `start-desktop`, `start-arch.sh` and `to_vault` that differ from `assets/scripts/`.
- **Citation corrections from the critic:** `tiny/font` appears only at `workflow.dart:1845`, not in `main.dart:1051-1063`. The cmatrix mount is `workflow.dart:1848`.
- **Fix direction:** for each feature, either ship the missing artifact, fix the path to `tiny/cross/`, or hide the UI and remove the mount. Drop the stale script copies from `patch.tar.gz`. Test how proot treats a missing `--mount` source before deciding if the mounts are harmful.

### M-10 Android service and audio lifetime issues (B-7) [(a) read; (b) and (c) reasoned]
- **Files:**
  - (a) `android/app/src/main/kotlin/com/daripper91/daripped/ContainerSessionService.kt:34` (`START_STICKY`), `:38` and `:65-71` (`acquireWakeLock`, no timeout).
  - (b) `android/app/src/main/cpp/native-socket.cpp:68` (`accept` blocking) and `:100-103` (`nativeClose` only `close()`s the fds). `AudioStream.kt:34-35`.
  - (c) `native-socket.cpp:89` (`write` return not checked for short writes).
- **Problems:**
  - (a) After the process dies, Android restarts the service with a null intent. It re-posts the foreground notification and re-takes the wake lock with no container running. Only the Stop action ends it.
  - (b) `close()` from another thread does not reliably wake a blocked `accept()`. If the guest never connects, `startStreaming` returns false ("STREAMING_UNAVAILABLE") until the process dies.
  - (c) Short writes silently drop samples.
- **Fix direction:**
  - (a) Use `START_NOT_STICKY`, or detect a null-intent restart and `stopSelf()`. Add a wake-lock timeout or a release on stop.
  - (b) Call `shutdown(fd, SHUT_RDWR)` before `close()`, or poll with a timeout.
  - (c) Loop on `write` until all bytes are sent.

### M-11 `start-desktop` overwrites user configuration on every launch (B-10) [read]
- **Files:** `assets/scripts/start-desktop:272-282` (`~/.config/gtk-3.0/settings.ini`, `~/.gtkrc-2.0`), `:288`, `:310` and `:335` (`xfce4-power-manager.xml`, `xfce4-screensaver.xml` and `xfce4-session.xml`, each written with `cat >`), `:109-110` (`sudo -n ln -sf /bin/true /usr/local/bin/xflock4` and `/usr/bin/xflock4`).
- **Problem:** these files are replaced on every start. `xfce4-session.xml` replaces the whole channel and drops any other `general` properties. `/usr/bin/xflock4` is a package-owned file and gets clobbered each launch, so the package manager will report or revert it on upgrade. Openbox is the same class of problem and is covered in the back-burner section.
- **Fix direction:** write each file only if it is missing, or merge keys, or keep a versioned marker. Prefer an `xdg` override or the `/usr/local/bin` shim over replacing `/usr/bin/xflock4`.

## Low

### L-1 Legacy VNC password migration is wrong, and the dead credential still leaks via clipboard (B-4; critic: Low/Medium, not a security finding) [read]
- **Files:** `lib/workflow.dart:299-302` (precedence bug), `:305` (write-side effect inside the `getCurrentProp` getter), `:311` and `:320` (the `12345678` replace literals), `:1621-1622` (`vncUrl` with `password=$initialVncPassword`). `lib/models.dart:184-190` (`hasProp('vncPassword')` is hard-coded `true`). `lib/main.dart:381-386` (the clipboard copy) and `:736` (a `sed` on `startvnc`, which does not exist).
- **Problem:** `a && !hasProp || (hasProp && empty)` has the wrong grouping, and the first clause is dead. The migration only fires for empty passwords, and `fromJson` maps a missing value to `''`, so most records are still migrated. No tree code ever writes `12345678`, so practical impact is low. `getCurrentProp` performs unawaited read-modify-write of `containersInfo`, which races (see M-2). No VNC server is started anywhere, so the password and the "share link" are dead credentials that are still copied to the system clipboard.
- **Fix direction:** if VNC is truly dead, remove `vncUrl`, `vncUri`, `vncPassword`, the clipboard action and the `startvnc` `sed`, with a one-time migration that strips the field. If it is kept, fix the grouping and move migration out of the getter into an explicit awaited step.

### L-2 Arch rootfs integrity is MD5 from the mirror itself, with no signature check (stage 2 residual 1) [executed live check]
- **Files:** `lib/distros.dart:442-445` (`ChecksumKind.md5Sidecar`, "Detects corruption, not tampering"). `lib/container_installer.dart:249-260`.
- **Problem:** the pipeline is fail-closed but this is not a trust anchor. A compromised mirror serves both file and hash. The ArchLinuxARM `.sig` is not checked.
- **Fix direction:** verify the detached GPG signature against a pinned ALARM Build System key fingerprint, or pin a sha256 per release. Do not reintroduce a skip mode. Do not describe the Arch rootfs as "verified" in docs or UI until this lands.

### L-3 Arch checksum sidecar is always fetched from the first mirror, and the failure message is raw (stage 2 residual 2) [executed probe]
- **Files:** `lib/container_installer.dart:249-258`, `:286-311`.
- **Problem:** `pickReachable` falls back to `ca.us` when `fl.us` is down, but the `.md5` is still fetched from `fl.us` and throws a raw `Exception: timeout`. This is fail-closed, but the fallback mirror is useless and the message is poor.
- **Fix direction:** keep the sidecar origin rule. Wrap the failure in a clear message ("checksum mirror unreachable"). Optionally try the sidecar from each listed origin in order, but never from the host that serves the tarball alone.

### L-4 No permanent tests for sidecar failure paths (stage 2 residual 3) [executed probes]
- **File:** `test/rootfs_verify_test.dart`.
- **Fix direction:** add three tests driving `ContainerInstaller.installBase` with a mock HTTP client: a sidecar 404, an HTML body, and a first-mirror timeout. Each asserts a throw and that the tarball URL was never requested. Do not weaken the existing tests.

### L-5 `AGENT_REPORT.md` carries stale or false claims [executed: `git cat-file -t 407cf4d` is invalid; test and analyze counts from stage 2]
- **File:** `AGENT_REPORT.md:20`. It says commit `407cf4d` skips the checksum when the mirror check fails. That commit does not exist, and HEAD is fail-closed. Lines 10 and 38 say 209 tests and 18 infos, against 297 and 10 measured.
- **Fix direction:** correct the checksum line (the historical hole was fail-open for all non-sidecar URLs before `b5e32c0`, now closed) and refresh the baseline numbers after re-running the suite on HEAD.

### L-6 Dead code `Util.rootfsExtractCommand` (workflow.dart:221) [executed grep]
- **Files:** `lib/workflow.dart:221` (unescaped `$stagingDir`, verbose `tar x`), `test/workflow_test/rootfs_extract_command_test.dart`.
- **Problem:** no caller exists in `lib/`. It is stale from the bundled split-archive era, and it carries an unescaped interpolation that someone could reuse.
- **Fix direction:** delete the function and its test. Do not touch the live extraction in `container_installer.dart` (see S-5).

### L-7 TinyDocumentsProvider minor defects (stage 2 findings a-d) [executed harness for the guard; the Android build was not run]
- **File:** `android/app/src/main/java/com/daripper91/daripped/TinyDocumentsProvider.java`.
  - `:196`: `file.getName().toLowerCase().contains(query)` never lowercases `query`, and a null query would NPE.
  - `:65-70` (`queryRoot`): uses non-canonical `getFilesDir()` for the root id, which is harmless because `resolve` canonicalises.
  - `createDocument` (~`:123-147`): there is a check-then-create race between `exists()` and `createNewFile()` (single process, local).
  - `:1`: package `com.daripper91.daripped.filepicker` but the file sits in `.../daripped/`.
- **Fix direction:** lowercase and null-check `query`, make creation atomic (`createNewFile()` returning false means "exists"), and align the package with the directory only if the manifest and tests are updated together. Do not change `DocumentPathGuard` (S-3).

### L-8 IME loopback socket 127.0.0.1:4720 has no peer authentication, and trickle clients can hold slots (B-13) [read]
- **File:** `android/app/src/main/kotlin/com/daripper91/daripped/X11KeyboardReceiver.kt:39` (`PORT`), `:45` (`MAX_CONCURRENT_CLIENTS = 4`), `:57-58` and `:82` (`serverRunning`), `:104-114` (per-read `soTimeout`).
- **Problem:** any local app with INTERNET can send show, hide or toggle. A client sending one byte per under 2 s holds a slot for about 2 minutes, and four of them block the IME. If bind fails, nothing retries until another broadcast arrives. Impact is nuisance-level.
- **Fix direction:** use a `LocalServerSocket` with a `peerCredentials.uid == Process.myUid()` check (the guest shares the app uid, so it still works). Add an overall per-connection deadline. Retry the bind with backoff.

### L-9 PulseAudio loopback TCP is also unauthenticated for local apps (C-1, critic-added) [reasoned]
- **Files:** `assets/assets.zip:bin/pulseaudio.conf:65` (TCP), `:59` (the unix-socket module is already loaded), `lib/workflow.dart:1383` and `assets/scripts/start-desktop:6`.
- **Problem:** after the M-5 fix, any local app can still reach 127.0.0.1:4718.
- **Fix direction:** have the guest use a unix socket under the app's private dir (via `PULSE_SERVER=unix:...` and a bind mount) and drop TCP entirely.

### L-10 In-guest string injection in `intelnode-ime` and `to_vault` (B-14) [read]
- **Files:** `assets/scripts/start-desktop:119` (`/bin/bash -c "printf '%s\n' '$ACTION' > /dev/tcp/127.0.0.1/4720"`), `assets/scripts/to_vault:17-19` (unsanitised `$TOPIC` in the output path, so `../../x` escapes `Raw_Intel`).
- **Problem:** same-user only; no privilege boundary is crossed. It is hygiene.
- **Fix direction:** validate `$ACTION` against `show|hide|toggle` and pass it without a `-c` string. Sanitise `TOPIC` to `[A-Za-z0-9._-]` with no leading dot.

### L-11 Swallowed errors in the Android and Dart foreground-service paths (B-15) [read]
- **Files:** `android/app/src/main/kotlin/com/daripper91/daripped/MainApplication.kt:74`, `:88`, `:102` and `:110` (empty `catch (_: Throwable) {}`). `lib/workflow.dart:1944-1954` (`startContainerForegroundService` and `stopContainerForegroundService` use `catch (_) {}`). `ContainerSessionService` logs only.
- **Problem:** a refused foreground-service start (Android 14+ `ForegroundServiceStartNotAllowed`) leaves the process without its cgroup-freeze protection and no user signal.
- **Fix direction:** log each catch with context. Surface a one-time user notice through `BootLog` and the existing toast mechanism when the foreground service fails to start.

### L-12 A cancelled desktop pick on first run orphans an installed base (B-16) [re-download read; downstream launch reasoned]
- **Files:** `lib/workflow.dart:1586-1594` (returns on `desktop == null`), `lib/container_installer.dart:229-231` (`finalizeScript` deletes that rootfs and tarball on the next run), `assets/scripts/start-desktop:535-536` ("No supported desktop environment").
- **Problem:** the base is fully installed but unregistered, so the next launch redownloads it. The caller then continues into container launch with no session file.
- **Fix direction:** register the base container before the picker, or keep the base and resume at the picker on the next launch. Make the cancelled path exit the launch flow cleanly.

### L-13 Latent shell interpolation of `username` and package lists (stage 2 and stage 3 checklist; not currently exploitable) [read]
- **Files:** `lib/container_installer.dart:55` (`static const String username = "tiny"`). `lib/distros.dart:252-296` (unquoted `$username` in the first-boot and common user setup, including `/etc/sudoers.d/$username` at `:277-278`), `:211-235` (`packages.join(' ')` in install and remove commands).
- **Problem:** no user input reaches either today. If `username` ever becomes configurable, or if package names ever come from user input, this becomes injection.
- **Fix direction:** if made configurable, validate against `^[a-z_][a-z0-9_-]{0,31}$` at the boundary, and quote with `Util.escapeShellArgument` (`workflow.dart:195`). Do not add a second quoting scheme (S-4). Add a comment on the constant that it must not be user-supplied.

### L-14 Audio port is user-editable with no validation (C-4, critic-added) [read]
- **Files:** `lib/main.dart:468-478`, `lib/settings.dart:19` (default 4718), `lib/workflow.dart:1744` (the value is sed'ed into the conf).
- **Fix direction:** validate an integer in 1024-65535 and reject conflicts with 4720 and 4713. Persist only valid values.

### L-15 Build and CI hygiene (B-17, scoped to items still valid at HEAD) [read]
- **`android/app/build.gradle:58`:** `"git rev-parse HEAD\n".execute()` throws if the `git` binary is missing. The `?:` fallback only covers empty output. Wrap it in try/catch and fall back to `CURRENT_COMMIT`.
- **`android/gradle.properties:2`:** `org.gradle.jvmargs=-Xmx16384m` is still present at HEAD (commit `ef0621f` removed only the aapt2 path). It can OOM-kill the daemon on small runners [reasoned]. Lower it or make it overridable.
- **`pubspec.yaml:34` and `:58`:** `intl: any` and `flutter_lints: any` are unpinned, while CI pins Flutter 3.41.6. The deprecated `Radio` usages (`lib/container_setup_page.dart:67`, `:68`, `:91`, `:92`, `:115`, `:116`) are the visible drift. Pin to the lockfile versions and migrate to `RadioGroup`.
- **`.github/workflows/release.yml:25` and `:75`, `flutter-build.yml:25` and `:85`:** `subosito/flutter-action@v2` and `softprops/action-gh-release@v2` are pinned by mutable tag in jobs that hold signing secrets and `contents: write`. Pin to commit SHAs.
- **`flutter-build.yml:87`:** the reused `latest-build` tag may not move, so the "latest" release can point at a stale commit [reasoned].
- **`assets/scripts/start-arch.sh:10-11`:** guest DNS falls back to 1.1.1.1 and 8.8.8.8, bypassing the user's Private DNS or VPN resolver (privacy, not integrity) [read]. Consider documenting it or making it a setting.
- **Dropped:** the `crash_summary.py` UTF-8 decode item. The file does not exist in the repo, so the item is unverifiable.

### L-16 Documentation drift that misleads implementers [read]
- **Files:** `CLAUDE.md` (names 4 lib files and one distro; `lib/` has about 20 files and 7 distros). `lib/workflow.dart:58-59` (relative imports of `models.dart` and `settings.dart`, against the absolute-import convention). `lib/workflow.dart:1` (`part of tiny_computer` header). `.audit` outputs should not be committed.
- **Fix direction:** touch `CLAUDE.md` only with the owner's go-ahead (it is a protected file). Convert the two relative imports to `package:da_ripped_tiny_computer/...`.

### L-17 Root-level and stale clutter [executed `ls`]
- **Files:** `Screenshot_20261117-*.png` (5 files, ~1.5 MB, repo root), `archive/README-1.0.1.md`, `debug/`, `extra/` (build and test scripts not wired into the app), `.gitignore` entries for `extra/archroot-build/` and `extra/flutter_project/` (absent), `images/intelnode_icon.png` vs `images/icon.png`. `.cursorrules`, `.windsurfrules`, `GEMINI.md`, `AGENTS.md` and `.github/copilot-instructions.md` duplicate the same ruleset. The recon claim that `.cursorrules` and `.windsurfrules` are absent was wrong; both exist.
- **Fix direction:** move the screenshots to `docs/` or delete them. Delete or document the dead dirs. Keep one canonical ruleset and generate the duplicates. The agent files are protected, so edit them only with the owner's go-ahead.

### L-18 CI does not verify 16 KB ELF alignment (S-8 gap) [executed `readelf -lW` for `p_align` only]
- **Files:** `android/app/src/main/cpp/CMakeLists.txt:10` (`-Wl,-z,max-page-size=0x4000`). `android/app/src/main/jniLibs/arm64-v8a/*.so` (17 prebuilt libs, all LOAD `p_align` 0x4000, `libexec_pulseaudio.so` 0x10000). The 67 libs in `assets/assets.zip` have 0x10000.
- **Problem:** only `p_align` was checked. File and zip offsets and the out-of-tree `patchelf` step are not scripted or verified.
- **Fix direction:** add a CI step that runs `readelf -lW` on every `.so` in jniLibs and asserts alignment, and add `zipalign -c -P 16` on the built APK. Script or document the patchelf step.

## Back-burner (Ubuntu, openSUSE, Kali, window managers i3 / Openbox / Fluxbox / IceWM / AwesomeWM / bspwm). Do not schedule ahead of the priority items above.

### BB-1 Kali `verified: true` is misleading (Low) [read]
- **File:** `lib/distros.dart:600-611` (`verified: true` at `:607`, with a note saying it "requires confirmation"). It has no pin (`ChecksumKind.none`), so `checksumSource` refuses it at install time. That is fail-closed by the other gate. The `verified` gate at `lib/container_installer.dart:87` does not protect Kali.
- **Fix direction:** set `verified: false` until it is device-tested. Keep the checksum gate.

### BB-2 sudo verification skipped for openSUSE (Medium sub-item of M-8) [reasoned]
- **File:** `lib/container_installer.dart:416-418`. Same issue as M-8: the zypper first-boot installs no sudo. Fix with the Debian and Void work in M-8.

### BB-3 Fedora `tint2` (Openbox WM entry) and Openbox rc.xml rewrite (Low) [executed index check for tint2; rc.xml read]
- **Files:** `lib/desktop_environments.dart` (Openbox dnf list; `tint2` is absent from Fedora 40 aarch64). With `--skip-broken` a missing name may still fail, which was not run. `assets/scripts/start-desktop:145-147` (Openbox `rc.xml` and `lxqt-rc.xml` are rewritten whenever the file lacks `<application class=`, losing customisation).
- **Fix direction:** remove `tint2` from the Fedora list or use a different panel. Merge rather than overwrite `rc.xml`.

### BB-4 Unverified items (note only) [not checked]
- Ubuntu rootfs pin was not re-verified. openSUSE zypper pattern names and Kali packages were not checked. Arch package names (stock groups) were not checked against an ALARM index. The termux/proot-distro pins for Debian, Fedora, openSUSE, Alpine v4.x and Void v4.x could not be re-verified (GitHub API disabled; multi-hundred-MB downloads not attempted). Alpine v3.21.3 and Void 20250202 were re-verified against vendor files.

## What to preserve
Confirmed by the critic unless noted. Do not regress these while applying the fixes above.

- **S-1 Fail-closed rootfs verification, pinned per exact URL** (`lib/container_installer.dart:240-282`, `:286-311`, `:449-470`; `lib/distros.dart:20-22`, `:61-66`). `checksumSource` is a pure function and `ChecksumKind.none` is refused by default. The hash is resolved before download, and the sidecar comes from the first-listed origin. Distinct exit codes separate a mismatch (delete) from a tool failure (keep). `checksumFor` only accepts `^[0-9a-f]{32,64}$`. Critic caveat: "fail-closed" is accurate, but Arch's MD5 is not a trust anchor (L-2). Stage 2 probes confirmed that a sidecar 404, an HTML body and a first-mirror timeout all abort before any tarball request.
- **S-2 Trust-invariant tests** (`test/distros_pins_test.dart:21-67`, `test/package_trust_test.dart:14-62`). Every non-rolling URL must have a 64-hex pin, and an empty allow-list greps `lib/` for `gpg-auto-import-keys|nogpgcheck|no-gpg-checks`. The `.deb` helper must contain `sha256sum -c -` before unpacking. 297 tests passed on the stage 2 tree. Critic: the claim that these tests "would have caught" the old fail-open hole is a counterfactual and is not asserted here.
- **S-3 `DocumentPathGuard`** (`android/app/src/main/java/com/daripper91/daripped/DocumentPathGuard.java:22-67`). Pure Java with canonicalise-then-separator-aware prefix checks. Stage 2 ran a standalone harness (10 cases, including sibling prefix and symlink file and dir escapes) with all passing. Fix the provider's low items (L-7), not the guard.
- **S-4 One shell-quoting primitive** (`lib/workflow.dart:195-196` `Util.escapeShellArgument`, used throughout `lib/container_installer.dart`). Extend it for L-13 rather than adding a second scheme. Stage 3 found no live injection.
- **S-5 Staged, contained tar extraction** (`lib/container_installer.dart:214-231`, `:643`). It extracts to a staging dir with `--exclude='dev/*' --delay-directory-restore`, then moves. In-guest deb unpack uses `--keep-directory-symlink --no-same-permissions --no-same-owner` and propagates failure. Stage 2 reproduced traversal containment with GNU tar 1.35 (not on Android). When deleting the dead `rootfsExtractCommand` (L-6), keep these flags.
- **S-6 Config-driven manifests** (`lib/distros.dart:3-5`, `:72-95`; `lib/desktop_environments.dart:14-15`, `:32-37`, `:66-67`). A new distro or desktop is one data entry, and `packagesByDistroId` already exists for M-3. Critic/stage caveat: the `RootfsSource.verified` flag is unreliable (BB-1), so fix the flag and keep the checksum gate.
- **S-7 In-code provenance and evidence notes** (pin comments at `lib/distros.dart:61-66`, `:464-465`, `:558`, `:587`; "Detects corruption, not tampering" at `:27-28`; the zypper key-fingerprint rationale at `:353-363`, locked by `test/package_trust_test.dart:29-32`). Stage 2 re-verified the Alpine 3.21.3 and Void 20250202 pins against vendor files. Keep these comments when refactoring.
- **S-8 (as corrected by the critic: Overstated) 16 KB page-size handling at artifact level only.** `android/app/src/main/cpp/CMakeLists.txt:10` sets the flag for the one in-tree lib. All prebuilt libs in jniLibs and `assets.zip` showed LOAD `p_align` of 0x4000 or 0x10000. This was not verified at build level (no build ran), and offsets and the patchelf step are unchecked. Keep the flag, and add the CI check in L-18.
- **S-9 Smaller specifics.** `X11KeyboardReceiver.readBoundedLine` (`X11KeyboardReceiver.kt:92-101`, 64-char cap, 4 concurrent clients) has correct buffer handling, and the receiver is `exported=false` and asserted by `test/android_manifest_exports_test.dart`. `Util.downloadFile` resume and 416 handling (`lib/workflow.dart:498-568`) had no boundary bug. The real baseline on the stage 2 tree was 297 passing tests and 10 info-level analyzer notes with 0 warnings or errors.

## Audit methodology note
Six-stage chain (recon, core verification, bug hunt, strengths, critic, fix-plan synthesis), critic-reconciled (B-1, B-2, B-3 re-rated Medium; B-4 Low; B-1 mic-read claim and B-8 citation errors removed; recon's `.cursorrules` claim dropped), run 2026-11-20 against HEAD `ef0621f` with no APK built, no device runs and no source files modified; stage 2 tests and analyzer ran on an earlier tree and were not re-run on HEAD.
