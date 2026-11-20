# IntelNode: close the public-repo exposure, harden the SAF provider and rootfs/release trust chain, then fix the features that point at things that are not shipped

> **Implement task-by-task, in order, phase by phase.** Highest priority is **Task S11 (Phase 0)**: the public repo carries personal and network identifiers and a third-party email in tracked files, and git history keeps them. It is rated LOW in the ledger (no credential), but it is the only item that gets worse the longer it stays public and it costs minutes to fix, so it goes first. The highest-severity code fix is **Task S1 (Phase 1)**: `TinyDocumentsProvider` accepts `..` document ids and unsanitised display names (MEDIUM; exploitability depends on a user-granted tree URI and on framework behaviour that was not verified).

**Audit date:** 2026-11-19 · **Commit audited:** `d0eaa99` (origin/main, detached worktree) · **Repo:** DaRipper91/IntelNode (public)

**Verdict:** no CRITICAL and no HIGH findings. Final ledger: 55 rows = 13 MEDIUM, 5 LOW-MED, 37 LOW. The installer plumbing is solid and well tested. The real risks are (1) the SAF provider's path confinement, (2) rootfs and package-signature trust, (3) a release workflow with no tag gate and a fail-open signing fallback, (4) a pile of shipped features that reference binaries, commands, JNI symbols and settings that do not exist, and (5) identifier exposure in a public repo.

**Context:** IntelNode is a Flutter/Kotlin Android app that runs Arch Linux ARM (and six other distros) in proot with an in-app X server (README: fork of Cateners/tiny_computer). This pass is a read-only audit of the whole tree at `d0eaa99`; this plan turns the critic-approved ledger (55 rows, SCRATCH.md section 05 "Final finding ledger") into ordered tasks. Already solid, so do not "fix" it: resume-aware `Util.downloadFile`, the `_gpgCleanupTrap` with `set +e`, distinct checksum exit codes, `hoistWrapperDir`/`extractScript`, `rmrf`, the `plan()`/`install()` gate, `sessionCheckScript`, `escapeShellArgument` use, `nativeLibLinkCommand` (`ln -sfn`), `SetupSession` marker parsing, `pickReachable`, SHA-pinned git deps, and `launchXServer` (looper thread plus `xServerLaunchFailed`).

---

## Coverage statement (read this before trusting the plan)

- **Read by stages 02/03:** `lib/workflow.dart`, `lib/main.dart` (union of ranges covers 1-2511), `container_installer.dart`, `container_manager.dart`, `container_delete_dialog.dart`, `setup_session.dart`, `settings.dart`, `start-arch.sh`, `to_vault`, `TinyDocumentsProvider.java`, `AndroidManifest.xml`, the three release workflows. Everything else was grep-traced.
- **Read by the 03 re-check:** `X11FloatingOverlay.kt`, `X11KeyboardReceiver.kt`, `MainApplication.kt`, `MainActivity.kt`, `ContainerSessionService.kt`, `AudioStream.kt`, `Signal9Activity.kt`, `native-socket.cpp` + `CMakeLists.txt`, `lib/desktop_environments.dart`, `lib/models.dart`, `start-desktop` lines 100-476, `workflow.dart` 862-896 and 1108-1376, `main.dart` 476-735 and 1228-2352, `test/first_run_flow_test.dart`; `assets/patch.tar.gz` by `tar -tzvf` listing only.
- **NOT read by any stage:** `lib/boot_log.dart`, `theme.dart`, `fake_proc.dart`, `setup_terminal.dart`; the non-read parts of `lib/distros.dart` (simplestreams/URL tables); 12 of 29 test files; Android resource/layout XML; the external `x11_flutter` / `avnc_flutter` plugin sources (reflective calls into `com.termux.x11.*` are unvalidated); jniLibs internals beyond `strings`/`readelf`. `guest_shims.dart` and `pty_shell.dart` were read in chunks by 02 only.
- **Nothing was executed on a device.** Every runtime consequence tagged "rt-U" in the ledger is a read-based hypothesis, not an observation. Those are collected under "Needs device confirmation".
- **`flutter` / `dart` were not run locally** (not on PATH). The only test evidence is CI run `44134148815` at the same commit: `flutter analyze` "18 issues found" (all info) and 205 tests passed. Those are CI-reported numbers, not re-run here.
- **`gh` evidence** (release authorship, secrets list by name, repo size, run IDs) is time-sensitive and was not re-run by the critic; re-check before relying on it.
- **Shallow, blobless clone:** history-level claims (the ~3 GB size, commit `18bbeb5`, full-history secret scan) are `gh`-derived or not done.

## Protected-file notice

`AGENTS.md` (and its symlinks `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`), `.github/copilot-instructions.md`, `.github/workflows/*` and lock files are protected by the repo ruleset. Tasks that touch them are tagged **[PROTECTED]**: do not start them without the owner's explicit go-ahead for that task.

## Earlier audit plans (do not edit; related items)

`docs/plans/` already holds 2026-11-15 and 2026-11-16 plans. Items below appear to repeat or narrow items in `docs/plans/2026-11-15-intelnode-fixes.md` (those plans track a worktree, not `d0eaa99`; re-verify their status annotations before trusting them): S6/S8 relate to its C4/C5 (signing guard, debug key); F7 to A5 (SetupSession); F16 to A6 (`selectedDE`); F31 to D3 (`patch.tar.gz` ignore rule); F23 to D4 (dead xa* helpers); F3 to D5 (getifaddrs/cmatrix/virtual mic); F34 to D2 (stale copilot-instructions); S11 to D2/D9 (path in docs; public device log). Link to them in the commit message instead of re-describing.

## Task index

| Phase | Tasks (ledger IDs, in order) | Count |
|---|---|---|
| 0 Exposure | S11 | 1 |
| 1 Security | S1, S2, S3, S5, S6, S4, F9, S10, S14, S13 | 10 |
| 2 Runtime-breaking and correctness | F4, F3, F1, F2, F5, F6, F8, F10, F7, F11, F12, S12, F14, F15, F16, F17, F18, F19, F20, F21, F22, F24, F27, F28, F36, F37, F40 | 27 |
| 3 CI / versioning / tests | S8, S7, F32, F33, F35, F29, F23, F38 | 8 |
| 4 Docs / cleanup | S9, F31, F34, F25, F26, F13, F30, F39, S15 | 9 |

Total 55, one task per ledger row. Severity shown is the FINAL ledger severity after critic downgrades.

Effort key: S = under half a day, M = about a day, L = multi-day or needs outside inputs.
Verification key: **CI** = runnable in the existing workflows or locally via `flutter test` / `flutter analyze` / a script; **device** = needs a phone.

---

# Phase 0: do-now exposure fixes (public repo)

## Task S11: Remove personal/network identifiers and the third-party email from tracked files

