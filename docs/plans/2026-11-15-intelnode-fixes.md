# IntelNode: make the two-stage first run survive a real phone, then close CI and repo hygiene

> **Implement task-by-task, in order.** Group A is first because the first run is currently device-blocking. The checksum step died on a Pixel 10 Pro with `CANNOT LINK EXECUTABLE ".../files/bin/busybox": library "libbusybox.so.1.37.0" not found` (task A1). The failure handler then deleted the complete 790 MB tarball (task A2). Both are already fixed on worktree branch `fix/resilient-first-run`, but **neither fix has been verified on a device yet**. Do not close A1-A3 until a phone run gets past the checksum step. Expect more failures in later steps, because extract, provisioning, finalize, verify and the desktop install have never run on a phone.

**Context:** IntelNode (DaRipped_tiny_computer) is a Flutter Android app that runs an Arch Linux ARM proot desktop. This pass audited commits `e7e05f9..628c9a9` on main, judged against `b91cdc5`. That range is the two-stage first run (visible PTY, echoed exit marker, desktop picker), the checksum and Ubuntu pin, the CI signing changes, and the removal of the bundled `assets/xa*` rootfs. Already solid, so don't re-litigate:
- The marker and `$?` echo logic in `lib/setup_session.dart` (no false success at any simulated chunk size).
- The `_prootRun` quoting round-trip.
- The `checksumFor` parsing.
- All pacman package and group names, checked against the live ARM repo databases.
- Secrets hygiene in the range (gitleaks clean).
- The injected `run`/`log`/`onProgress` seam in `installBase`/`installDesktop`.

Caveat: most "verified" evidence is host-only (`bash -n`, shellcheck, stubs, a host busybox, `flutter test` +106 green). The one device run proved that this evidence class misses linker-environment failures.

**How to read the tables.** Severity is the critic's final severity (second pass). Status values:
- `FIXED-IN-WORKTREE`: fixed on branch `fix/resilient-first-run`. The commit is given where the scratch file supports it. For commit-message-only attributions the scratch file says "from commit messages only".
- `OPEN`: not addressed.
- `NEEDS-USER-DECISION`: a policy or data call is needed first.

"Device?" says whether verification needs a phone. Commits on the branch: 368d2f9, de413d9, a386c7e, f6f987a. The scratch file records the content of 368d2f9, de413d9 and f6f987a only. **The content of a386c7e is not described anywhere in the scratch file**, so no finding is attributed to it. When executing, run `git show a386c7e --stat` and reconcile.

---

# Group A: Device-blocking first-run issues

## Task A1: Export `LD_LIBRARY_PATH` in every script that runs bundled `busybox`

**Source:** 03c (first-hand device finding), 04b #3. **Severity:** HIGH, VERIFIED-ON-DEVICE. **Status: FIXED-IN-WORKTREE (f6f987a), not yet device-verified.**

**Problem:** `lib/container_installer.dart` `_checksumScript` (main :256-281; 03c cited ~:268-280) and `_finalizeScript` (main :240-251) call `$DATA_DIR/bin/busybox` without `export LD_LIBRARY_PATH=$DATA_DIR/lib`. The legacy inline copy in `execute` (main ~:203) has the same gap. Only `_extractScript` (:231) and `_prootRun` (:420) export it. On the phone, checksum verification failed with exit 1 and the linker error above. `workflow.dart:1499-1506` stages `libbusybox.so.1.37.0` into `$DATA_DIR/lib` and relies on `LD_LIBRARY_PATH`. The cause is inferred from source, not observed by a passing run.

**Steps:**
1. Confirm f6f987a exports `LD_LIBRARY_PATH=$DATA_DIR/lib` in `_checksumScript`, `_finalizeScript` and the legacy inline script in `execute`.
2. Confirm f6f987a's checksum script returns the distinct exit codes 2 and 3 and that the tests use a fake busybox that refuses to start without the linker env.
3. Grep `lib/` for any other `$DATA_DIR/bin/busybox` call sites and confirm each has the export.

**Verification:** `flutter test` (fake-busybox tests). **Needs a device:** YES. Install the debug APK, run first run, and confirm the "Verifying checksum" step prints a match and exits 0, with no linker error. Until then the cause stays "inferred".

## Task A2: Do not delete a complete tarball because a tool failed

**Source:** 03c, 04b #4. **Severity:** HIGH, VERIFIED-ON-DEVICE (on de413d9). **Status: FIXED-IN-WORKTREE (368d2f9 / f6f987a; the critic saw separate conditional removals at worktree container_installer.dart lines 361 and 384, with the exact commit not stated).**

**Problem:** At b91cdc5 `installBase`'s `catch (_) { run("rm -rf staging tarball"); rethrow; }` (container_installer.dart:352-357) deletes the tarball after any failure. On the phone, the de413d9 handler ran `rm -f` on the finished 790 MB tarball (step2.sh) and `rm -rf` on staging (step3.sh) after a busybox-only failure. At b91cdc5 this outcome is by reading, not observation. `_finalizeScript` (:250) also deletes the tarball before stage 2 starts. A stage-2 failure therefore forces a full re-download (stage 2 #7, stage 3 #10).

**Steps:**
1. Confirm the worktree removes staging and the tarball in separate conditional runs. The tarball should be removed only when it is corrupt or a checksum mismatch is proven, not on tool failure.
2. Confirm the finalize step keeps the tarball until stage 2 succeeds, or document the intentional trade-off.
3. Add a test with an injected `run` that fails at the checksum step with exit 2 or 3 (tool failure) and assert the tarball is kept. Add a second with a real mismatch and assert it is removed.

**Verification:** unit tests as above. **Needs a device:** YES for end-to-end. Kill the app after a successful download and confirm the next launch resumes or reuses the tarball.

## Task A3: Resumable, bounded network access for the first-run download (and its metadata fetches)