**Severity:** LOW (ledger; no credential, but identifying data in a public repo with history) · **Effort:** S (tree edit) + owner decisions · **Depends on:** none · **Verification:** CI/local grep; the history decision is outside CI
**Ledger:** S11 (03 #12; critic K1/B1 closed)

**Problem:** Tracked files in a public repo hold identifying data. Types and locations only; this plan deliberately records no values:
- `(OLD) AGENT_REPORT.md:106-112`: a tailnet hostname and tailnet (CGNAT) IPs, an ADB wireless-debugging pairing identifier that embeds a device serial, and private LAN IP:port pairs.
- `docs/HANDOFF-agy-2026-11-16.md:74,76`: LAN and tailnet IPs.
- `debug/README.md:9,10` and `debug/capture.sh:3`: a LAN IP.
- `OWNERS:1`: a third-party (upstream author) email address.
- `.github/copilot-instructions.md:39`: a Windows user-profile path with an account name.
- Plan-writer observation, not a ledger row: `docs/plans/2026-11-15-intelnode-fixes.md` (D2 task text, roughly lines 372-379) repeats that Windows profile path. That file is out of this plan's write scope (do not edit earlier plans); the owner decides.
- Plan-writer cross-reference to F12/R14: every entry in `assets/patch.tar.gz` carries the author's local account name as tar owner/group metadata (handled in F31).

**Steps:**
1. Replace each value above with a neutral placeholder in the current tree: LAN/tailnet addresses in `debug/README.md` and `debug/capture.sh` become an environment variable or `<DEVICE_IP>` argument; delete the connection-record lines from `(OLD) AGENT_REPORT.md` and `docs/HANDOFF-agy-2026-11-16.md` (historical notes, no runtime use); remove the Windows path line from `.github/copilot-instructions.md` **[PROTECTED]** (coordinate with F34).
2. `OWNERS`: grep for consumers first (`git grep -n OWNERS`); then replace the email with the project owner's public contact or delete the file if unused. Do not substitute another private address.
3. Revoke/rotate the records themselves, because history keeps them: remove the wireless-debugging pairing from the phone (Developer options > Wireless debugging > forget paired devices); expire/remove the referenced tailnet node in the tailnet admin console and re-authenticate it. LAN addresses are not secrets; no action beyond removal.
4. **Owner decision, outward-facing, separate from this task:** rewriting history with `git filter-repo` (force-push) would also remove the identifiers from old commits and would be the moment to drop the roughly 3 GB `assets/xaa`-`xae` rootfs chunks (repo size per `gh` is about 3.0 GB; chunks removed from the tree in `18bbeb5`, so use `--path-glob 'assets/xa*' --invert-paths`). It invalidates every clone, fork, tag and release ref and GitHub caches old objects until support purges them. Do not do it as a side effect of this task. If chosen, take a mirror backup first.
5. Do not edit the earlier plans in `docs/plans/`; flag the Windows-path repeat to the owner.

**Verification (CI/local):** `git grep -nE '\.ts\.net|_adb-tls|(100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|192\.168)\.[0-9]+\.[0-9]+|[A-Za-z]:\\\\Users\\\\'` over tracked files returns nothing outside the earlier plans, and `OWNERS` no longer contains an email. History still contains the values until step 4 is done.

---

# Phase 1: security

## Task S1: Canonicalise and confine `TinyDocumentsProvider` (traversal, displayName, symlinks, prefix siblings)

**Severity:** MEDIUM · **Effort:** M · **Depends on:** none (fold S2 into the same change) · **Verification:** CI (JUnit, needs a workflow step: [PROTECTED]) + device
**Ledger:** S1 (02 verdict, 02-recheck K3, Opus A)

**Problem:** `android/app/src/main/java/com/daripper91/daripped/TinyDocumentsProvider.java`: doc id is the absolute path (`:205`); `getFileForDocId` is `new File(docId)` with only an `exists()` check (`:212-216`); `isChildDocument` is `documentId.startsWith(parentDocumentId)` (`:195-196`), so `<root>/../shared_prefs/x` and prefix siblings such as `containers_evil/x` or `containers/10` (tree on `containers/1`) pass. `createDocument` does `new File(parentDocumentId, displayName)` with raw `displayName` (`:122`, `:125`) and returns the raw `getPath()` (`:140`), so `../../bin/x` creates outside the root. `openDocument` honours the client's mode (`:102-105`). Search guards symlinks by comparing a canonical path to an absolute prefix and fails open on `IOException` (`:176-179`). Declaration (`AndroidManifest.xml:58-67`): `exported=true`, `grantUriPermissions=true`, `permission=MANAGE_DOCUMENTS`. Attacker model: only the system picker or an app the user handed a TREE URI on this root can reach it; impact is read/write/delete of the IntelNode app sandbox. Not exploited; framework enforcement (`enforceTree` passing `..` ids and display names unmodified) was not verified on a device.

**Steps:**
1. Apply the patch in `/home/daripper/agent-config-review/intelnode-opus-review.md` section A ("Minimal patch (A)") as a starting point. It is not compiled or tested; review each hunk. It: canonicalises doc ids with `getCanonicalFile()` against the canonical `getFilesDir()/containers` root; adds a separator-aware `isInside(base, f)`; makes `getFileForDocId` an instance method (needs `getContext()`); rewrites `isChildDocument` to require both ids inside the base and the child inside the parent, failing closed on `IOException`; adds `sanitizeDisplayName` (no separators, NUL, `.`/`..`, 200-char cap); checks the parent is a directory and re-checks containment after creation; flips the search `IOException` fallback to `false`.
2. Keep doc ids as `getAbsolutePath()` so already-persisted grants keep working.
3. Optional hardening from the review: refuse `deleteDocument` on the root itself.
4. Extract the path logic (`isInside`, `sanitizeDisplayName`, canonicalise) into a small pure helper class so it can be unit-tested with plain JUnit and temp dirs, instead of needing a `Context`.
5. Add `android/app/src/test/...` JUnit cases: `..` doc id rejected; `containers_evil` and `containers/10` rejected for a tree on `containers/1`; displayName `../../x`, `a/b`, `.`, `..`, empty, 300 chars; symlink pointing outside rejected; root equals itself accepted.
6. Wire `./gradlew :app:testDebugUnitTest` into CI (see F33; [PROTECTED]).

**Verification:** CI: new JUnit suite green; `flutter build apk --debug` still builds. Device: see "Needs device confirmation" S1 (a throwaway client app holding a tree grant must get `SecurityException`/`FileNotFoundException` for `..` ids and a sanitised name for `../../x`).

## Task S2: Null-safety in `TinyDocumentsProvider` (`listFiles()`, `getParentFile()`)

**Severity:** LOW · **Effort:** S · **Depends on:** S1 (same file) · **Verification:** CI (JUnit)
**Ledger:** S2 (Opus A; `:95`, `:182` re-read by critic)

**Problem:** `TinyDocumentsProvider.java:95` and `:182` iterate `listFiles()` without a null check (null on I/O error or non-directory). `:254` calls `getParentFile()` which Opus reports NPEs for `/`; that line was NOT re-read by the critic (UNVERIFIED).

**Steps:**
1. Null-guard `:95` and `:182` (included in the S1 patch).
2. Re-read `:254`; if `getParentFile()` can return null, guard it; otherwise record as refuted.
3. Add JUnit cases: unreadable directory and non-directory parent return an empty cursor, not an NPE.

**Verification:** CI: JUnit cases pass.

## Task S3: Pin SHA-256 per versioned rootfs URL; stop downloading five distros unverified

**Severity:** MEDIUM · **Effort:** M (L if pins must be collected from fresh downloads) · **Depends on:** none (F9 and S4 build on it) · **Verification:** CI (`flutter test`) + device for one real install
**Ledger:** S3 (02, Opus B)

**Problem:** `lib/container_installer.dart:236-258` fetches a checksum only for `archlinuxarm.org` (`.md5`) and `cloud-images.ubuntu.com` (`SHA256SUMS`); every other URL falls to `return null` (`:245-247`). Debian, Fedora, openSUSE, Alpine and Void (`lib/distros.dart:370-431`: proot-distro GitHub release assets plus Alpine/Void fallbacks) and Kali get no verification at all. The tarball is extracted and its first-boot script runs as guest root in proot as the app UID, and the guest's package-manager keyrings come from that same tarball, so a poisoned rootfs poisons later "verified" installs. Transport is https everywhere; the threat is a compromised or replaced upstream asset, not network MITM.

**Steps:**
1. Add a per-URL `sha256` map to `RootfsSource.direct` in `lib/distros.dart` (keyed by URL, not distro, because `pickReachable` can choose a fallback with different bytes), per the "Code sketch (pinned-hash path)" in `intelnode-opus-review.md` section B. Cover every fixed versioned URL: the GitHub proot-distro assets, Alpine 3.21.3 minirootfs, Void `ROOTFS-20250202`, and Ubuntu `release-20261017`.
2. In `container_installer.dart` (`:360` region) prefer the pin: `checksumScript(pinned, tarballPath, "sha256sum")`; fall back to `_checksumScript(url, ...)`; if neither exists, log a loud "UNVERIFIED download" line (better: refuse unless the user opts in). The existing exit-code handling (3 deletes the file, others keep it) already fits.
3. Compute each pin from a fresh download and cross-check against a second source (Opus: proot-distro plugin files may publish `TARBALL_SHA256` per tag; that publication is UNVERIFIED, check it). Record where each pin came from in a comment.
4. Kali is `verified:false` and refused by `install()` (04 #7); if simplestreams `items` carry a `sha256`, return it with the URL (format UNVERIFIED for this server), otherwise leave Kali blocked.
5. Unit test over `Distros.all`: every pin is exactly 64 lowercase hex; every fixed versioned URL has a pin; a tampered fixture tarball makes the install fail with the "delete and retry" exit code.

**Verification:** CI: `flutter test` (new `distros_pins_test.dart` and an installer test). Device: one real install of a pinned distro on the Pixel 10 Pro completes.

## Task S5: Remove unauthenticated package-trust bypasses (`--gpg-auto-import-keys`, `--nogpgcheck`, `--no-gpg-checks`, hash-less .debs)

**Severity:** MEDIUM · **Effort:** M · **Depends on:** none · **Verification:** CI (grep + string tests) + device (openSUSE first boot)
**Ledger:** S5 (02, 03-rc R5, Opus B)

**Problem:** `lib/distros.dart:175,192,301,302` use zypper `--gpg-auto-import-keys`, which silently trusts any new repository signing key. `lib/workflow.dart:1091` runs `dnf --nogpgcheck`. `workflow.dart:1192` runs `zypper --no-gpg-checks install /tmp/qq.rpm` on an RPM whose URL is scraped from a remote JS file with `grep -oP`. `workflow.dart:689-690` (`_debInstall`) installs third-party .debs with no hash; all of this runs with the guest's passwordless sudo.

**Steps:**
1. Drop `--gpg-auto-import-keys` from `updateCommand`/`installCommand` (`distros.dart:175,192`). Keep it at `:301-302` only if first boot genuinely needs it, and then pair it with a key-fingerprint check (Opus). Whether the openSUSE rootfs already ships the keys is UNVERIFIED; confirm on a device first.
2. Remove `--nogpgcheck` (`workflow.dart:1091`) or restrict the command to repos with working keys.
3. Remove the scraped-URL QQ rpm install with `--no-gpg-checks` (`workflow.dart:1192`), or pin a URL plus SHA-256 and verify before `zypper install`.
4. For `_debInstall` entries: add a pinned SHA-256 verify step per .deb, or drop the quick command.
5. Add a test asserting no `gpg-auto-import-keys` / `nogpgcheck` / `no-gpg-checks` strings remain outside an explicit allow-list.

**Verification:** CI: `git grep -nE 'gpg-auto-import-keys|nogpgcheck|no-gpg-checks' lib` returns only allow-listed lines; `flutter test`. Device: first boot of an openSUSE container still provisions (see device list).

## Task S6: `release.yml`: tag guard, prerelease by default, fail-closed signing

**Severity:** MEDIUM (signing sub-risk LOW while the secrets are present) · **Effort:** M · **Depends on:** none (coordinate with S8, F32) · **Verification:** CI on a scratch fork or throwaway tag · **[PROTECTED]**
**Ledger:** S6 (02 verdict as rewritten by 02-recheck K2). Related: earlier plan C4/C5.

**Problem:** `.github/workflows/release.yml:3-6` triggers on ANY pushed tag matching `v*`, including `v2.2.6-debug.2`-style names; it publishes with `prerelease: false` (`:79`) and `generate_release_notes: true` (`:80`) with no environment or approval gate, no check that the tagged commit is on `main`, and no check that signing happened. `:54-57` emits only a `::warning::` and `exit 0` when `KEYSTORE_BASE64` is empty, and `android/app/build.gradle:79` then silently selects `signingConfigs.debug` for the `release` build type when `keystore.properties` is absent. Failure model: an accidental secret deletion/rename/expiry, a fork or repo transfer, or a collaborator/stolen token with tag-push rights publishes a non-prerelease, debug-signed APK that GitHub shows as a normal release; users on a real-key build must uninstall to move to it, losing the proot rootfs. Not an external-attacker RCE. Currently latent: the four `KEYSTORE_*`/`KEY_*` secrets are configured and the only recent `release.yml` runs (including `44106400727`) failed in Gradle before publishing (NDK 27.0.12077973 install), so no debug-signed publish was seen. The earlier claim that the live "Latest" debug release demonstrates this risk is withdrawn (see S7).

**Steps:**
1. Narrow the trigger to strict release tags (for example `v[0-9]+.[0-9]+.[0-9]+`) so `-debug*` tags never run the release job.
2. Add a first step that fails unless the tagged commit is an ancestor of `origin/main` (`git merge-base --is-ancestor "$GITHUB_SHA" origin/main`).
3. Set `prerelease: true` by default, or add a protected `environment: release` with required reviewers (owner choice) and promote manually.
4. Replace the `exit 0` fallback (`:54-57`) with `exit 1` when any of the four secrets is empty, naming which are empty (names only). This subsumes the earlier-plan C4 partial-secret guard.
5. Make `build.gradle:79` fail (`GradleException`) for the `release` build type when `keystore.properties` is absent, rather than choosing `signingConfigs.debug`; keep local convenience behind an explicit `-P` flag.
6. After build, run `apksigner verify --print-certs` on the APK and fail if the certificate is the Android debug certificate (or compare to a stored expected release-cert SHA-256).

**Verification:** CI: on a scratch fork or throwaway repo with the secrets blanked, push `v0.0.1` and expect a hard failure; push `v0.0.1-debug.1` and expect no run; with secrets set, expect a prerelease whose `apksigner` cert matches. Device: none.

## Task S4: Make checksum scheme and tar-flag selection explicit and fail-closed; fetch Arch/Ubuntu sums from a different origin

**Severity:** LOW-MED · **Effort:** M · **Depends on:** S3 · **Verification:** CI (`flutter test`)
**Ledger:** S4 (02, 03 #16a,b, Opus B)

**Problem:** For Arch and Ubuntu the checksum comes from the same host/mirror as the tarball (`container_installer.dart:236-258`), so it detects corruption, not tampering. The scheme is chosen by `url.contains("archlinuxarm.org")` / `contains("cloud-images.ubuntu.com")` (`:239-247`), which is fail-open (a candidate URL without the substring silently gets no verification) and can be fooled by the substring appearing in a path or query. The tar flag is chosen by `url.endsWith('.xz'|'.bz2')` else gzip (`:355`), so `.tar.zst`, `.tgz?x=1` or bare `.tar` silently get `z`.

**Steps:**
1. Replace substring checks with an explicit field on `RootfsSource` (for example `checksumKind` and `compression`), defaulting to "must have a pin or fail".
2. Unknown compression raises an error instead of falling back to gzip.
3. Fetch the Arch `.md5` and Ubuntu `SHA256SUMS` from the first listed mirror/origin rather than the mirror serving the tarball (Opus: cheaply defeats a single rogue mirror). Prefer the dated Ubuntu directory with a pin (S3). Document that the Arch install otherwise trusts the mirror.
4. Tests: a URL with the substring in its path/query must not select a scheme; an unknown extension errors; mirror and sum origin differ.

**Verification:** CI: `flutter test`.

## Task F9: Name partial rootfs downloads by source so resume cannot graft one distro/mirror onto another

**Severity:** MEDIUM (UNVERIFIED; author-tagged reasoned scenario) · **Effort:** S · **Depends on:** S3 (use the pin as the name when present) · **Verification:** CI + device
**Ledger:** F9 (02 #6, Opus B)

**Problem:** `container_installer.dart:343` names the partial `new_rootfs_<index>.tar`, independent of distro and URL. `Util.downloadFile` (`lib/workflow.dart:477-549`) resumes any existing file with a Range request and treats a 416 with a matching size as complete (`:497-506`). A failed Fedora attempt followed by choosing Alpine at the same index resumes onto Fedora's bytes. Arch/Ubuntu are saved by the checksum (mismatch deletes the file, `:364-367`); the five unverified distros are not, and an extraction failure keeps the tarball (`:387-391`), so a retry can loop on the same bad file. Reasoned from code only; not observed.

**Steps:**
1. Name the partial `new_rootfs_<first 16 hex of pin>.tar` when a pin exists (S3), otherwise `new_rootfs_<first 16 hex of sha256(url)>.tar`.
2. On extraction failure, delete the tarball unless it was hash-verified (`:387-391`).
3. Leave `Util.downloadFile` itself unchanged (its resume logic is covered by `download_resume_test.dart`).
4. Test: two different URLs at the same container index produce different partial paths; a failed unverified extraction removes the file.

**Verification:** CI: `flutter test`. Device: see "Needs device confirmation" F9.

## Task S10: Lock down `X11KeyboardReceiver` (export, socket bounds) and decide on cleartext

**Severity:** LOW · **Effort:** S-M · **Depends on:** F2 (cleartext decision) · **Verification:** CI (manifest check, JUnit) + device
**Ledger:** S10 (02, 03 #18 with its "never retried" claim withdrawn, 03-rc R8)

**Problem:** `AndroidManifest.xml:68-76` declares the receiver `exported="true"` with no permission; `X11KeyboardReceiver.kt:36` binds `127.0.0.1:4720` unauthenticated, so any local app can send show/hide/toggle (it only shows/hides the IME; `process=":x11"`). `reader.readLine()` (`:84`) has no length cap or read timeout and spawns one thread per connection, so a local process can grow memory or pin threads. `serverSocket.reuseAddress = true` is set after the bind (`:53-54`), where it has no effect. (Correction recorded by the critic: `ensureServerStarted` IS retried from `onReceive` at `:27`; the `finally` resetting `serverRunning` is at `:67-72`.) `AndroidManifest.xml:18` sets `usesCleartextTraffic="true"`; all Dart HTTP is https, and only the dead `http://localhost:36082` VNC URL needs it (F2). `Signal9Activity` and `com.termux.x11.MainActivity` are also `exported=true`.

**Steps:**
1. Identify the legitimate senders of the receiver's broadcast (grep the action string). If only in-app, set `exported="false"`; otherwise protect it with a signature-level permission.
2. Bound the socket: cap line length (for example 64 bytes), set a read timeout, cap concurrent connections or use a small thread pool, and move `reuseAddress` before bind.
3. Decide whether the loopback TCP bridge is worth keeping; if not, replace it with an app-private mechanism.
4. After the F2 decision, set `usesCleartextTraffic="false"`, or scope it to localhost with a `network_security_config`.
5. Confirm whether `Signal9Activity` really needs `exported="true"`.

**Verification:** CI: `apkanalyzer manifest print` (or `aapt dump xmltree`) shows `exported=false` and no cleartext flag; JUnit for the bounded reader. Device: `adb shell am broadcast ...` from the shell is rejected; an over-long no-newline stream is dropped.

## Task S14: Escape or validate HiDPI/VirGL/Turnip options before they reach the boot line

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** S14 (02 #11)

**Problem:** `defaultHidpiOpt`/`defaultVirglOpt`/`defaultTurnipOpt` (`lib/settings.dart:68-85`, set at `main.dart:593-599,942-948,970-976`) are concatenated unescaped into `extraOpt` (`lib/workflow.dart:1905,1922,1927`) and then into `getBootCommand` unquoted (`:1956`). Only `defaultVirglCommand` is tokenised and escaped (`virglServerArguments`, `:1861-1873`). Self-inflicted only (user-edited), but a malformed value breaks the boot line.

**Steps:**
1. Reuse the `virglServerArguments` tokenise-and-escape approach for the other three, or validate against an allow-list regex when saving the setting.
2. Test: a value containing quotes, `;` and `$(...)` neither breaks the boot line nor executes.

**Verification:** CI: `flutter test`.

## Task S13: Document (and where possible narrow) the guest's reach into app data

**Severity:** LOW (informational) · **Effort:** S (document) / M (narrow mounts) · **Depends on:** S5 · **Verification:** device
**Ledger:** S13 (02 #10)

**Problem:** `lib/workflow.dart:1438-1443` binds `/data`, `/storage`, `/system`, `/apex` into the guest, and `_commonUserSetup` (`lib/distros.dart`) gives the guest user `NOPASSWD:ALL` sudo and a polkit YES rule. Inside proot this is the app's own uid, so it is not a new privilege boundary by design, but any guest package (including the hash-less quick-command .debs, S5) can read the app's SharedPreferences and other containers' `containers/` trees. Reach is a runtime hypothesis.

**Steps:**
1. State this trust model in the README/SECURITY notes.
2. Check why each bind is needed; drop `/apex` and `/system` binds nothing in the guest uses, and consider narrowing `/data` to the paths actually required.
3. Confirm on a device whether the guest can actually read the app's `shared_prefs` (see device list).

**Verification:** device.

---

# Phase 2: runtime-breaking bugs and correctness

## Task F4: Fix the mic-streaming JNI symbol/package mismatch

**Severity:** MEDIUM (static VERIFIED; crash rt-U) · **Effort:** S · **Depends on:** pairs with F19/F20; the feature stays dead until F3 ships `tiny_virtual_mic` · **Verification:** CI (symbol check) + device
**Ledger:** F4 (03-rc R1)

**Problem:** `android/app/src/main/cpp/native-socket.cpp:16,48,60,75` define `Java_com_example_tiny_1computer_AudioStream_nativeInit/Accept/Send/Close`, but the class is `com.daripper91.daripped.AudioStream` (`AudioStream.kt:1,9`; `build.gradle` namespace/applicationId `com.daripper91.daripped`). Expected symbols are `Java_com_daripper91_daripped_AudioStream_*`. `System.loadLibrary("native-socket")` (`AudioStream.kt:11`) would succeed, then the first native call would throw `UnsatisfiedLinkError`; `startStreaming` calls `nativeInit` inside a bare `Thread { }` (`:28-30`) with no catch, and `stopStreaming` calls `nativeClose()` on the platform thread (`:95`). Entry point is the Settings toggle at `lib/main.dart:1154-1183`. The crash itself was not observed.

**Steps:**
1. Rename the four functions in `native-socket.cpp` to `Java_com_daripper91_daripped_AudioStream_nativeInit/Accept/Send/Close`.
2. Catch `UnsatisfiedLinkError` (and other `Throwable`) around the native calls at `AudioStream.kt:28-30` and `:95`, and report the failure to Dart instead of killing the process.
3. Decide with F3 whether to keep the toggle visible while the guest side (`tiny_virtual_mic`) is not shipped; hide it until it is.
4. Add a CI check that exports the shared library's dynamic symbols and asserts the four expected names exist and no `com_example` names remain.

**Verification:** CI: after `flutter build apk --debug`, `nm -D --defined-only` on the built `libnative-socket.so` shows the four `Java_com_daripper91_daripped_AudioStream_*` symbols and no `com_example`. Device: toggle audio streaming and watch logcat (see device list).

## Task F3: Ship, or stop referencing, the guest commands and files the app calls

**Severity:** MEDIUM (static VERIFIED by grep and tar listing; runtime rt-U) · **Effort:** L if shipping artifacts, M if removing references · **Depends on:** owner decision per item; F2 (stopvnc/startvnc) · **Verification:** CI (path-existence test) + device
**Ledger:** F3 (02 #3, 03-rc R4). Related: earlier plan D5.

**Problem:** The app references guest commands/files that no asset ships. `stopvnc` (Power Off quick command, `lib/workflow.dart:791,859`, and the pacman defaults) and `startvnc`; `cmatrix` and `tiny_virtual_mic` mounts (`workflow.dart:1941-1942`; `patch.tar.gz` holds only `tiny_virtual_mic.c`); `getifaddrs_bridge_client_lib.so` (source only, so `workflow.dart:1892-1895` silently never enables the bridge); `freedreno_icd.aarch64.json` (`settings.dart:78` Turnip default); `tiny/font`. The Hangover buttons call `~/.local/share/tiny/extra/install-hangover[-stable]` (`main.dart:1051,1063`) and the Wine "Fix CJK" commands run `regedit Z:\home\tiny\.local\share\tiny\extra\chn_fonts.reg` (`workflow.dart:1273,1315`), but `patch.tar.gz` ships them under `tiny/cross/`, so the `extra/` path does not exist. (The correction from 03-rc R4: the reg file is under `tiny/cross/`, not `tiny/`.)

**Steps:**
1. For each item, decide: build and ship (cross-compile `tiny_virtual_mic` and the getifaddrs client from the sources in `patch.tar.gz`, add `cmatrix`/font/Turnip assets) or remove the reference and the UI that depends on it.
2. Fix the path mismatches without shipping anything new: point the Hangover buttons (`main.dart:1051,1063`) and the `chn_fonts.reg` calls (`workflow.dart:1273,1315`) at `tiny/cross/`, or copy `cross/*` into `extra/` during bootstrap (`workflow.dart:1537-1551`).
3. Replace the `stopvnc` Power Off command with something that exists in the guest once the F2 decision is made.
4. Add a test that scans `lib/` for guest paths of the form `.local/share/tiny/extra/...` and asserts each exists in the shipped asset listing (the repo's tests already shell out to `tar`; add a `Platform.isLinux` skip, see F38).
5. Regenerate `patch.tar.gz` (F31) after the layout decision.

**Verification:** CI: the new path-existence test. Device: see "Needs device confirmation" F3.

## Task F1: Wire up or remove the per-container startup-command (`boot`) setting

**Severity:** MEDIUM (dead setting VERIFIED; "upstream used to launch it" clause UNVERIFIED) · **Effort:** M to wire, S to remove · **Depends on:** owner decision · **Verification:** CI
**Ledger:** F1 (02 #1)

**Problem:** `lib/main.dart:300-316` and `:243-246` let the user edit/reset the per-container `boot` command, but nothing reads it: the only `getCurrentProp("boot")` hit is the settings text field. `launchCurrentContainer` (`lib/workflow.dart:1956`) always uses `Workflow.getBootCommand(...)`. The helper text and `shellCommandWarning` promise an effect that does not exist. Containers also carry a frozen copy of the boot string (`workflow.dart:1731`, `container_installer.dart:497`).

**Steps:**
1. Decide: (a) wire it, or (b) remove the field, its reset handler and the warning text.
2. If (a): read `Util.getCurrentProp("boot")` in `launchCurrentContainer` (`:1956`). Because existing containers hold a frozen default (`:1731`, `:497`), store only user overrides (empty means "use `getBootCommand`") or those frozen strings would become authoritative and mask later fixes to `getBootCommand`.
3. If (b): delete `main.dart:300-316` and `:243-246`, the strings, and the `boot` prop write at creation.
4. Test: `launchCurrentContainer` uses the override when set and the default otherwise.

**Verification:** CI: `flutter test`, `flutter analyze`.

## Task F2: Decide the dead VNC/AVNC/browser display path: remove (recommended) or restore

**Severity:** MEDIUM (no server installed VERIFIED; runtime consequence rt-U) · **Effort:** L · **Depends on:** owner decision; unblocks S10 (cleartext), F3 (`stopvnc`), F18, F24, F29, S12 · **Verification:** CI + device
**Ledger:** F2 (02 #2, #5; 03 #14, #25)

**Problem:** `assets/scripts/start-desktop` (546 lines) has zero "vnc" matches, and `lib/desktop_environments.dart` / `lib/distros.dart` install no VNC server or noVNC (only the legacy `extra/build-arch-rootfs.sh` does). Yet the app keeps `useAvnc`, `avncResizeDesktop`, `avncScaleFactor`, `vncUrl` (localhost:36082), `vncUri` (5904), `autoLaunchVnc` branches, `waitForConnection`/`launchBrowser`/`launchAvnc` (`workflow.dart:1971-2026`, `main.dart:2419-2425`), the share-link button (`main.dart:354-397`) and a resolution editor that runs `sed ... $(command -v startvnc)` (`main.dart:735`). Toggling `useX11` off (`main.dart:843`) yields a display path with no server behind it (the "can never connect" outcome is not observed). `launchGUIBackend` (`workflow.dart:1960-1969`) also types `bash /etc/X11/xinit/xinitrc &> ~/.vnc/x.log &` into the pty although `start-arch.sh:27-32` already `exec`s `start-desktop`, and no installed package provides that xinitrc path. README states the in-app X server is the display.

**Steps:**
1. Owner decides. Recommended: remove, since README documents the in-app X server and restoring needs a per-distro VNC server plus shipped `startvnc`/`stopvnc` (F3).
2. If removing: delete the `useAvnc`/`avncResizeDesktop`/`avncScaleFactor`/`vncUrl`/`vncUri`/`autoLaunchVnc` settings and UI, `waitForConnection`/`launchBrowser`/`launchAvnc`, the share-link button, the `startvnc` resolution editor, the `useX11` toggle, and the typed xinitrc line (`workflow.dart:1960-1969`); drop the `avnc_flutter` and `webview_flutter` dependencies after confirming nothing else uses them (F29); stored prefs keys can stay orphaned.
3. If restoring: install a VNC server per distro in the package lists and ship `startvnc`/`stopvnc`; add a test that the packages are present in each family's list.
4. Remove the `~/.vnc` creation on the host side.

**Verification:** CI: `flutter analyze`, `flutter test`, `git grep -in vnc lib` returns only intended hits. Device: the default X11 launch still reaches the desktop; no `~/.vnc` is created.

## Task F5: Register added containers with the correct package manager and quick commands

**Severity:** MEDIUM · **Effort:** M · **Depends on:** none · **Verification:** CI
**Ledger:** F5 (03 #3)

**Problem:** `ContainerInstaller._registerContainer` (`lib/container_installer.dart:491-506`) builds `ContainerInfo(...)` without `packageManager` (default `'pacman'`, `lib/models.dart:40`, serialised at `:123`) and with `commands: []`. The first-run path does it right (`workflow.dart:1719-1737` uses `D.getCommandsForPackageManager`), so a Fedora/Debian/Alpine container added later is mis-tagged with an empty quick-command bar. The long-press reset (`main.dart:2323-2326`) always writes `D.commands`/`D.commands4En` (pacman lists) regardless of distro. No test touches `_registerContainer`/`install()` success.

**Steps:**
1. Derive `packageManager` from the chosen distro spec and pass it, and `commands: D.getCommandsForPackageManager(pm, english: ...)`, in `_registerContainer`.
2. Make the reset action (`main.dart:2323-2326`) use the current container's package manager.
3. Add tests for the `install()` success path asserting `packageManager` and a non-empty command list for Fedora, Debian and Alpine, and for the reset action.

**Verification:** CI: `flutter test`.

## Task F6: Fix default quick commands that cannot work as shipped

**Severity:** MEDIUM (a, b VERIFIED; c UNVERIFIED) · **Effort:** S · **Depends on:** none · **Verification:** CI + device
**Ledger:** F6 (03 #4)

**Problem:** (a) Boot runs as uid 1000 (`--change-id=1000:1000`, `workflow.dart:1434`), yet the zh pacman default "更新和升级" is a bare `pacman -Syu --noconfirm` (`workflow.dart:898`; the English list and `D.commands` use sudo), so it fails as non-root. (b) `neofetch -L && neofetch --off` ("System Info", in every list: `workflow.dart:698,801,900,987,1050,1136`) but no first-boot or DE list installs neofetch (`distros.dart`, `desktop_environments.dart`). (c) `_debInstall` uses `wget` (`workflow.dart:683-684`) and the Arch first boot installs only `sudo dbus xorg-xauth xorg-xkbcomp xkeyboard-config ttf-dejavu adwaita-icon-theme librsvg` (`distros.dart:266`); whether the ALARM base ships wget is UNVERIFIED.

**Steps:**
1. Add `sudo` to the pacman command at `workflow.dart:898`.
2. Install neofetch in the first-boot package lists, or remove the command.
3. Confirm `wget` presence on a device (see list); if absent, add it to the Arch first-boot package set (`distros.dart:266`).
4. Test: every shipped pacman quick command that modifies the system starts with `sudo`; every tool a quick command invokes is in a package list.

**Verification:** CI: `flutter test`. Device: see "Needs device confirmation" F6.

## Task F8: Stop swallowing errors on core config reads and service start/stop

**Severity:** MEDIUM (code facts VERIFIED; the "invisible to Dart" Android 12+ claim UNVERIFIED) · **Effort:** M · **Depends on:** none · **Verification:** CI + device
**Ledger:** F8 (03 #6)

**Problem:** `Util.getGlobal` returns `null` on any exception (`lib/workflow.dart:260-265`) while callers cast `as bool`/`as int`/`as String` (e.g. `main.dart:544,467`; `workflow.dart:2104`), turning a root cause into an unrelated `TypeError`. `Util.getCurrentProp` has `catch (_) { return _getDefaultProp(key); }` (`workflow.dart:317-319`): a corrupt or out-of-range `containersInfo` (for example after the non-atomic delete, F10) silently yields default name/boot/commands. `startContainerForegroundService`/`stop...` are `catch (_) {}` (`workflow.dart:2040,2046`), and `ContainerSessionService.start` logs and swallows `Throwable` (`ContainerSessionService.kt:165-167`) while `MainActivity.kt:27-28` replies `result.success(0)`.

**Steps:**
1. Log (boot log or `debugPrint`) every caught exception in `getGlobal`/`getCurrentProp`; for `getGlobal`, return a typed default or rethrow with context.
2. Log the swallowed errors at `workflow.dart:2040,2046`.
3. In Kotlin, return a channel error from `MainActivity.kt:27-28` when `ContainerSessionService.start` fails, and surface it in Dart.
4. Tests: a corrupt `containersInfo` is logged and the fallback is visible; a service-start failure reaches Dart.

**Verification:** CI: `flutter test`. Device: see "Needs device confirmation" F8.

## Task F10: Make container delete/renumber crash-consistent (or give containers stable IDs)

**Severity:** LOW-MED · **Effort:** M (consistency) to L (stable IDs) · **Depends on:** none · **Verification:** CI
**Ledger:** F10 (02 verdict; 04 #6 caveat)

**Problem:** `lib/container_manager.dart:126-166`: `delete()` runs the files-first `rm` then `mv` chain under `set -e` and only afterwards rewrites prefs (`containersInfo`, `defaultContainer`, `currentContainer`, `:157-165`). A failure mid-chain leaves folders renumbered but prefs not, so entries point at the wrong rootfs. The ordering of the moves is sound and `blockedReason` forbids deleting index <= current or default. There is no test for a mid-failure.

**Steps:**
1. Minimum: on a non-zero script exit, do not touch prefs and report which folders moved; better, write a pending-delete journal to prefs before the file moves and reconcile it at startup.
2. Preferred longer-term: name container folders by a stable id (no renumbering), with a one-time migration of existing `containers/<n>` folders.
3. Add a test to `test/container_manager_test.dart` that makes one `mv`/`rm` fail mid-chain (a PATH shim or read-only target) and asserts prefs and folders stay consistent.

**Verification:** CI: `flutter test` (new failure-injection test).

## Task F7: Mark the setup shell dead and give the install page a cancel

**Severity:** LOW-MED (read VERIFIED; runtime rt-U) · **Effort:** M · **Depends on:** none · **Verification:** CI + device
**Ledger:** F7 (03 #5). Narrows the still-open part of earlier plan A5.

**Problem:** `SetupSession` completes the pending run with -1 only from the one-shot `pty.exitCode.then` (`lib/setup_session.dart:31-34`). If the shell dies (the user types `exit` in the interactive terminal wired at `:27`), later cleanup `run`s from `install()`'s catch (`container_installer.dart:131-136`) and `installBase`'s catch (`:387-391`) write to a dead pty and `pending.future` never completes (no `_dead` flag). `ContainerInstallPage` blocks back while running (`PopScope(canPop: !running)`, `container_install_page.dart:76`) and has no Cancel. No test covers `SetupSession.run` (only `parseExitMarker`).

**Steps:**
1. Set a `_dead` flag in the `exitCode` handler; make `run()` return -1 immediately when dead.
2. Add a Cancel action to `ContainerInstallPage` that terminates the shell and pops; allow back when the shell is dead.
3. Add a seam (fake PTY) and tests: exit mid-run, run-after-exit returns -1 without hanging.

**Verification:** CI: `flutter test`. Device: see "Needs device confirmation" F7.

## Task F11: Stop `ContainerSessionService` restarting itself with no container and an untimed wake lock

**Severity:** LOW-MED (read VERIFIED; runtime rt-U) · **Effort:** S · **Depends on:** none · **Verification:** device
**Ledger:** F11 (03-rc R3)

**Problem:** `ContainerSessionService.kt:26-35` returns `START_STICKY` and treats a null intent as `ACTION_START` (`intent?.action ?: ACTION_START`). After a process kill Android re-delivers a null intent, so the service re-posts the "IntelNode Desktop Active" notification and calls `acquire()` with no timeout (`:65-72`) although no container or X server exists, until the user taps Stop. `MainActivity.kt:43` starts the service before validating `tmpdir/xkb/xserverArgs` (`:44-48`), so an `INVALID_ARGUMENTS` call still starts it. The stop path `context.startService(...)` (`:175`) from background on Android 8+ throws `IllegalStateException`, caught and only logged (`:176-178`).

**Steps:**
1. Treat a null intent as stop (`stopSelf()` and `START_NOT_STICKY`), or return `START_NOT_STICKY`.
2. Use a timed `acquire(timeout)` with renewal while a container runs.
3. Validate arguments in `MainActivity.kt` before starting the service.
4. Use `stopService` (or an explicit stop action) instead of `startService` for stopping.

**Verification:** device: see "Needs device confirmation" F11.

## Task F12: Make `to_vault` executable and stop hardcoding device metadata

**Severity:** LOW-MED (MEDIUM only if EACCES is confirmed on a device) · **Effort:** S · **Depends on:** F31 (archive modes) · **Verification:** device (decisive) + CI string test
**Ledger:** F12 (03 #1, R14)

**Problem:** `assets/scripts/to_vault` is copied via `Util.copyAsset` -> `File.writeAsBytes` (`lib/workflow.dart:71-75,1548-1551`) and bind-mounted as `/usr/local/bin/to_vault` (`:1943`). The only chmods in `lib/` cover `bin/*`, `libexec/proot/*` and `tmp` (`workflow.dart:1646-1648`). The repo's own comment (`assets/scripts/start-arch.sh:28`) says the app copies assets without the executable bit, which is why `start-desktop` is run via `/bin/bash`. So the documented `cat findings.txt | to_vault "X"` (MANUAL.md:100) would hit EACCES; EACCES was not observed on a device. Every entry in `assets/patch.tar.gz` is mode 0644 too. `to_vault:17-18` hardcodes `device: Pixel_10_Pro` and `os: Android_Cinnamon_Bun` into every note.

**Steps:**
1. First confirm EACCES on a device (see list); if not reproduced, downgrade to LOW and do only step 3.
2. Add `chmod +x` for `tiny/extra/*` next to `workflow.dart:1646-1648` (or invoke via `bash`).
3. Replace the hardcoded metadata in `to_vault` with values read at run time (`getprop` or env), or drop the fields.
4. Test: the bootstrap command string includes the chmod for `tiny/extra`.

**Verification:** device: `echo hi | to_vault T` works; CI: string-level bootstrap test.

## Task S12: Remove the hardcoded VNC password and LAN-exposed VNC from the legacy builder

**Severity:** LOW (dormant) · **Effort:** S · **Depends on:** F2, F31, F24 · **Verification:** CI grep
**Ledger:** S12 (02 #9)

**Problem:** `extra/build-arch-rootfs.sh:309` pipes a fixed password into `vncpasswd` and starts `vncserver ... -localhost no` (about `:304-312`), exposing VNC on the LAN. The same script ships inside `assets/patch.tar.gz` (`tiny/build-arch-rootfs.sh`), and `lib/workflow.dart:289-304` still migrates the legacy constant password. Not wired into CI or the live install, so dormant.

**Steps:**
1. If the F2 decision is "remove", delete the VNC block (or the whole legacy script) and its copy in `patch.tar.gz`; if the script stays, generate a random password and bind `-localhost yes`.
2. Remove or rewrite the legacy-password migration in `workflow.dart:289-304` (see F24).

**Verification:** CI: `git grep -n vncpasswd extra assets lib` returns nothing; `tar -xzOf assets/patch.tar.gz` of the legacy script no longer contains the password.

## Task F14: Do not gate the whole app on storage permission, and ask for it before the install

**Severity:** LOW · **Effort:** S-M · **Depends on:** none · **Verification:** CI + device
**Ledger:** F14 (02 #8)

**Problem:** `lib/workflow.dart:2092-2095` throws if neither storage permission is granted, after `initData()` has already done the first-run download and install (`:1788-1790`). Storage is only needed for the optional `/storage` mounts. Denying gives a hard error plus a Retry that re-runs `initData` and re-launches the X server (`:1808-1810`, unawaited).

**Steps:**
1. Do not throw on denial; skip the `/storage` mount when not granted.
2. Request the permission lazily (when a storage-dependent feature is first used) rather than after install.
3. Guard Retry so it does not relaunch an already-running X server.

**Verification:** CI: `flutter test` for the denied path with a fake permission handler. Device: see list.

## Task F15: Replace the side-effect first-run marker with an explicit flag

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** F15 (02 #7)

**Problem:** `workflow.dart:1788` decides first run via `!G.prefs.containsKey("defaultContainer")`, and `GlobalSettings.defaultContainer` (`settings.dart:15-16`) writes the default on first read; `container_delete_dialog.dart:14` and `workflow.dart:1792` read it. The "desktop selection cancelled" early return (`:1703-1706`) returns normally, then `:1792` sets the marker with no `containersInfo` and no desktop, leaving a bare base that boots default props forever. The picker blocks back/dismiss (`desktop_picker.dart:72-76`), so reachability is UNVERIFIED and likely low.

**Steps:**
1. Introduce a dedicated `firstRunComplete` key, written only after the setup path succeeds.
2. Make `defaultContainer`'s getter side-effect free.
3. Test: a cancelled picker does not set the marker.

**Verification:** CI: `flutter test`.

## Task F16: Remove write-only `selectedDE` and unused `lastDate`

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** F16 (02 #4). Related: earlier plan A6.

**Problem:** `selectedDE` is written at `lib/workflow.dart:1715` with a getter at `settings.dart:61,172` but is never read (the real session choice lives in `~/.intelnode-session`). `lastDate` is never read or written outside `settings.dart`.

**Steps:**
1. Delete the `selectedDE` write and getter, and `lastDate`.
2. Confirm with `flutter analyze` and `flutter test`.

**Verification:** CI: `git grep -n 'selectedDE\|lastDate' lib test` returns nothing.

## Task F17: Make the audio-port setting actually control the guest client port

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** F17 (03 #13)

**Problem:** `defaultAudioPort` (`main.dart:467-480`, validator allows 0) changes PulseAudio's TCP module port through `sed s/4713/<port>/` (`workflow.dart:1852`), but the guest client is hardcoded to `PULSE_SERVER=tcp:127.0.0.1:4718` in the boot line (`:1502`) and `start-desktop:6`. Any value other than 4718 silently kills audio.

**Steps:**
1. Derive the boot-line and `start-desktop` port from the setting (env var), or remove the setting.
2. Test: a custom port appears consistently in the boot line and the server config.

**Verification:** CI: `flutter test` on the generated boot command.

## Task F18: Await or handle the unawaited futures in the launch path

**Severity:** LOW · **Effort:** S · **Depends on:** F2 (most of this path may be deleted) · **Verification:** CI
**Ledger:** F18 (03 #14; runtime rt-U)

**Problem:** `lib/workflow.dart:2107-2108` calls `launchGUIBackend(); launchX11();` unawaited (errors become unhandled async errors; `launchX11` can throw from the plugin). `:2112` `waitForConnection().then(...)` has no `onError`, so `retry` raising `RetryException`/`TimeoutException` goes unhandled. `launchBrowser` pushes a route on `G.homePageStateContext` (`:1987`) after async gaps with no `mounted` check, hidden by the file-wide `// ignore_for_file: use_build_context_synchronously` (`:18`).

**Steps:**
1. After F2, handle what remains: `await` or wrap in `unawaited(...catchError(...))` with logging.
2. Remove the file-wide ignore and fix the sites the analyzer then flags.

**Verification:** CI: `flutter analyze` clean without the ignore.

## Task F19: Reply to `startStreaming`/`stopStreaming`, remove the `!!`, gate the debug env

**Severity:** LOW · **Effort:** S · **Depends on:** F4 · **Verification:** device
**Ledger:** F19 (03 #15)

**Problem:** `MainActivity.kt:80-85` calls `AudioStream` for `startStreaming`/`stopStreaming` but never calls `result.success/error/notImplemented`, so the Dart futures (`main.dart:1162,1178`, not awaited) never complete. `call.argument("path")!!` (`MainActivity.kt:81`) is the only `!!` in the Kotlin/Java sources. `AudioStream.stopStreaming` joins the recording thread on the platform thread (`AudioStream.kt:96-100`). `MainActivity.kt:53` sets `TERMUX_X11_DEBUG=1` unconditionally, including release.

**Steps:**
1. Reply on both branches (`result.success(null)` or an error).
2. Replace the `!!` with a null check returning `INVALID_ARGUMENTS`.
3. Move the join off the platform thread.
4. Set `TERMUX_X11_DEBUG` only when `BuildConfig.DEBUG`.

**Verification:** device: toggle streaming; no hang; logcat clean.

## Task F20: Harden `AudioStream` state handling and the JNI helpers

**Severity:** LOW · **Effort:** S-M · **Depends on:** F4 · **Verification:** device / JUnit where practical
**Ledger:** F20 (03-rc R2)

**Problem:** `AudioStream.kt:14` `isStreaming` is a plain `var` shared across threads; the `sent < 0 -> break` path (`:81`) leaves it `true` (cleanup `:86-88` does not reset it) so a later start returns early at `:25`; `AudioRecord.getMinBufferSize` error codes feed `ByteArray(bufferSize)` unchecked (`:47-61`); `recorder.startRecording()` on an uninitialised recorder throws uncaught on the worker thread; `recorder.read` returning <= 0 loops without sleeping (`:69-74`, `:77-83`). In `native-socket.cpp`: unsynchronised `server_fd`/`client_fd` globals (`:18-19`), `GetStringUTFChars` buffer leaked on the failure returns (`:22,:34,:40`), and `memset`/`strncpy`/`strerror` used without `<cstring>`.

**Steps:**
1. Mark `isStreaming` `@Volatile` and reset it on every exit path.
2. Validate the buffer size and recorder state; catch `startRecording` failures.
3. Back off or break on `read <= 0`.
4. In C++: release the UTF chars on all returns, guard the fds, add `<cstring>`.

**Verification:** device: start, stop, restart streaming repeatedly; CI: native build compiles.

## Task F21: Replace substring flag parsing and the `$ACTION` shell splice

**Severity:** LOW · **Effort:** S-M · **Depends on:** S4 (covers the checksum/tar-flag parts) · **Verification:** CI + device
**Ledger:** F21 (03 #16c-e, R5)

**Problem:** (c) `workflow.dart:870-888` `getCommandsForPackageManager` uses `contains('apt'|'leap'|'void'|...)` on a free string (latent, enum-fed today). (d) `start-desktop:478-482` AT-SPI monitor greps `"focused"` then `"1"`/`"0"` on the next dbus-monitor line (substring match on any digit; every focused widget, not only text fields, may fire `intelnode-ime show`; UNVERIFIED). (e) `start-desktop:117-119` `intelnode-ime` splices `$ACTION` into `bash -c "printf ... '$ACTION' ..."`, so a quote breaks out (local, user-supplied only).

**Steps:**
1. Make `getCommandsForPackageManager` take the enum (or an exact string) and match exactly.
2. Validate `$ACTION` against `show|hide|toggle` before the `bash -c`.
3. Tighten the AT-SPI filter to the actual event and value fields; confirm on a device that non-text focus does not pop the IME.
4. Shell test: `intelnode-ime "x'; touch p; '"` runs nothing.

**Verification:** CI: `bash -n` plus a shell/Dart test of the validation; device for the AT-SPI behaviour.

## Task F22: Stop `start-desktop` rewriting user config on every launch

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** device
**Ledger:** F22 (03 #17, R12)

**Problem:** `start-desktop` unconditionally rewrites `~/.config/gtk-3.0/settings.ini` (`:272`), `~/.gtkrc-2.0` (`:279`), the xfce4 power-manager (`:288`), screensaver (`:310`) and session (`:335`) XML on every launch. The openbox/lxqt `rc.xml` is replaced only when it lacks `<application class=` (`:146`); the generated file contains that string (`:185`) so it is not rewritten after the first launch. `sudo -n ln -sf /bin/true /usr/bin/xflock4` replaces a package-owned binary. The screen lock is deliberately neutered (`:339`, a design choice for a phone; leave it).

**Steps:**
1. Write each file only if absent, or guard with a version marker.
2. Do not overwrite a package-owned `xflock4`; install a shim earlier on `PATH` instead.

**Verification:** device: customise a setting, relaunch, confirm it persists.

## Task F24: Fix the operator-precedence bug in the legacy VNC-password migration

**Severity:** LOW · **Effort:** S · **Depends on:** F2 (may delete the migration) · **Verification:** CI
**Ledger:** F24 (03 #20)

**Problem:** `workflow.dart:276-281` is `(keyIsVnc && !info.hasProp("vncPassword")) || (info.hasProp("vncPassword") && getProp.isEmpty)`. `ContainerInfo.hasProp('vncPassword')` is always true (`models.dart:192-193`), so the first arm is dead and the second ignores `key`: for any container whose `vncPassword` is `''` (for example legacy JSON, default at `models.dart:106`), every `getCurrentProp(<any key>)` generates a password and fires an unawaited `addCurrentProp` read-modify-write of `containersInfo` (`:282-304`). Real containers carry a random password, so it is rarely hit; the "migrate the legacy constant" intent never triggers for non-empty legacy passwords.

**Steps:**
1. If F2 removes VNC, delete the migration entirely.
2. Otherwise: `keyIsVnc && (getProp.isEmpty || getProp == <legacy constant>)`.
3. Test: a non-vnc key read with an empty `vncPassword` performs no write.

**Verification:** CI: `flutter test`.

## Task F27: Confirm destructive quick commands and key FastCommands by id

**Severity:** LOW · **Effort:** S-M · **Depends on:** F5 (package-manager gating) · **Verification:** CI + device
**Ledger:** F27 (03 #23, R10)

**Problem:** `main.dart:1084` `rm -rf ~/.wine` and `:1075` `sudo pacman -Rns --noconfirm hangover*` fire straight into the terminal on tap, and the Wine/Hangover panel is shown for all containers though the commands are pacman-only. `FastCommands` runs commands immediately (`:2084`), including shipped `rm -rf`/uninstall entries; edit/delete use a list index captured at build (`e.key`) against a freshly read list (`:2155,:2178`), and `setState` follows an `await` before the `mounted` check (`:2153-2160,:2176-2184,:2285-2292,:2321-2330`, where the guard checks the dialog context, not the State).

**Steps:**
1. Add a confirm dialog (existing project mechanism) before destructive shipped commands.
2. Show the Wine/Hangover panel only for pacman containers.
3. Key edit/delete by a stable command id, not a captured index; check the State's `mounted` after awaits.

**Verification:** CI: widget test for the confirm; device spot-check.

## Task F28: Stop the fake progress bar from advancing after failure

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** F28 (03 #24)

**Problem:** `FakeLoadingStatus` (`main.dart:130-165`) is an asymptotic timer unrelated to real progress and keeps advancing while `G.startupFailed` is true (`main.dart:1869-1882`).

**Steps:**
1. Stop the timer (or show an indeterminate indicator) when `G.startupFailed` is set.
2. Widget test: after failure the displayed value stops changing.

**Verification:** CI: `flutter test`.

## Task F36: Replace silent id fallbacks and free-text package-manager classification

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** F36 (03-rc R6, R7)

**Problem:** `desktop_environments.dart:428-429` and `distros.dart:454-455` use `orElse: () => all.first`, so an unknown id silently becomes XFCE or the first distro. `models.dart:54-72` `packageManagerForDistro` matches unanchored regexes (`kali`, `trixie`, `void`, `opensuse`, ...) against the user-editable container name when the stored `packageManager` is missing or invalid (apt is tested first, so "avoid-debian-test" resolves by substring order); today `toJson` always writes `packageManager` (`models.dart:123`), so only legacy or hand-edited JSON reaches it. `models.dart:40` `this.additionalProps = const {}` plus `setProp`'s default branch (`:178-180`) would throw `UnsupportedError` for a constructor-built object given an unknown key (latent; the one non-test constructor call never calls `setProp`). `DesktopEnvironments.byId` has no caller in `lib/`; `Distros.byId` is used by tests.

**Steps:**
1. Make `byId` return null or throw on an unknown id.
2. Classify the package manager only from the stored id; do not infer it from the name.
3. Use `Map.of(...)`/a mutable default for `additionalProps`.

**Verification:** CI: `flutter test`.

## Task F37: Android overlay/IME polish: accessibility, scale label, silent reflection catches

**Severity:** LOW · **Effort:** S-M · **Depends on:** none · **Verification:** device
**Ledger:** F37 (03-rc R9; Signal9Activity and MainApplication notes)

**Problem:** `X11FloatingOverlay.kt:114-132` `createActionButton(label, tooltip, ...)` ignores `tooltip`, so no button has a content description. The scale button label is hardcoded "150%" with `scaleIndex = 2` (`:147,:287`) regardless of the real displayScale; the overlay is rebuilt on activity recreation (`:304-312`); `MainApplication.kt:58-88` re-forces `adjustResolution`/`displayStretch`/`forceOrientation` on layout changes, which may fight the scale choice (whether Termux:X11 honours the broadcast is not checkable here). `openPreferences` falls back to an implicit, package-less broadcast (`:268-271`). Every reflective lookup into `com.termux.x11.*` catches `Throwable` silently (`X11KeyboardReceiver.kt:136-138,145-147,197-200`; overlay `:268,:281`; `MainApplication.kt:74-110`), so a renamed plugin method silently degrades the keyboard button. `Signal9Activity.kt:57-58` has no `ActivityNotFoundException` handling.

**Steps:**
1. Set `contentDescription` from `tooltip`.
2. Initialise the scale label from the actual value; persist `scaleIndex` across recreation.
3. Always set the package on the preferences broadcast.
4. Log reflection failures once.
5. Catch `ActivityNotFoundException` in `Signal9Activity`.

**Verification:** device: TalkBack reads the buttons; scale label matches.

## Task F40: Make the desktop theme settings match the packages actually installed

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** device
**Ledger:** F40 (03-rc R12b)

**Problem:** `start-desktop:257-267` writes `theme=frost` and `icon_theme=Papirus` into `lxqt.conf`, but no package list installs a Papirus icon theme (`git grep -in papirus lib assets` hits only `start-desktop:262`), and `lxqt-themes` appears only in the dnf list (`desktop_environments.dart:112`); whether the other families' lxqt packages pull `frost` is UNVERIFIED. The openbox rules at `:185-210` place wildcard `class="*"` rules before the dialog/splash rules; which wins is Openbox matching behaviour (UNVERIFIED).

**Steps:**
1. Add the missing theme packages to the per-family LXQt lists, or point the config at themes that are installed.
2. After a device check, reorder the openbox rules if the dialog/splash rules do not take effect.

**Verification:** device: after an LXQt install, the themes resolve.

---

# Phase 3: CI, versioning and tests

All workflow edits in this phase are **[PROTECTED]**.

## Task S8: Stop signing debuggable APKs with the production key and publishing them to the rolling release

**Severity:** LOW (critic downgrade from MEDIUM; the exposure arguments are inference) · **Effort:** S-M · **Depends on:** S6; owner answer on who consumes debug APKs · **Verification:** CI · **[PROTECTED]**
**Ledger:** S8 (03 #8). Related: earlier plan C5.

**Problem:** `android/app/build.gradle:86` signs the `debug` build type with the release key whenever `keystore.properties` exists. `debug-build.yml` restores `KEYSTORE_BASE64` on every push to `wip/**`/`rebase/**`/`debug/**` and uploads the APK; `flutter-build.yml:91-103` attaches `app-debug.apk` to the `latest-build` release. A debuggable build (run-as access to app data) then carries the production signing identity, and the signing secrets are reachable from any branch workflow edit. Both claims ("run-as exposure", "collaborator secret exposure") are inference; anyone who can push a branch can already push a `v*` tag (S6).

**Steps:**
1. Ask who uses the published debug APKs. Warn that switching signing identities makes in-place upgrades fail (signature mismatch forces an uninstall and loses the proot rootfs), so the change needs a release note.
2. Sign debug builds with the default debug keystore only; remove the keystore restore from `debug-build.yml` and the debug path of `flutter-build.yml`.
3. Publish debug APKs only as a pre-release or workflow artifact.

**Verification:** CI: `apksigner verify --print-certs` on the debug artifact shows the debug cert.

## Task S7: Fix the "Latest" release pointing at a manually uploaded debug APK

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** `gh` read (not CI)
**Ledger:** S7 (02-recheck K2)

**Problem:** `gh` shows `v2.2.6-debug.2` as GitHub "Latest" with `prerelease=false`; the release and both `*-debug*` APK assets (about 1.47 GB and about 66 MB) were created and uploaded by the repo owner (the second attached after publication), not by `github-actions[bot]`. It is a manual-publish hygiene issue; it is not evidence that `release.yml` produced it (that claim is withdrawn). Data came from `gh` and was not re-run by the critic.

**Steps:**
1. Re-check with `gh release view v2.2.6-debug.2 --json isPrerelease,author,assets`.
2. Owner action: mark it as a pre-release and make a real release "Latest" (or delete it); the release is outward-facing, so the owner does this.
3. Adopt a convention: debug builds are always published as pre-releases.

**Verification:** `gh api repos/DaRipper91/IntelNode/releases/latest --jq .tag_name` returns a non-debug tag.

## Task F32: Align `pubspec.yaml` version with the tags and derive it in CI

**Severity:** LOW · **Effort:** S · **Depends on:** S6 · **Verification:** CI · **[PROTECTED]** (workflow edit)
**Ledger:** F32 (02 verdict)

**Problem:** `pubspec.yaml:4` is `version: 2.1.1+2` while tags run v2.0.8..v2.2.7-debug.20261117, so every APK built from this tree reports 2.1.1 / versionCode 2.

**Steps:**
1. Bump `pubspec.yaml` to the intended current version.
2. In `release.yml` pass `--build-name` from the tag (stripping the `v`) and `--build-number` from `${{ github.run_number }}` so versionCode is monotonic.

**Verification:** CI: `aapt dump badging app-release.apk | grep -E 'versionName|versionCode'` matches the tag and run number.

## Task F33: Add a pull-request CI trigger and stop tests from passing vacuously

**Severity:** LOW (critic downgrade from MEDIUM) · **Effort:** S-M · **Depends on:** S1 (to run its JUnit suite) · **Verification:** CI · **[PROTECTED]**
**Ledger:** F33 (03 #7)

**Problem:** `git grep pull_request .github/workflows` has no hits. Triggers are push to `main`, push to `wip/rebase/debug` branches, and `v*` tags, so nothing runs analyze/test on a PR, and `flutter-build.yml` publishes a release on every push to `main`. `test/workflow_test/rootfs_extract_command_test.dart:20-23` returns early (green, asserting nothing) when `busybox`/`unxz` is missing, and `!Platform.isLinux` guards do the same (`native_lib_link_test.dart:15`); whether `ubuntu-latest` has busybox is UNVERIFIED. There are no Kotlin/Java tests (`find android -path '*test*'` is empty).

**Steps:**
1. Add a `pull_request` trigger (or a small `ci.yml`) that runs `flutter analyze` and `flutter test`.
2. Turn early returns into `skip: 'reason'` so skips show in the report, and install `busybox`/`xz` in CI where the test is meant to run.
3. Add the Android unit-test step (`./gradlew :app:testDebugUnitTest`) once S1 adds the first JUnit tests.

**Verification:** CI: open a PR; checks run; the skipped-test count is visible.

## Task F35: Workflow hygiene (stale secret, release flags, WeChat quick command, NDK install retry/cache)

**Severity:** LOW · **Effort:** S-M · **Depends on:** none · **Verification:** CI + `gh` · **[PROTECTED]**
**Ledger:** F35 (02 #12)

**Problem:** The repo secret `GEMINI_API_KEY` exists (names only via `gh`) but no workflow references it. `flutter-build.yml:97-102` sets `prerelease: true` and `make_latest: true` together. The apt "安装微信" quick command (`workflow.dart:1025`) `wget`s a `.png` URL as the `.deb`.

**Steps:**
1. Owner action: delete the unreferenced secret (`gh secret delete GEMINI_API_KEY`) after confirming nothing external uses it.
2. Decide whether the rolling release should be `make_latest`; a pre-release should not be Latest.
3. Fix the WeChat URL or remove the command.
4. NDK step: the only observed release run (`44106400727`, tag `v2.2.7-debug.20261117`) failed in Gradle when installing NDK `27.0.12077973`, after analyze and the 205 tests passed (02-recheck). This is not a separate ledger row and the cause was not diagnosed; add a bounded retry around the NDK/SDK install and cache the SDK/NDK directory, then re-run to see whether it recurs.

**Verification:** CI: a tag-less dry run of the build job installs the NDK; `gh secret list` no longer lists `GEMINI_API_KEY`.

## Task F29: Build hygiene (gradle `git` exec, TODO, unpinned `intl`/`flutter_lints`, dead dependencies)

**Severity:** LOW · **Effort:** S · **Depends on:** F2 (dead dependencies) · **Verification:** CI · **[PROTECTED]** for `pubspec.lock`
**Ledger:** F29 (03 #25)

**Problem:** `build.gradle:58` runs `"git rev-parse HEAD\n".execute()`, which throws if `git` is not on PATH (breaks builds from a source tarball); `build.gradle:51` keeps a "TODO: Specify your own unique Application ID" although it is set; `pubspec.yaml:34,58` use `intl: any` and `flutter_lints: any`; `avnc_flutter` (`:39`) and `webview_flutter` (`:21`) exist only for the dead VNC path (F2).

**Steps:**
1. Wrap the `git rev-parse` call in try/catch with an "unknown" fallback; delete the TODO.
2. Pin `intl` and `flutter_lints` to the currently resolved versions and run `flutter pub get` (lockfile changes by the package manager only).
3. Remove `avnc_flutter` and `webview_flutter` once F2 lands.

**Verification:** CI: `flutter pub get && flutter analyze && flutter test`; a build with `git` unavailable still succeeds.

## Task F23: Remove dead code that tests keep alive; close the biggest test gaps

**Severity:** LOW · **Effort:** M · **Depends on:** F5, F7 (tests share fixtures) · **Verification:** CI
**Ledger:** F23 (03 #19). Related: earlier plan D4.

**Problem:** `Util.rootfsExtractCommand` (`cat xa* | ...`, `workflow.dart:200`), `swapAlarmTinyIdsCommand` (`:188`), `copyAssetsSequentially` (`:80`) and `copyAsset2` (`:89`) have no non-test caller; `test/workflow_test/rootfs_extract_command_test.dart`, `swap_ids_test.dart` and `copy_assets_sequentially_test.dart` (about 8 tests, 136 lines) exercise only them. Untested: `ContainerInstaller.installBase/installDesktop/_registerContainer`, `getCurrentProp`, `launchCurrentContainer`, `SetupSession.run`, `_runFirstTimeSetup`. `test/widget_test.dart` asserts only that the widget you just pumped exists. `tool/dump_boot.dart:12` duplicates the `extraMount` string and has drifted from `workflow.dart:1938-1943` (omits the cmatrix and tiny_virtual_mic mounts).

**Steps:**
1. Re-grep `lib/` for callers, then delete the four helpers and their three test files (the earlier plan warns that `FakeProc` is live; re-grep before touching it).
2. Add the success-path tests from F5, the `SetupSession.run` tests from F7, and a `getCurrentProp` test.
3. Make `tool/dump_boot.dart` import the mount list instead of copying it.
4. Expect the test count to drop by about 8; update AGENT_REPORT counts (F39).

**Verification:** CI: `flutter analyze --no-fatal-infos`; `flutter test`.

## Task F38: Test hygiene in `first_run_flow_test.dart` and package-name validation

**Severity:** LOW · **Effort:** S (guards) / L (package validation) · **Depends on:** none · **Verification:** CI
**Ledger:** F38 (03-rc R13)

**Problem:** Tests at `test/first_run_flow_test.dart:384-391` and `:135-150` assert substrings of generated shell rather than executing it. The executed ones (`:219-250`, `:271-346`) call `Process.runSync('chmod'/'sh'/'tar'/'md5sum'...)` with no `Platform.isLinux` guard (contrast `native_lib_link_test.dart:15`), so they fail on Windows or on macOS without GNU tar. The test at `:56-58` asserts `picked?.id` is still `'xfce4'` after only a scroll, so it re-asserts the earlier tap. Nothing asserts that DE package names exist in distro repos; `desktop_environments.dart` lists (for example Alpine `enlightenment`, Void `mate-extra`, apt `cinnamon-core`) were NOT validated against any repo in this audit.

**Steps:**
1. Add `skip:` guards for the tool-dependent tests (loud, not silent returns).
2. Fix the `:56-58` assertion so it tests the scroll.
3. Owner decision: add a containerised nightly job that runs `pacman -Si`/`apt-cache policy`/`dnf info`/`apk info`/`xbps-query` for every listed package, or accept a documented manual check.

**Verification:** CI: tests skip visibly on a host without the tools.

---

# Phase 4: docs and cleanup

## Task S9: Document jniLibs provenance, hashes, licences and alignment

**Severity:** MEDIUM · **Effort:** L (needs the owner's source information) · **Depends on:** none (README source-offer part can go earlier) · **Verification:** CI (hash and alignment script)
**Ledger:** S9 (02)

**Problem:** `android/app/src/main/jniLibs/arm64-v8a/` holds 17 committed prebuilt binaries (proot, busybox, tar, virgl, pulseaudio, pcre2, ...) with no documented provenance and no published hashes. `strings`/`readelf` show Termux builds: `libexec_proot`/`busybox`/`tar`/`libbusybox` have RUNPATH `/data/data/com.termux/files/usr/lib`, `tar` embeds `/root/.termux-build/tar/src/...`, `virgl_test_server` references the Termux virglrenderer path. `libexec_pulseaudio` was built with Android clang 8.0.7 and `getifaddrs_bridge_server` with clang 9.0.8, so neither came from the pinned NDK 27. README says "No Termux" while crediting Termux. The GPL binaries (proot, busybox, tar) ship with no source or offer pointer in the README (`COPYING` is the app's own GPL). `libexec_getifaddrs_bridge_server.so` and `libproot-loader32.so` have 4 KiB PT_LOAD alignment (the rest 16/64 KiB), matching `docs/asahi-apk-build.md:57`. The history of the original add is unavailable in the shallow clone.

**Steps:**
1. Add `docs/jnilibs-provenance.md` with, per file: `sha256sum`, upstream package and version, build date, and licence. Regenerate hashes with `sha256sum android/app/src/main/jniLibs/arm64-v8a/*`; the owner must supply upstream versions (they cannot be reconstructed from the files).
2. Add the GPL source-offer pointers to the README and fix the "No Termux" wording to say the binaries are Termux builds.
3. Either rebuild the two stale-toolchain and 4 KiB-aligned libs from source with the pinned NDK and a 16 KiB max page size, or document why not.
4. Add a CI script that verifies the committed hashes against the manifest and checks `readelf -lW` alignment.

**Verification:** CI: `sha256sum -c` against the manifest and an alignment check on all 17 files.

## Task F31: Regenerate `assets/patch.tar.gz` from tracked sources and fix its ignore rule, modes and metadata

**Severity:** LOW · **Effort:** S-M · **Depends on:** F3, F12, S12 · **Verification:** CI
**Ledger:** F31 (03 #11, location corrected by R4; R14). Related: earlier plan D3.

**Problem:** `git ls-files -ci --exclude-standard` prints `assets/patch.tar.gz`: `.gitignore` lists it although it is tracked (force-added). It is a required runtime asset (extracted at `workflow.dart:1644`), so a regenerated copy would not be picked up by `git add -A`. Its contents are stale: `tiny/start-desktop` is 2213 B against 546 lines in `assets/scripts`, `tiny/start-arch.sh` 646 B against 32 lines, plus a full copy of the legacy `build-arch-rootfs.sh` (with the VNC password, S12), `turnip.patch`, and `chn_fonts.reg` under `tiny/cross/`. The live scripts win only because `workflow.dart:1539-1551` copies them to `tiny/extra/` after the tar. Every entry is mode 0644 (F12) and carries the author's local account name as tar owner/group (a personal identifier; value not recorded here).

**Steps:**
1. Remove the `assets/patch.tar.gz` line from `.gitignore`; `git ls-files -ci --exclude-standard` should then print nothing.
2. Add `tool/build_patch_tar.sh` that builds the archive from tracked sources with `--owner=0 --group=0 --numeric-owner` and explicit modes (scripts executable), dropping the stale shadow copies and the legacy builder (S12).
3. Settle the `cross/` versus `extra/` layout with F3 before regenerating.

**Verification:** CI: `git ls-files -ci --exclude-standard` is empty; `tar -tzvf assets/patch.tar.gz` shows only intended entries, no personal owner name, and executable modes where needed.

## Task F34: Fix stale contributor/agent/user docs

**Severity:** LOW (critic downgrade from MEDIUM) · **Effort:** S-M · **Depends on:** F2 (display transport), F12 · **Verification:** CI grep · **[PROTECTED]** for `AGENTS.md` and `.github/copilot-instructions.md`
**Ledger:** F34 (03 #9). Related: earlier plan D2.

**Problem:** `AGENTS.md` (the target of the `CLAUDE.md`/`GEMINI.md`/`.cursorrules` symlinks) and `.github/copilot-instructions.md:3,51,64,114` describe VNC/noVNC as the display, bundled `xaa..` rootfs chunks, "only four Dart source files" (there are 20), `assets/assets.zip` as the proot/busybox bootstrap (it holds only pulseaudio libs), and a `build.ps1` that does not exist (plus the Windows path at `:39`, S11). `MANUAL.md:123-124` tells users to open the Termux:X11 app (`start-desktop:9,16` prints the same); `MANUAL.md` section 5.1 says DaRipped exports `PROOT_NO_SECCOMP=1` and to verify it in the Startup Command setting, but `workflow.dart:1426-1431` deliberately does not set it (author comment: it broke chdir on Android 17) and the Startup Command setting is dead (F1). `distros.dart:336` still says "Matches the bundled default container". README and `AGENTS.md` also disagree on the display architecture (in-app X server versus VNC).

**Steps:**
1. Rewrite the architecture and rootfs sections of `AGENTS.md` and `copilot-instructions.md` to match the live design (in-app X server, download/checksum/extract flow); remove the `build.ps1` and `xa*` references.
2. Fix `MANUAL.md` (Termux:X11 wording, the `PROOT_NO_SECCOMP` claim) and the `start-desktop:9,16` messages; fix the `distros.dart:336` comment.
3. Keep the symlinks intact.

**Verification:** CI: `git grep -nE 'build\.ps1|xa\*|noVNC|Termux:X11 app' AGENTS.md .github/copilot-instructions.md MANUAL.md assets/scripts` returns nothing unintended.

## Task F25: Fill the Chinese l10n gaps and clean up hardcoded English

**Severity:** LOW · **Effort:** M (needs translations) · **Depends on:** none · **Verification:** CI
**Ledger:** F25 (03 #21, R5)

**Problem:** `lib/l10n/intl_zh.arb` is missing 26 keys and `intl_zh_Hant.arb` 25 that exist in the English template (the new-container, delete and picker strings, plus `enableTerminalKeypad` in zh), so Chinese users see English for the whole new install flow. 16 English keys are never used (for example `appTitle`, `chooseDesktop*`, `desktopLxqt*`, `desktopXfce*`, `copyingContainerSystem`, `installationComplete`, `startingVnc`, `waitingForVnc`). Hardcoded English remains: "Retry" (`main.dart:1880`, `container_install_page.dart:99`) and the step names in `container_installer.dart`. Non-Arch quick-command lists (apt/dnf/zypper/apk/xbps, `workflow.dart:1110-1266` and earlier) have Chinese-only names for English users (`getCommandsForPackageManager`'s `english` flag only affects pacman, `:864-889`).

**Steps:**
1. Add the missing keys to both zh files (owner supplies or approves translations).
2. Delete or use the 16 unused keys (the VNC ones go with F2).
3. Move "Retry" and the installer step names into ARB.
4. Add English variants for the non-Arch command lists.
5. Add a test that compares ARB key sets.

**Verification:** CI: the new ARB parity test; `flutter gen-l10n` clean.

## Task F26: Point in-app and template links at this repo; fix the dated Ubuntu fallback

**Severity:** LOW · **Effort:** S · **Depends on:** S3 (the Ubuntu URL) · **Verification:** CI grep
**Ledger:** F26 (03 #22, R11)

**Problem:** In-app Project/Issue/FAQ/Solution/Discussion links go to `Cateners/tiny_computer` and gitee `caten/tc-hints` (`workflow.dart:666-686`; also `main.dart:901,1738,2268`); the issue templates and discussions link (`.github/ISSUE_TEMPLATE/*`, `config.yml:4`) point to the upstream repo; `Signal9Activity.kt:42,46` sends users to `vmos.cn` and upstream gitee docs. Bug reports from IntelNode users go to the wrong maintainer. The Ubuntu fallback URL is a dated directory `release-20261017` (`distros.dart:357`) that Ubuntu prunes.

**Steps:**
1. Replace the issue/discussion links with this repo's; keep upstream links only as attribution.
2. Review the `.github/ISSUE_TEMPLATE/*` (workflow-adjacent; confirm editing is allowed).
3. Revisit the Ubuntu dated URL together with its S3 pin.

**Verification:** CI: `git grep -n 'Cateners/tiny_computer\|tc-hints' lib android .github` shows only intended attribution.

## Task F13: Reconcile MANUAL.md's tool-stack claims with what is installed

**Severity:** LOW (critic downgrade from MEDIUM) · **Effort:** S · **Depends on:** F12 · **Verification:** CI grep
**Ledger:** F13 (03 #2)

**Problem:** `MANUAL.md:57-59,95-110` promise `~/Vault`, an `xclip` clipboard bridge, a Zellij layout, `rg`, `fd`, `jq` and `fzf`. `git grep -niE "zellij|xclip|ripgrep|fzf|obsidian" -- lib assets extra android` hits only `to_vault`; no first-boot or DE package list (`distros.dart:263-330`, `desktop_environments.dart`) installs any of them. Only `~/Vault/Raw_Intel` is created, by `to_vault` itself.

**Steps:**
1. Either add the tools to the package lists, or cut the claims from `MANUAL.md` and mark them as optional installs.
2. Tie the `to_vault` instructions to the F12 outcome.

**Verification:** CI: every tool named in `MANUAL.md` is either in a package list or labelled optional (a small grep-based check).

## Task F30: Remove or replace the non-Python `update_changelog.py`

**Severity:** LOW · **Effort:** S · **Depends on:** none · **Verification:** CI
**Ledger:** F30 (03 #10)

**Problem:** `.github/scripts/update_changelog.py` is a single pasted markdown line (`**Location in each repo:** \`.github/scripts/update_changelog.py\``); `python3 -I -m py_compile` fails with `SyntaxError` at line 1. Nothing references it (`grep -rn update_changelog` finds no workflow or doc).

**Steps:**
1. Delete the file, or replace it with the real script and wire it up.

**Verification:** CI: `python3 -I -m py_compile .github/scripts/update_changelog.py` passes, or the file is gone.

## Task F39: Reconcile AGENT_REPORT.md counts and device claims

**Severity:** LOW · **Effort:** S · **Depends on:** F23 (test count changes) · **Verification:** CI grep
**Ledger:** F39 (02 verdict)

**Problem:** `AGENT_REPORT.md:12` says "202/202" but `:62` says "205 passed"; the CI run `44134148815` at the same commit reports 18 info-level analyzer issues and 205 tests passed (matches `:62`). `:8` claims all distros were verified on physical hardware (Nothing Phone 2a) while README says the last test was a Pixel 10 Pro; neither is independently verifiable.

**Steps:**
1. After the test changes (F23), write one real count taken from a CI run into both places.
2. Reconcile the device identity, or state the claim as "author-reported, per device".

**Verification:** CI: the numbers in `AGENT_REPORT.md` equal the latest `flutter test` output.

## Task S15: Complete the open-source licence panel

**Severity:** LOW · **Effort:** S-M · **Depends on:** S9, F2 · **Verification:** CI (widget test)
**Ledger:** S15 (03-rc R11)

**Problem:** The "Open source licenses" panel (`main.dart:1337-1707`) lists only Flutter, `path_provider`, `webview_flutter`, `url_launcher`, `shared_preferences`, xterm, `flutter_pty`, `permission_handler`, `http`, `retry` and `intl`. It omits `clipboard`, `wakelock_plus`, `dynamic_color`, `network_info_plus`, `device_info_plus` (`pubspec.yaml:24-28`), the two GPL-family plugins `x11_flutter` and `avnc_flutter` (`pubspec.yaml:31-39`, pinned to commit SHAs), and the bundled GPL binaries proot/busybox/tar.

**Steps:**
1. Add the missing entries, or replace the hand-written panel with Flutter's `LicenseRegistry`/`showLicensePage` and register the bundled binaries' licences with source pointers (S9).
2. Drop `avnc_flutter`/`webview_flutter` entries if F2 removes them.
3. Widget test: the licence page lists each current dependency.

**Verification:** CI: `flutter test`.

---

# Needs device confirmation

Every runtime claim below was reasoned from code and never observed. Target: a Pixel 10 Pro, package `com.daripper91.daripped`. Use a debug build for `run-as` (release builds are not debuggable). Clear logcat first with `adb logcat -c`. Confirm each before ranking the task above MEDIUM.

| ID | Claim to confirm | Repro on the Pixel 10 Pro | Bug is real if |
|---|---|---|---|
| F4 | Mic streaming throws `UnsatisfiedLinkError` | `adb shell pm grant com.daripper91.daripped android.permission.RECORD_AUDIO`; launch the app; Settings, enable audio streaming; `adb logcat -b main -b crash \| grep -E 'UnsatisfiedLinkError\|native-socket\|AndroidRuntime'` | `UnsatisfiedLinkError` naming `AudioStream.nativeInit`, or the process dies |
| F19 / F20 | Start/stop futures never complete; `isStreaming` sticks `true` | Toggle streaming on, off, on repeatedly (after F4 is fixed); watch logcat | The second start is ignored, or the toggle hangs |
| F12 | `to_vault` has no exec bit | `adb shell run-as com.daripper91.daripped find . -name to_vault -exec ls -ln {} \;`; in the in-app terminal: `echo hi \| to_vault T` | Mode lacks `x` and the shell prints "Permission denied" |
| F3 | Guest files/commands are missing | Terminal: `command -v stopvnc startvnc cmatrix tiny_virtual_mic`; `ls ~/.local/share/tiny/extra ~/.local/share/tiny/cross`; tap Power Off, Hangover install, Wine "Fix CJK"; watch for an `ld.so ... cannot be preloaded` warning on a guest command | Commands not found; `install-hangover` and `chn_fonts.reg` only under `cross/` |
| F2 | Turning `useX11` off leaves no reachable display; VNC-era line typed into the pty | Settings, switch X11 display off, launch; `adb logcat \| grep -iE 'RetryException\|TimeoutException\|36082\|Unhandled'`; terminal: `ls -a ~ \| grep vnc` | A connection that never succeeds and unhandled exceptions; a `~/.vnc` directory appears |
| F6 | `wget` missing; zh "更新和升级" fails; `neofetch` missing | Terminal on a fresh Arch container: `command -v wget neofetch`; run the zh "更新和升级" quick command | `wget`/`neofetch` not found; "you cannot perform this operation unless you are root" |
| F7 | Installer hangs after the setup shell dies | During an install, type `exit` in the install terminal; `adb shell dumpsys activity top \| head -30` | The page stays on the install screen with no way out except force-stop |
| F8 | Foreground service start failure is invisible to Dart | Press Home, trigger a container start from background (Android 12+); `adb logcat \| grep -iE 'ForegroundServiceStartNotAllowed\|ContainerSession'` | Exception in logcat while Dart sees success |
| F9 | Stale partial resumed across distros | Start a Fedora install, then `adb shell svc wifi disable` mid-download; re-enable, choose Alpine at the same container index; `adb shell run-as com.daripper91.daripped find . -name 'new_rootfs_*'` | The same partial filename is reused, and the download resumes on the first distro's bytes |
| F11 | Service self-restarts with no container and an untimed wake lock | Start a container, press Home, `adb shell am kill com.daripper91.daripped`; then `adb shell dumpsys activity services com.daripper91.daripped` and `adb shell dumpsys power \| grep -i wake` | The service is running or restarting, and a partial wake lock is still held with no container |
| F14 | Storage-permission denial throws after the install | Fresh install; `adb shell appops set com.daripper91.daripped MANAGE_EXTERNAL_STORAGE deny`; run first-run | The error screen appears after the rootfs download, and Retry re-launches the X server |
| F15 | Cancelled picker leaves a bare base | At the desktop picker: `adb shell input keyevent KEYCODE_BACK` | The picker closes and the next start boots a base with no desktop (expected: blocked) |
| F18 | Unhandled async errors in the launch path | With F2's path active, launch and `adb logcat \| grep -i 'Unhandled Exception'` | Unhandled exception from `launchX11`/`waitForConnection` |
| F21(d) | IME pops up on non-text focus | In the desktop, click a non-text widget; watch for the soft keyboard | The keyboard appears |
| F22 | Config overwritten each launch | In the guest edit `~/.config/gtk-3.0/settings.ini`; stop and relaunch the desktop | The edit is gone |
| F37 | Overlay buttons lack descriptions; "150%" is wrong | Enable TalkBack; `adb shell uiautomator dump /sdcard/u.xml && adb pull /sdcard/u.xml`; check the overlay buttons' `content-desc` and the scale label | Empty `content-desc`; the label is out of sync with the real scale |
| F40 | LXQt theme/icon packages are missing | After an LXQt install: `pacman -Q papirus-icon-theme lxqt-themes` (or the distro's equivalent) | The packages are not installed while `lxqt.conf` names them |
| S1 | Framework passes `..` doc ids and display names unmodified (the critical unknown) | Build a throwaway client app that calls `ACTION_OPEN_DOCUMENT_TREE`, picks the IntelNode `containers` root, then calls `DocumentsContract.buildDocumentUriUsingTree` with a `..` doc id (and `createDocument` with `../../x`); `adb shell` cannot hold `MANAGE_DOCUMENTS`, so adb alone is not enough | Before the fix: the read/create succeeds outside the root. After the fix: `SecurityException` or `FileNotFoundException`, and a sanitised name |
| S5 | openSUSE first boot works without `--gpg-auto-import-keys` | After step 1 of S5, install an openSUSE container and watch the first-boot log | First boot completes; if not, restore the flag at `distros.dart:301-302` with a fingerprint check |
| S10 | Unauthenticated local control of the IME bridge | `adb shell "echo show \| toybox nc 127.0.0.1 4720"`; and `adb shell am broadcast -a <action from AndroidManifest.xml:68-76>` | The keyboard toggles from the shell (before); a rejected broadcast and bounded socket (after) |
| S13 | Guest can read the app's own data | In the guest: `ls /data/data/com.daripper91.daripped/shared_prefs` | The listing succeeds |
| F10 | Mid-failure leaves folders and prefs inconsistent | Reproduce with the CI test (F10 step 3); no device needed | The test fails before the fix |

Not device-dependent and already VERIFIED statically (no repro needed): S2, S3, S4, S6, S7, S8, S9, S11, S12, S14, F1, F5, F13, F16, F17, F23-F26, F28-F36, F38, F39. F38's package-name validation needs a container or network check, not a phone.

---

# Out of scope / not reviewed

- Files no stage read: `lib/boot_log.dart`, `lib/theme.dart`, `lib/fake_proc.dart`, `lib/setup_terminal.dart`; the non-read parts of `lib/distros.dart` (simplestreams/URL tables); 12 of 29 test files; Android resource and layout XML; `guest_shims.dart` and `pty_shell.dart` (read in chunks by one stage only).
- External plugin sources (`x11_flutter`, `avnc_flutter`; reflective calls into `com.termux.x11.*` are unvalidated), jniLibs internals beyond `strings`/`readelf`, and `assets/assets.zip` beyond its listing.
- `flutter analyze` and `flutter test` were not run locally; no Dart dependency CVE audit (`pubspec.lock`); no full-history secret scan (shallow, blobless clone; only a regex grep over the current tree, which found no credentials).
- No on-device run of anything; no exploit of the SAF provider was executed; the AOSP `DocumentsProvider.enforceTree` path and the `MANAGE_DOCUMENTS` protection level were not read.
- No upstream-vs-fork diff, so every "upstream did X" statement (including in F1) is unverified.
- Who signed the v2.1.1 to v2.2.5 bot releases was not checked (no `apksigner`/`keytool` pass).
- `MANUAL.md` claims beyond F13 and F34 (the Tensor G5 "kernel-level optimizations" line, Zellij layout, "Rust-based parsing stack", HiDPI scaling) were never examined.
- Earlier-plan items not re-checked here (for example D9 in `docs/plans/2026-11-15-intelnode-fixes.md`, a device log committed under `Bug_Reports/`): outside this ledger.
- `gh`-derived facts (release authorship, secrets list by name, run IDs, repo size) are time-sensitive; re-check before acting.

---

## Known coverage gaps

See the coverage statement at the top and the "Out of scope / not reviewed" list. In short: runtime behaviour was never observed on a device, the Flutter toolchain was never run, the SAF framework enforcement path is unverified, and roughly a dozen files and the external plugin sources were not read.

## Definition of done

- **S11:** the grep in S11 returns nothing outside the earlier plans; `OWNERS` has no third-party email; the owner has revoked the wireless-debugging pairing and the tailnet node and has made (and recorded) the history-purge decision.
- **S1, S2:** JUnit suite for `..`, prefix siblings, display names, symlinks and null listings passes in CI; the S1 device repro is blocked.
- **S3, S4, S9-pins, F9:** every fixed versioned rootfs URL has a 64-hex pin verified by test; unknown schemes or extensions fail closed; partial files are named by source; one pinned distro installs end-to-end on the Pixel 10 Pro.
- **S5:** `git grep -nE 'gpg-auto-import-keys|nogpgcheck|no-gpg-checks' lib` returns only allow-listed lines; openSUSE first boot succeeds on a device.
- **S6:** on a scratch fork, a `-debug` tag runs nothing; a release tag with blank secrets fails; a signed run produces a pre-release whose cert is not the debug cert.
- **S10, S13, S14:** the manifest shows the receiver unexported (or permission-protected) and cleartext decided; the socket is bounded; HiDPI/VirGL/Turnip options are escaped.
- **F4, F19, F20:** `nm -D` finds four `Java_com_daripper91_daripped_AudioStream_*` symbols; both channel methods reply; repeated device start/stop works.
- **F3, F1, F2, F5, F6, F8, F10, F7, F11, F12, S12:** each owner decision is recorded in the commit message; `git grep -in vnc lib` is intended-only; `_registerContainer` and the reset action produce the right package manager and commands; failure-injection tests for delete and `SetupSession` pass; `to_vault` runs on the device; no hardcoded VNC password remains.
- **F14-F18, F21, F22, F24, F27, F28, F36, F37, F40:** the corresponding unit/widget tests pass and the device checks in the table above show the fixed behaviour.
- **S8, S7, F32, F33, F35, F29, F23, F38:** a PR triggers analyze and tests; debug artifacts carry the debug cert; "Latest" is a non-debug release; the APK reports the tag's version and a monotonic versionCode; `flutter analyze` and `flutter test` are green with a visible skip count.
- **S9, F31, F34, F25, F26, F13, F30, F39, S15:** the hash manifest and alignment checks pass in CI; `git ls-files -ci --exclude-standard` is empty and the tar has no personal owner name; the docs grep checks above are clean; the ARB parity test passes; `AGENT_REPORT.md` quotes one real test count.
- **Across the plan:** each task's commit cites its ledger ID; `flutter analyze` and `flutter test` are run before each commit; no task marked [PROTECTED] was started without the owner's go-ahead; `AGENT_REPORT.md` is updated at the end per `AGENTS.md`.