**Source:** 03b N1; critic kickback 1. **Severity:** HIGH (real device log: `debug/logs/20261115-190842/logcat.txt:82396` `ClientException: Connection closed while receiving data`). **Status: FIXED-IN-WORKTREE for download resume (368d2f9, per the critic's read of worktree `workflow.dart:455-515` and `container_installer.dart:341/:361`); OPEN for the sub-items below.**

**Problem:** At b91cdc5 `Util.downloadFile` (workflow.dart:445-478) is a single `client.send` with no timeout, retry or `Range` header, and it truncates via `openWrite()`. A mid-stream close throws, and the cleanup then deletes the partial file. The mirror serves `accept-ranges: bytes` and a content-length of 829367415 bytes (~791 MiB), so resume is possible. Remaining holes, which no commit message claims to cover:
- `container_installer.dart:268` checksum `http.get` has no timeout or retry.
- `distros.dart:77` and `:88` (simplestreams `http.get`) have no timeout or retry.
- `distros.dart:251` has a single hard-coded mirror, `de3.mirror.archlinuxarm.org`, with no fallback.
- The download exception is rethrown without being `log()`ed into the terminal, so the user sees no error text.
- A stalled (not closed) connection hangs forever, because there is no `.timeout`.

**Steps:**
1. Confirm worktree `workflow.dart:455-515` sends `Range: bytes=<existing>-`, appends rather than truncates, retries with an attempt counter, and shows "Connection lost ... retrying". Run `download_resume_test.dart`.
2. Add `.timeout(...)` to the chunk stream and to the `http.get` calls at container_installer.dart:268 and distros.dart:77/:88.
3. Log the download failure (message and exit) into the setup terminal before rethrowing.
4. Add a fallback mirror list (or the `os.archlinuxarm.org` redirector) in distros.dart near :251. This is a source decision, see A3b.

**Verification:** `flutter test`. **Needs a device or a throttled/closing local HTTP server:** YES for the real mid-stream drop and for resume against the mirror.

## Task A3b: Mirror fallback policy

**Source:** 03b N1(d). **Severity:** HIGH as part of N1. **Status: NEEDS-USER-DECISION.**

**Problem:** There is only one mirror (`distros.dart:251`). Which fallback host(s) are acceptable, given the checksum is MD5 fetched from the same mirror (stage 2 #9 caveat: it guards corruption, not a hostile mirror)?

**Steps:**
1. User picks the fallback host(s) and whether to also verify the ALARM `.sig`.
2. Implement under A3 step 4.

**Verification:** unit test for the fallback order. **Device:** no.

## Task A4: Desktop picker must not throw on the system back button

**Source:** Stage 3 #8. **Severity:** medium. **Status: FIXED-IN-WORKTREE (the critic saw `desktop_picker.dart:62-82` wrapped in `PopScope(canPop: false)`; commit message attribution: de413d9 "harden setup session and picker").**

**Problem:** At b91cdc5 `lib/desktop_picker.dart:64-77`: `barrierDismissible: false` does not block Android back, so `showDialog` returns null and `return choice!` (:77) throws "Null check operator used on a null value". After the base install, the install is stuck and the error is shown without a retry. If the Activity is destroyed while the dialog is open, the future dies with the process (low-memory kill, `singleInstance`, AndroidManifest :16). Also `G.homePageStateContext` used as the dialog context may be disposed (NV).

**Steps:**
1. Confirm the PopScope is in place and `choice!` is replaced by something that cannot throw.
2. Add a widget test for the back path (none exists; first_run_flow_test.dart covers the body only).

**Verification:** widget test. **Needs a device:** YES to confirm Android back and Activity recreation behave.

## Task A5: `SetupSession.run()` must not wedge or hang forever

**Source:** Stage 2 #6; stage 3 #9; 03b N3. **Severity:** medium. **Status: FIXED-IN-WORKTREE in part (PTY exit: `pty.exitCode.then(...)` at worktree `setup_session.dart:29`, commit message de413d9 "harden setup session"). OPEN: no timeout string found in worktree `setup_session.dart`.**

**Problem:** `lib/setup_session.dart:68-89` at b91cdc5 shows these defects:
- (a) `_pending` is set at :76-78 before `pty.write` (:79), which is outside the try/finally (:84-88). A throwing write leaves `_pending` non-null and every later `run()` throws "already running". That includes the cleanup `run` in `installBase`'s catch, which masks the original error.
- (b) There is no timeout on `await _pending!.future`. `pacman-key --init` can stall on entropy, a mirror can stall, and a script blocked on stdin (the PTY is its stdin) hangs the UI forever.
- (c) PTY exit was not observed. If the user types `exit` or Ctrl-D, or the shell is killed, the run hangs. The terminal is interactive.
- (d) The regex requires exactly one literal space between token and code (:44), so ANSI, CR, backspace or a double space means the marker never matches and the run hangs (executed in stage 2 #5e).
- Ctrl-C yields exit 130 and triggers the cleanup `rm -rf`, which can wipe a download (mitigated by A2).
- `dispose()` runs only on the success path (workflow.dart:1612-1613) and never disposes `controller`.

**Steps:**
1. Move `_pending` assignment and `pty.write` inside the same try/finally, so `_pending` is always cleared.
2. Keep the `pty.exitCode` handler from the worktree and complete the pending run with an error.
3. Add a per-step timeout (configurable, generous for pacman) that completes the run with an error and tells the user in the terminal.
4. Loosen the marker regex to tolerate ANSI/CR/extra whitespace between token and code.
5. Dispose the `controller` and the PTY on failure paths when the user leaves the terminal (see A6).
6. Add tests: write throws, PTY exits mid-run, timeout fires.

**Verification:** unit tests with a fake PTY. **Needs a device:** YES for real PTY chunking and mksh echo (see group E).

## Task A6: Failure UX of `initForFirstTime`, and `selectedDE` written before stage 2

**Source:** Stage 2 #7; stage 3 #10; 03b N3. **Severity:** medium. **Status: FIXED-IN-WORKTREE in part (Retry affordance: `G.retryStartup`, worktree `workflow.dart:1347-1350`; setupSession cleared at :1657; previous session disposed at :1600; per the critic's read, no try/finally was confirmed). OPEN: `selectedDE` still set before install (worktree `workflow.dart:1626`).**

**Problem:** At b91cdc5 `lib/workflow.dart:1545-1614` has no try/finally. On a throw, `G.setupSession.value` stays set and `session.dispose()` is never called, so the PTY leaks until process death. `main.dart:2367-2373` writes `Error initializing app:\n$e` and returns, and the stack trace goes only to `debugPrint`. `selectedDE` is written at workflow.dart:1573 (worktree :1626) BEFORE stage 2 starts, so a failed stage 2 leaves a `selectedDE` for a DE that is not installed (the only reader found is settings.dart, so the UI effect is NV). Leftovers: `containers/0` after a stage-2 failure, `setup/stepN.sh` files never cleaned, `bin/ lib/ tiny/` from `setupBootstrap`.

**Steps:**
1. Confirm the worktree Retry button re-enters `initForFirstTime` cleanly (previous session disposed, no duplicated PTY).
2. Move the `selectedDE` write to after `installDesktop` succeeds.
3. Surface the stack trace (or a copy-able error) in the terminal or the error screen.
4. Decide whether `setup/stepN.sh` should be cleaned after success.

**Verification:** `flutter test` for the ordering, plus a failure-injection test with a fake `run`. **Needs a device:** YES for the Retry flow on a phone (the Retry button appearing was observed once in 03c, after the checksum failure).

---

# Group B: Correctness and robustness

## Task B1: Exit code truncated when the marker is split mid-digit

**Source:** Stage 2 #4. **Severity:** low. **Status: OPEN.**

**Problem:** `lib/setup_session.dart:43-46` `RegExp("<token> (\\d+)")` with the tail logic at :53-60. Feeding `...@@INTELNODE-1@@ 1` then `27\r\n` completes with code 1, not 127. A failure can never become success (the first digit is nonzero), only a wrong number in the error text. Real PTY chunking is NV.

**Steps:**
1. Require a terminating non-digit (`\r` or `\n`) after the code before completing, keeping the tail until it arrives.
2. Add a chunk-size sweep test (1..199) asserting 137 comes out for a split `137`.

**Verification:** unit test. **Device:** no (real chunking is group E).

## Task B2: `userdel` failure is swallowed in `_commonUserSetup`

**Source:** Stage 2 #11 (F); stage 3 #14(b). **Severity:** low. **Status: FIXED-IN-WORKTREE (de413d9, commit message "surface userdel/dbus failures").**

**Problem:** `lib/distros.dart:188-206` has `userdel -r "$existing" || true`. If uid 1000 cannot be freed, the later `useradd` dies with "UID 1000 is not unique" (exit 4) and the reason is lost. Same function also: a pre-existing `tiny` at another uid is kept (guard `id -u $username ||`), and a re-run of the sudoers write after `chmod 0440` may fail under proot (NV).

**Steps:**
1. Confirm the worktree prints the `userdel` failure reason and still fails closed.
2. Decide whether a pre-existing `tiny` with uid != 1000 should be an explicit error.

**Verification:** stub test (as in stage 2 #11). **Needs a device:** YES for real `useradd`/`userdel` under proot.

## Task B3: `start-arch.sh` dbus bring-up hides failures

**Source:** Stage 3 #14(d); 03b N4. **Severity:** low-medium. **Status: FIXED-IN-WORKTREE (de413d9, commit message "surface userdel/dbus failures").**

**Problem:** `assets/scripts/start-arch.sh:21`: `sudo -n dbus-daemon --system --fork 2>/dev/null || dbus-daemon --system --fork`. The first failure is hidden, and the fallback runs unprivileged under `--change-id`. If both fail there is no error and `start-desktop` proceeds without a system bus. `rm -f /var/run/dbus/pid` (:14) can race a still-living daemon. The script has no `set` or exit handling, so DNS or mkdir failures are silent.

**Steps:**
1. Confirm the worktree logs a one-line warning when both dbus attempts fail.
2. Optionally check for a running daemon before removing the pid file.

**Verification:** read plus `bash -n`/shellcheck. **Needs a device:** YES (dbus under proot).

## Task B4: `~/.intelnode-session` read is not normalised in `start-desktop`

**Source:** Stage 3 #1 (critic: medium -> LOW). **Severity:** low. **Status: FIXED-IN-WORKTREE (de413d9, commit message "tolerant start-desktop session parsing").**

**Problem:** `assets/scripts/start-desktop:52-54`. Trailing spaces, CRLF, leading space, multi-word value, empty file, or an uninstalled name all fall through to autodetect with no log line. Autodetect (:55-62) cannot find openbox, fluxbox or icewm, so for those three the session file is the only path. The current writer (`container_installer.dart:399`, `printf '%s\n'`) is clean, so the trigger is hand-editing or a future multi-word `xinitrcExec`. Also, `container_installer.dart:408` interpolates `xinitrcExec` inside single quotes, so a future manifest entry containing `'` would break quoting (stage 2 #10).

**Steps:**
1. Confirm the worktree trims whitespace and CR and logs when the file is present but unusable.
2. Add a manifest-level assertion that every `xinitrcExec`/`xdgDesktopName`/package token matches `^[A-Za-z0-9@._+-]+$`.

**Verification:** fake-PATH run of start-desktop lines 46-75 (as in stage 3 #1) and a unit test for the manifest assertion. **Device:** only for the final launch (group E).

## Task B5: Remove the dead `G.postCommand` / `firstRunScript` / `first-run.sh` path

**Source:** Stage 3 #4; 03b N4 (critic: medium -> LOW). **Severity:** low. **Status: FIXED-IN-WORKTREE (de413d9, commit message "remove dead first-run path").**

**Problem:** `workflow.dart:1308` (decl), `:1726-1729` (`firstRunMarker`/`firstRunScript`), `:1782-1786` (writer), `start-arch.sh:24-28` (consumer) and `test/workflow_test/first_run_test.dart` form a path that never fires because nothing assigns `G.postCommand` after e7e05f9. The test gives false assurance. `firstRunScript` also lacks `set -e`, so it would write the marker even on failure.

**Steps:**
1. Confirm all five items are gone on the branch and `flutter test` is still green.

**Verification:** `flutter analyze --no-fatal-infos`; `flutter test`. **Device:** no.

## Task B6: Shared constant for the guest username and uid

**Source:** Stage 3 #11. **Severity:** low. **Status: OPEN.**

**Problem:** The boot path hard-codes `--change-id=1000:1000` (workflow.dart:1322), `setPwd("/home/tiny")` (:1323), `HOME=/home/tiny USER=tiny` (:1387), the `/home/tiny/...` mounts (:1357-1374, :1741, :1777-1779), and `su - tiny` (start-arch.sh:25, :35). The installer uses `username = "tiny"` (container_installer.dart:54) and `-u 1000` (distros.dart:190-195). They agree today, but there is no shared constant, so changing one silently yields a container whose boot user does not exist. Also, bind-mount targets under `/home/tiny/.local/...` do not exist in a freshly useradd'd home (NV).

**Steps:**
1. Introduce one constant for name, uid and home, used by both the installer and the boot command.
2. Add a test asserting the installer script and boot command both use it.

**Verification:** unit test. **Needs a device:** YES for the bind-mount-to-missing-path behaviour.

## Task B7: `start-arch.sh` runtime concerns (X socket removal, DNS)

**Source:** 03b N4. **Severity:** low (X socket, downgraded from medium by the critic; NOT-VERIFIED) and low-medium (DNS; NOT-VERIFIED). **Status: OPEN, needs a device first.**

**Problem:**
- `start-arch.sh:15` `rm -rf /tmp/.X11-unix/*` runs at every container launch. In X11 mode `launchXServer()` (workflow.dart:1671) runs BEFORE `launchCurrentContainer()` (:1912) and may already have created the socket. Whether clients still connect via the abstract socket is unknown. The line dates from the original script (2de1f8f).
- `getprop net.dns1/net.dns2` (:7-8) are likely not populated on modern Android, so the 1.1.1.1/8.8.8.8 fallback is almost always used.
- The `su - tiny` branch (:34-36) is unreachable under `--change-id` and would drop DISPLAY/PULSE/LD_PRELOAD if reached.

**Steps:**
1. On a device, check `ls /tmp/.X11-unix` before and after launch in X11 mode and whether a client connects. Only then decide whether to scope the `rm` (for example, skip the active display's socket).
2. On a device, run `getprop net.dns1` and decide whether to read resolvers another way or accept the static fallback.

**Verification:** device. **Needs a device:** YES.

## Task B8: Debian `policykit-1` time-bomb

**Source:** 03b N6. **Severity:** low today, medium as a time-bomb. **Status: OPEN.**

**Problem:** `_debianFirstBoot` installs `policykit-1`. It exists in bookworm and Ubuntu noble, but is ABSENT in Debian trixie (only `polkitd`/`pkexec`). When the product at `distros.dart:~284` is bumped from bookworm to trixie, `apt-get install ... policykit-1` fails under `set -e`. `polkitd` exists in all of bookworm (122-3), trixie (126-2) and noble (124-2ubuntu1). Installing `polkitd` drags in systemd and dbus (postinst under proot NV).

**Steps:**
1. Replace `policykit-1` with `polkitd` in the Debian/Ubuntu first-boot script.
2. Add a test asserting the Debian package list contains no `policykit-1`.

**Verification:** unit test; package facts already verified against live indexes. **Needs a device:** YES for `polkitd` postinst under proot.

## Task B9: Fedora product `fedora:41:arm64:default` does not exist

**Source:** 03b N6 (critic: HIGH -> MEDIUM). **Severity:** medium. **Status: NEEDS-USER-DECISION.**

**Problem:** `distros.dart:264` `product: "fedora:41:arm64:default"` is not in the live linuxcontainers.org index (published arm64 default products: `fedora:43`, `fedora:44`, `fedora:45`). `RootfsSource.resolve()` always throws "Simplestreams product ... was not found". This is the legacy add-container path (container_setup_page.dart), labelled unverified (:72), so it fails loudly. It is not a first-run blocker. Fedora 41 package names are NOT-VERIFIED; Fedora 43 `glibc-langpack-en`, `polkit` and `sudo` exist.

**Steps:**
1. User decides: bump to `fedora:43` (the verified release), or remove the Fedora entry.
2. If bumped, re-check the rpm first-boot package names against that release.

**Verification:** query the simplestreams index (unit test with a recorded index). **Needs a device:** YES for rpm provisioning under proot.

## Task B10: Locale generation can silently do nothing on Debian/Ubuntu

**Source:** 03b N6. **Severity:** low. **Status: OPEN, NOT-VERIFIED.**

**Problem:** `sed -i 's/# en_US.UTF-8/en_US.UTF-8/'` assumes the locale.gen line exists. The Ubuntu noble `/etc/locale.gen` content was not unpacked. A no-match sed is silent, so `locale-gen` yields nothing and the hard-coded `LANG=en_US.UTF-8` (getBootCommand :1387) falls back to C/POSIX with no failure signal. The Arch spelling `#en_US.UTF-8` was verified against the real file.

**Steps:**
1. Unpack the noble `locales` package and check the line.
2. Add a post-check (`locale -a | grep -i en_US`) that logs a warning.

**Verification:** read plus host check. **Device:** no for the check; yes to confirm locale on a running guest.

## Task B11: Setup terminal minor UX gaps

**Source:** 03b N3; 04b #2. **Severity:** low. **Status: OPEN.**

**Problem:** In `lib/setup_terminal.dart`, "Copied" is shown even for an empty buffer after `copyAll`. `onPressed: session.paste` (:46) has no feedback or error handling. The font is fixed at 11. No widget test exists. Soft-keyboard layout (`terminal.onResize` -> `pty.resize` repeatedly, plus the large icon above at main.dart:1840) and long-press selection are NOT-VERIFIED. For one frame after `session.dispose()` the TerminalView can write to a killed pty (flutter_pty behaviour NV). The paste goes straight to the PTY stdin of the running script.

**Steps:**
1. Show "Nothing to copy" for an empty buffer.
2. Wrap paste in try/catch with feedback.
3. Add a SetupTerminal widget test.

**Verification:** widget test. **Needs a device:** YES for keyboard, selection and layout.

## Task B12: Digit/other minor setup items from the audit (informational hardening)

**Source:** Stage 2 #12; 03b N4. **Severity:** info/low. **Status: OPEN, optional.**

**Problem:**
- Stage 2 #12: the `DisableSandbox` insert (`distros.dart:216`) is a no-op on current ALARM (the tarball already ships `DisableSandboxFilesystem` and `DisableSandboxSyscalls`). Harmless, but the comment is true only by accident.
- 03b N4: `extraOpt` is spliced raw into the boot command and also exported (harmless redundancy). User-configurable `defaultHidpiOpt`/`defaultTurnipOpt` strings are concatenated unescaped (injection only into the user's own shell).

**Steps:**
1. Make the `DisableSandbox` comment say the line currently exits via the existing options, or match `^DisableSandbox` more precisely.
2. Leave the rest unless the user wants it escaped.

**Verification:** re-run the sed pipeline on a copy of the real `pacman.conf` (as in stage 2 #12). **Device:** no.

---

# Group C: CI and release

## Task C1: Pin Flutter in the release workflows (Gradle/Flutter mismatch)

**Source:** Stage 2 #1 (critic: pre-existing, not introduced by the range; evidence VBE). **Severity:** high. **Status: FIXED-IN-WORKTREE for the "release workflows" per the de413d9 commit message; confirm both files.**

**Problem:** `.github/workflows/release.yml:27` and `flutter-build.yml:27` use `channel: 'stable'` with no `flutter-version`, while `debug-build.yml:42` pins 3.41.6. `android/gradle/wrapper/gradle-wrapper.properties:5` = gradle-8.11.1. The tag runs v2.2.6-debug.1 and .2 (log of run 43776024690) failed: "Your project's Gradle version (8.11.1) is lower than Flutter's minimum supported version of 9.3.1" -> `assembleRelease failed`. Debug run 43782546050 (pinned) succeeded at 628c9a9. That the new signing/analyze steps in release.yml have never run green is an inference from run history.

**Steps:**
1. Confirm both `release.yml` and `flutter-build.yml` pin the same `flutter-version` as `debug-build.yml` (3.41.6).
2. Push a test tag (for example a `-debug` tag) and confirm the release run goes green through Restore, analyze, test and `assembleRelease`.

**Verification:** a real CI run. **Needs a device:** no (needs GitHub Actions; a tag push needs user authorisation).

## Task C2: `flutter-build.yml` never fires on push

**Source:** Stage 2 #2. **Severity:** medium. **Status: NEEDS-USER-DECISION.**

**Problem:** `.github/workflows/flutter-build.yml:5` `branches: [master]`, but the only branch is `main` (default; `gh api` default_branch = main). The last runs are from 2026-07, the master era. Its copy of the signing block is dead except via `workflow_dispatch` (:6).

**Steps:**
1. User decides: retarget to `main`, or delete the workflow (it duplicates release.yml/debug-build.yml).
2. If retargeted, confirm it goes green once with the pinned Flutter (C1).

**Verification:** CI run. **Device:** no.

## Task C3: `set +o pipefail` is a no-op and `sdkmanager --licenses` output is hidden

**Source:** Stage 2 #3 (line numbers corrected in 02b). **Severity:** low. **Status: OPEN.**

**Problem:** `set +o pipefail` at `release.yml:43`, `flutter-build.yml:43`, `debug-build.yml:59`; `yes | sdkmanager` at :44 / :44 / :60. The default `run` shell is `bash -e {0}` with no pipefail, so the line is harmless but its comment is misleading. Dropping `|| true` means a genuine `sdkmanager` failure now fails the step, which is intended, but stdout goes to `/dev/null` so the reason is invisible.

**Steps:**
1. Delete the `set +o pipefail` line and fix the comment in all three workflows.
2. Send `sdkmanager` output to a file and `tail` it on failure, or stop discarding it.

**Verification:** CI run. **Device:** no.

## Task C4: Harden the `Restore signing key` step: guard on ALL four secrets

**Source:** Stage 2 #13; 02b (1) scenario D, 02b (5). **Severity:** low/medium (critic). **Status: OPEN.**

**Problem:** The step script is byte-identical in `debug-build.yml:62-79`, `flutter-build.yml:46-63` and `release.yml:46-63` (md5 99f4f12920fdf59cd2163cd7b560ac8a). It guards only on `KEYSTORE_BASE64` (`release.yml:~53`). With `KEYSTORE_BASE64` set and the other three empty (scenario D, executed), it writes the jks AND a `keystore.properties` containing empty `storePassword=`, `keyAlias=`, `keyPassword=`. With such a file, `android/app/build.gradle` `signingConfigs.release` (:69-74; `storeFile` null-fallback at :72) is selected for both build types (RELEASE type at :79, DEBUG type at :86; each is `keystorePropertiesFile.exists() ? release : debug`). `signingReport` showed the selected config has an unreadable key: `Error: Failed to read key  from store ...`. That the APK build then fails at signing is [UNVERIFIED]; the failure would be loud, not silent wrong-key signing.

**Steps:**
1. In all three workflows, change the guard to require all four of `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and `KEY_PASSWORD` to be non-empty, for example `if [ -z "$KEYSTORE_BASE64" ] || [ -z "$KEYSTORE_PASSWORD" ] || [ -z "$KEY_ALIAS" ] || [ -z "$KEY_PASSWORD" ]`. Emit a distinct `::warning::` naming WHICH secrets are empty (names only, never values) when it is a partial set, and take the same fork-fallback exit.
2. Keep `exit 0` (debug-key fallback) for the all-empty fork case.
3. Optionally dedupe the three identical blocks (a composite action) so the guard lives in one place. The user may prefer not to.
4. Optionally make `build.gradle` check that the four keys are non-blank before choosing `signingConfigs.release` (at :79 and :86).
5. Re-run the 02b scenarios A-D against the edited script: A (all unset) and B (all empty) must warn and write nothing; C (all set) must write both files; D (partial) must now warn and write nothing.

**Verification:** execute the extracted step script in temp dirs (as in 02b). Then run `./gradlew :app:signingReport` on a scratch copy (SDK at ~/Android/Sdk, JAVA_HOME at JBR 21) to confirm a partial secret set falls back to the debug config. **Device:** no. (CI protected-file rule: these workflow edits are authorised only because this plan asks for them.)

## Task C5: Fork/missing-secret release tag produces a debug-key-signed "release" APK; debug artifact is release-key signed

**Source:** 02b (5) scenario 0; stage 2 #13. **Severity:** low (distribution). **Status: NEEDS-USER-DECISION.**

**Problem:** With no `keystore.properties`, debug AND release builds use the debug key (VBE), so a fork or missing-secret tag run yields a debug-key-signed "release". `debug-build.yml` uploads a release-key-signed, debuggable APK as a 7-day artifact on a public repo. It installs as an in-place upgrade over a production build for anyone holding it (the key itself is not exposed).

**Steps:**
1. User decides: should release.yml fail (not fall back) when secrets are missing? Should the debug workflow stop signing with the release key?
2. Implement the choice in `release.yml` / `build.gradle:86`.

**Verification:** CI run on a fork or with secrets blanked. **Device:** no.

---

# Group D: Repo hygiene

## Task D1: Untracked `assets/xaaa`..`assets/xaaj` (~990 MB) bundle into local APKs

**Source:** Stage 3 #7. **Severity:** medium (stale docs + local-build bloat). **Status: NEEDS-USER-DECISION (user data; do not delete without asking).**

**Problem:** `assets/xaaa`..`xaaj` (103M x9 + 60M, dated 8 Mar) and `assets/DIRECTORY_INDEX.md` are untracked and ignored (`.gitignore:54` `assets/xa*`). `pubspec.yaml:77` declares `- assets/`, so a local `flutter build apk` ships ~1 GB of unused chunks while CI (clean checkout) does not. Local and CI APKs differ.

**Steps:**
1. Ask the user whether the chunks may be deleted or moved out of `assets/`.
2. After removal, run `flutter build apk` and confirm the APK size drops by ~1 GB.
3. Optionally narrow `pubspec.yaml:77` to explicit subpaths so stray files can't bundle.

**Verification:** `ls assets`; APK size comparison. **Device:** no.

## Task D2: Stale `.github/copilot-instructions.md` and stale `start-desktop` comment

**Source:** Stage 3 #7 and #15; critic's additional item. **Severity:** medium (stale docs). **Status: OPEN.**

**Problem:** `.github/copilot-instructions.md:35-40` and `:64-65` still tell contributors to build a rootfs, split it into 98 MB `xa*` chunks, copy them to `assets/`, and run `build.ps1`. `:39` has `C:\Users\29513\Downloads\`, another contributor's machine path. This is the architecture removed by e7e05f9/18bbeb5. `AGENTS.md` has no xa/rootfs mention, so only this file is stale. `assets/scripts/start-desktop:47-49` carries a comment that first-run setup "uninstalls the non-chosen DE's packages"; that uninstall was dropped (stage 3 #2). Note: `copilot-instructions.md` is a protected agent-instruction file, so edit it only because this plan explicitly asks.

**Steps:**
1. Rewrite the "Rootfs / Asset Pipeline" section to describe the download, checksum and extract flow, or point it to `AGENTS.md`.
2. Remove the `C:\Users\29513` path.
3. Fix the `start-desktop:47-49` comment (check whether de413d9's session-parsing change already touched it).

**Verification:** `grep -n "xa\*\|98MB\|build.ps1\|29513" .github/copilot-instructions.md assets/scripts/start-desktop` returns nothing. **Device:** no.

## Task D3: Remove the wrong ignore rule for tracked `assets/patch.tar.gz`

**Source:** Stage 3 #6 (critic: medium -> LOW). **Severity:** low. **Status: OPEN.**

**Problem:** `git ls-files -ci --exclude-standard` prints exactly `assets/patch.tar.gz`. `.gitignore:55` lists it but it is tracked (force-added: ab4a3cc, dc8527e). It is a REQUIRED build input (workflow.dart:1421, :1529), so a `git rm --cached`, `git clean -X` or fresh `git add -A` workflow would silently drop it and bootstrap would fail. Contents are upstream scripts and C sources; no personal data.

**Steps:**
1. Delete the `assets/patch.tar.gz` line from `.gitignore` (:55).
2. Run `git ls-files -ci --exclude-standard`; it should print nothing.

**Verification:** that command, plus `git status` clean. **Device:** no.

## Task D4: Delete orphaned xa*-era helpers and their tests

**Source:** Stage 3 #7; recon; second pass dead-code answer. **Severity:** low. **Status: OPEN.**

**Problem:** `Util.rootfsExtractCommand` (workflow.dart:183-184, `cat xa* | ... unxz | tar x`), `Util.swapAlarmTinyIdsCommand` (:171) and `Util.copyAssetsSequentially` (:66) have no `lib/` callers. Only tests reference them: `test/workflow_test/rootfs_extract_command_test.dart`, `swap_ids_test.dart`, `copy_assets_sequentially_test.dart`. They still pass, which is false assurance. `FakeProc` is LIVE (workflow.dart:1348-1350, :1649) and must NOT be removed.

**Steps:**
1. Re-grep `lib/` to confirm no callers (the worktree may have changed this).
2. Delete the three helpers and their three tests.
3. Do not touch `FakeProc`.

**Verification:** `flutter analyze --no-fatal-infos`; `flutter test`. **Device:** no.

## Task D5: Ship (or stop referencing) the `getifaddrs` client library, `cmatrix` and the virtual mic

**Source:** Stage 3 #12 (static facts VERIFIED-BY-EXECUTION; runtime consequences relabelled [UNVERIFIED — worth checking] by the critic). **Severity:** medium. **Status: NEEDS-USER-DECISION.**

**Problem:** `workflow.dart:1741` `LD_PRELOAD=/home/tiny/.local/share/tiny/extra/getifaddrs_bridge_client_lib.so`, and the `:1778-1779` mounts of `tiny/extra/cmatrix` and `tiny/extra/tiny_virtual_mic`. `setupBootstrap` copies only `start-arch.sh`, `start-desktop` and `to_vault` into `tiny/extra` (:1424-1436). `unzip -l assets/assets.zip` and `tar tzf assets/patch.tar.gz` show only `.c` sources (`getifaddrs_bridge_client_lib.c`, `tiny_virtual_mic.c`), and jniLibs ships only the server (`libexec_getifaddrs_bridge_server.so`). `getifaddrsBridge` defaults to TRUE on sdk>=31 (:1695-1697). Pre-existing (same lines in e7e05f9~1), not a regression. The `ld.so` "cannot be preloaded" warning on each exec, the virtual-mic failure (main.dart:1169-1170) and the cmatrix quick-command failure (workflow.dart:719, :787) are all [UNVERIFIED].

**Steps:**
1. User decides: build and ship the three artifacts (cross-compile from the `.c` sources in `patch.tar.gz`), or turn the default off and hide the dependent UI.
2. On a device, run a guest command and look for an `LD_PRELOAD` warning to confirm the runtime claim before choosing.

**Verification:** listing of the shipped artifacts; device run for the runtime effect. **Needs a device:** YES for the runtime claims.

## Task D6: Stale AUR comment for experimental desktops

**Source:** Stage 3 #13; 04 #7. **Severity:** low. **Status: OPEN.**

**Problem:** `lib/desktop_environments.dart:215-217` and `:235-236` say niri, xwayland-satellite and cosmic-session are AUR-only. All three are in `extra` on Arch Linux ARM today. The design (experimental desktops refused in the picker and in `installDesktop`) is sound; only the comment and caveat data are stale. The `installDesktop` refusal has no test.

**Steps:**
1. Correct the comments and the `experimentalCaveat` text. The reason for "experimental" remains the missing nested-compositor bridge.
2. Add a test for the `installDesktop` refusal of an experimental entry.

**Verification:** `flutter test`. **Device:** no.

## Task D7: Branding and launcher art

**Source:** 03b N2; critic kickback 2. **Severity:** low (cosmetic). **Status: FIXED-IN-WORKTREE (368d2f9: new IntelNode logo, adaptive background colour, `images/icon.png` and `launcher_icon.png` and mipmaps replaced). Loading-screen logo confirmed on the phone (03c); the home-screen adaptive icon is NOT device-checked.**

**Problem:** At b91cdc5, `images/icon.png` (used at `lib/main.dart:1840` loading screen and `:2431` About panel; pubspec asset line 80) is the legacy Debian swirl on lavender. `android/app/src/main/res/values/ic_launcher_background.xml:3` is `#D1BAFD`, and the adaptive foreground webp carries the same art. `pubspec.yaml:111-114` `flutter_launcher_icons` has no adaptive keys. `images/intelnode_icon.png` exists but nothing in `lib/` references it.

**Steps:**
1. Verify the branch's adaptive layers (foreground and background) are the new art.
2. Decide whether to delete or use the unreferenced `images/intelnode_icon.png`.
3. Add adaptive keys to the `flutter_launcher_icons` config so regenerating does not revert the layers.

**Verification:** visual check of the installed launcher icon. **Needs a device:** YES (home-screen adaptive icon on Android 8+).

## Task D8: `aid_*` passwd/group entries were dropped from the guest

**Source:** Stage 3 #5. **Severity:** low. **Status: NEEDS-USER-DECISION (and a device check).**

**Problem:** The old first run injected `aid_<user>` / `aid_<group>` entries for the Android uid/gids (e7e05f9~1 `workflow.dart:1669-1678`). The new path does not. Nothing in `lib/` or `extra` reads them. Expected effect: `ls -l` on host binds (/media/sd, /storage, /data) shows numeric owners, and tools needing the owner uid to exist (git "dubious ownership") may behave differently. Kernel checks use numeric ids, so network access (gid 3003) is unaffected.

**Steps:**
1. On a device run `ls -ln /media/sd; git -C /media/sd/x status; id`.
2. User decides whether to restore the injection (cosmetic), `safe.directory` guidance, or accept.

**Verification:** device. **Needs a device:** YES.

## Task D9: Public committed device log and symlinked agent rule files (out-of-range notes)

**Source:** Stage 2 #14; 03b N7. **Severity:** low. **Status: NEEDS-USER-DECISION.**

**Problem:**
- `Bug_Reports/FS/data/misc/recovery/last_kmsg.1` (commit e1dc94d) is a pre-range device log committed to a PUBLIC repo; it was flagged but not reviewed. The other 172 gitleaks hits are vendored wolfssl test keys.
- `.cursorrules`, `.windsurfrules`, `CLAUDE.md` and `GEMINI.md` are now git symlinks to `AGENTS.md` (mode 120000), which break on Windows checkouts without `core.symlinks`.

**Steps:**
1. Review `last_kmsg.1` for personal data and decide whether to purge it from history.
2. Decide whether Windows checkouts matter.

**Verification:** manual review of the file; `git ls-files -s`. **Device:** no.

---

# Group E: Verification gaps that only a device can close

These are NOT-VERIFIED or inferred, and no further host work reduces the risk. The one device run so far died at step 1 of the checksum and says nothing about later steps. Run them in order and expect new failures; keep the visible-terminal design.

| # | Gap | Source | Closes tasks |
|---|---|---|---|
| E1 | Checksum step passes on the phone with `LD_LIBRARY_PATH` (f6f987a), exit codes 2/3 behave | 03c, second pass (b) | A1 |
| E2 | Download resume against a real mid-stream drop (airplane-mode toggle or a throttled server) | 03b N1 | A3 |
| E3 | Extract under proot (`_extractScript`), `_finalizeScript`, `_verifyScript` (`id`, package manager, `sudo -n true`) | second pass (d) | A2, A6 |
| E4 | `pacman-key --init/--populate`, `pacman -Syu` and `DownloadUser = alpm` under proot; entropy stalls | stage 2 #12 | A5 |
| E5 | Real `useradd`/`userdel`, sudoers write on re-run, proot DAC behaviour | stage 2 #11 | B2, B6 |
| E6 | Real PTY chunking and mksh echo (digit-split, ANSI/CR in the marker line) | stage 2 #4-5 | A5, B1 |
| E7 | Picker back button and Activity recreation with the dialog open | stage 3 #8 | A4 |
| E8 | Soft-keyboard layout, long-press selection, paste in the setup terminal | 03b N3 | B11 |
| E9 | `installDesktop` per stable DE; `start-desktop` launch with the session file; i3 first-start wizard; `dbus-launch` runtime | stage 3 #3 | B4, B3 |
| E10 | X socket removal vs the in-app X server; DNS `getprop` | 03b N4 | B7 |
| E11 | `LD_PRELOAD` warning, cmatrix/virtual-mic failures, bind mounts to missing guest dirs | stage 3 #11, #12 | D5, B6 |
| E12 | Ownership display after `aid_*` removal (`ls -ln`, git dubious ownership) | stage 3 #5 | D8 |
| E13 | Adaptive launcher icon on the home screen | second pass (a)2 | D7 |
| E14 | Debian/Ubuntu/Fedora provisioning under proot, `polkitd` postinst, noble `locale.gen` | 03b N6 | B8, B9, B10 |
| E15 | arm64 `libbusybox.so` md5sum/sha256sum applets actually executing | stage 2 #9 | A1 |

Optional host-side shortcut, needing the user's sudo authorisation: a qemu-aarch64 chroot of the ALARM rootfs in `extra/archroot-build/rootfs` could run `_archFirstBoot` cheaply before a phone run (stage 2 "Checks skipped").

---

## Known coverage gaps

From the critic's second pass (both passes read-only; nothing in this audit was re-run by the critic):
- Everything after the checksum step on a device has never run (E3-E9).
- f6f987a (checksum exit codes 2/3, `LD_LIBRARY_PATH` everywhere) and the resume download are not device-verified. The unit tests with a fake busybox were not read by the critic. The critic could not run git in the worktree, so branch contents come from reading the worktree plus commit messages.
- **a386c7e is not described in the scratch file.** Findings attributed to a commit above rest on the critic's worktree reading and on commit messages relayed by the coordinator. Re-confirm each FIXED-IN-WORKTREE status with `git show` before closing it.
- The 03c evidence (screenshots, `setup/step1.sh`..`step3.sh` via run-as, logcat beyond line 82396) is not saved in the repo or `.audit`. The "rm pid 25470" detail was not re-verified. Save those artefacts.
- Real fork or PR CI behaviour was never observed, and "undefined secret expands to empty" is documented GitHub behaviour simulated locally. `actionlint` was not run. `assembleDebug` with an incomplete keystore was not run (only `signingReport`).
- `lib/main.dart` is reviewed only at :1840, :1870-1874, :2367-2373 and :2431. Debian, Ubuntu and rpm first-boot scripts are generated and syntax-checked and package names verified, but not flag-reviewed. The Ubuntu noble `locale.gen` line and Fedora 41 names are NOT-VERIFIED.
- The in-session `CLAUDE.md` content versus `AGENTS.md` was not diffed (cached copy suspected). Windows symlink behaviour was not tested. `README.md` and `images/` are out of scope.
- The "~500 MB download" figure used in some earlier stage text is wrong; the real size is ~790 MiB (`790/790 MB` on the phone, content-length 829367415).

## Definition of done

- **A1:** The checksum, finalize and legacy inline scripts all export `LD_LIBRARY_PATH`. On a phone, "Verifying checksum" prints a match and exits 0 (E1). `flutter test` is green with the fake-busybox tests.
- **A2:** A tool failure (exit 2/3) keeps the tarball; only a proven mismatch or corrupt file deletes it. Tests cover both. A killed app does not force a full re-download (E3).
- **A3:** The download resumes with `Range` after a real drop (E2). The checksum and simplestreams fetches have timeouts. Failures are logged in the terminal. The mirror fallback decision (A3b) is made and implemented.
- **A4:** Android back during the picker does not throw. A widget test covers it (E7).
- **A5:** A throwing write, PTY exit and a stuck step each end in a visible error rather than a hang. `_pending` is always cleared. The marker regex tolerates ANSI/CR/spacing.
- **A6:** Retry works from the loading screen without leaking the PTY. `selectedDE` is written only after stage 2 succeeds. The error is copyable with a stack.
- **B1-B12:** Each OPEN item has a test or a recorded device result. B2-B5 are re-confirmed against the branch commits. B8 uses `polkitd`. B9 is resolved per the user's choice.
- **C1:** A tag run is green end to end on a pinned Flutter.
- **C2/C5:** The user's decisions are applied.
- **C3:** No `set +o pipefail`, and `sdkmanager` failures show a reason.
- **C4:** All three Restore steps require all four secrets non-empty (scenarios A-D re-run: A, B and D warn and write nothing; C writes both files). A partial secret set falls back to the debug key and no longer writes a half-valid `keystore.properties`.
- **D1-D9:** `git ls-files -ci --exclude-standard` prints nothing. `grep` finds no `xa*` or `29513` text in `copilot-instructions.md`. The three orphan helpers and their tests are gone while `FakeProc` remains. The assets decision and the artifact decision (D5) are recorded. `flutter analyze --no-fatal-infos` and `flutter test` are both green.
- **E:** Every row has a recorded result or an explicit "accepted unverified" note in `AGENT_REPORT.md`.
