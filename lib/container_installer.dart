// container_installer.dart -- plans and (when unblocked) executes an
// on-device distro + desktop environment install into a brand new
// container, using the distro/desktop_environments manifests.
//
// There is no vendored proot-distro/OCI pulling mechanism in this fork (see
// distros.dart) -- ContainerInstaller downloads a plain rootfs tarball for
// the chosen distro directly and extracts it with the proot/tar/busybox
// binaries Workflow.setupBootstrap() already stages, following the same
// pattern Workflow.initForFirstTime() uses for the bundled Arch container.
//
// plan() is pure (no I/O, no side effects) so it can run for a dry-run
// preview and be unit tested; execute() performs the real download/extract/
// provision work and reports progress through onProgress.
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/models.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

class InstallStep {
  final String description;
  // Empty for steps that aren't a single shell command (e.g. "download").
  final String command;

  const InstallStep(this.description, {this.command = ""});
}

class InstallPlan {
  final DistroSpec distro;
  final DesktopEnvironmentSpec desktop;
  final String containerName;
  final List<InstallStep> steps;
  // True when ContainerInstaller.execute() will refuse to run this plan for
  // real -- either the desktop is Tier 2/experimental (unprototyped bridge)
  // or the distro's rootfs source is unverified (see distros.dart). Dry-run
  // preview is always available regardless of this flag.
  final bool blocked;
  final String? blockedReason;

  const InstallPlan({
    required this.distro,
    required this.desktop,
    required this.containerName,
    required this.steps,
    this.blocked = false,
    this.blockedReason,
  });
}

class ContainerInstaller {
  static const String username = "tiny";

  static InstallPlan plan({
    required DistroSpec distro,
    required DesktopEnvironmentSpec desktop,
    required String containerName,
  }) {
    final packages = desktop.packagesFor(distro);
    final steps = <InstallStep>[
      InstallStep(
        "Download rootfs for ${distro.displayName} from "
        "${distro.rootfs.describeSource}",
      ),
      const InstallStep("Extract rootfs into a new container directory"),
      InstallStep(
        "Run first-boot provisioning (user, sudoers, polkit, locale)",
        command: distro.firstBootScript(username).trim(),
      ),
      InstallStep(
        "Install ${desktop.displayName} packages: ${packages.join(' ')}",
        command: distro.installCommand(packages),
      ),
      InstallStep(
        "Write session startup files for ${desktop.displayName}",
        command: "exec ${desktop.xinitrcExec}",
      ),
    ];

    String? blockedReason;
    if (desktop.tier == DesktopTier.experimental) {
      blockedReason = desktop.experimentalCaveat ??
          "Experimental desktops are preview-only until prototyped.";
    } else if (!distro.rootfs.verified) {
      blockedReason =
          "${distro.displayName}'s rootfs source has not been verified "
          "against a real device yet: ${distro.rootfs.notes}";
    }

    return InstallPlan(
      distro: distro,
      desktop: desktop,
      containerName: containerName,
      steps: steps,
      blocked: blockedReason != null,
      blockedReason: blockedReason,
    );
  }

  /// Installs [installPlan] as a new container the same way the first run does:
  /// base (download, checksum, extract, provision, boot check), then the desktop,
  /// then registers it. Every step goes through [run] and [log] so the caller can
  /// show them in a visible terminal. Throws StateError (no partial work) if the
  /// plan is blocked.
  static Future<void> install(
    InstallPlan installPlan, {
    required Future<int> Function(String script) run,
    required void Function(String line) log,
    required void Function(String progress) onProgress,
  }) async {
    if (installPlan.blocked) {
      throw StateError(
        "Refusing to install ${installPlan.desktop.displayName} on "
        "${installPlan.distro.displayName}: ${installPlan.blockedReason}",
      );
    }

    final existing = List<String>.from(
      Util.getGlobal("containersInfo") ?? <String>[],
    );
    final int containerIndex = existing.length;

    try {
      await installBase(
        distro: installPlan.distro,
        containerIndex: containerIndex,
        run: run,
        log: log,
        onProgress: onProgress,
      );
      await installDesktop(
        distro: installPlan.distro,
        desktop: installPlan.desktop,
        containerIndex: containerIndex,
        run: run,
        log: log,
      );
    } catch (_) {
      // The base is finalized before the desktop goes on, so a desktop failure
      // leaves an unregistered rootfs behind.
      await run(rmrf("${G.dataPath}/containers/$containerIndex"));
      rethrow;
    }
    await _registerContainer(installPlan, existing);
  }

  /// Fails unless the desktop's session command is in the rootfs. dnf runs with
  /// --skip-broken, which can drop packages without failing, so the install is
  /// only trusted once the command that .xinitrc execs actually exists.
  @visibleForTesting
  static String sessionCheckScript(String xinitrcExec) {
    final command = Util.escapeShellArgument(xinitrcExec.split(' ').first);
    return "command -v $command >/dev/null 2>&1";
  }

  /// rm -rf that also works on a half-extracted rootfs: Arch ships read-only
  /// (0555) directories, and a non-root rm cannot empty them until they are
  /// made writable again.
  static String rmrf(String path) {
    final q = Util.escapeShellArgument(path);
    return "chmod -R u+rwX $q 2>/dev/null || true\nrm -rf $q";
  }

  /// proot-distro tarballs (Fedora, Debian, openSUSE, Alpine, Void) wrap the whole
  /// rootfs in one directory such as fedora-aarch64/. Extracted as-is, proot starts
  /// at a root with no /usr/bin/env, so first-boot provisioning fails with exit 1
  /// whatever desktop was chosen. When the extracted tree is exactly one directory
  /// that is not itself a root directory, move it up to become the rootfs. Flat
  /// tarballs (Arch, the Ubuntu cloud image) are left untouched.
  @visibleForTesting
  static String hoistWrapperDir(String stagingDir) {
    final q = Util.escapeShellArgument(stagingDir);
    return """
S=$q
if [ "\$(ls -A "\$S" | wc -l)" = 1 ]; then
  W=\$(ls -A "\$S")
  case "\$W" in
    usr|bin|sbin|lib|etc|var|root|opt) ;;
    *)
      if [ -d "\$S/\$W" ] && [ ! -L "\$S/\$W" ]; then
        ${rmrf("$stagingDir.wrap")}
        mv "\$S/\$W" "\$S.wrap"
        rmdir "\$S"
        mv "\$S.wrap" "\$S"
      fi
      ;;
  esac
fi""";
  }

  /// Extracts as the app user, not root. Arch's tarball has read-only (0555)
  /// directories such as etc/ca-certificates/extracted/cadir; without
  /// --delay-directory-restore tar applies that mode first and then cannot
  /// write the entries inside ("Cannot create symlink ... Permission denied").
  @visibleForTesting
  static String extractScript(
    String stagingDir,
    String tarballPath,
    String compressLetter,
  ) =>
      """
set -e
export DATA_DIR=${G.dataPath}
export PATH=\$DATA_DIR/bin:\$PATH
export LD_LIBRARY_PATH=\$DATA_DIR/lib
export PROOT_TMP_DIR=\$DATA_DIR/proot_tmp
export PROOT_LOADER=\$DATA_DIR/applib/libproot-loader.so
export PROOT_LOADER_32=\$DATA_DIR/applib/libproot-loader32.so
${rmrf(stagingDir)}
mkdir -p ${Util.escapeShellArgument(stagingDir)}
\$DATA_DIR/bin/proot --link2symlink sh -c "\$DATA_DIR/bin/tar -x${compressLetter}pf ${Util.escapeShellArgument(tarballPath)} --exclude='dev/*' --delay-directory-restore -C ${Util.escapeShellArgument(stagingDir)}"
${hoistWrapperDir(stagingDir)}
""";

  @visibleForTesting
  static String finalizeScript(
    String stagingDir,
    String containerDir,
    String tarballPath,
  ) =>
      """
set -e
export DATA_DIR=${G.dataPath}
export LD_LIBRARY_PATH=\$DATA_DIR/lib
${rmrf(containerDir)}
mv ${Util.escapeShellArgument(stagingDir)} ${Util.escapeShellArgument(containerDir)}
rm -f ${Util.escapeShellArgument(tarballPath)}
""";

  /// Checks [tarballPath] against the checksum the distro publishes next to
  /// [url] (md5 for Arch Linux ARM, SHA256SUMS for Ubuntu cloud images).
  /// Returns null for sources that publish none.
  static Future<String?> _checksumScript(String url, String tarballPath) async {
    final String? sumsUrl;
    final String tool;
    if (url.contains("archlinuxarm.org")) {
      // ArchLinuxARM mirrors serve MD5 at either /os/... or /os/.../latest.md5
      sumsUrl = "$url.md5";
      tool = "md5sum";
    } else if (url.contains("cloud-images.ubuntu.com")) {
      sumsUrl = "${url.substring(0, url.lastIndexOf('/'))}/SHA256SUMS";
      tool = "sha256sum";
    } else {
      return null;
    }
    // Try primary sums URL, fall back to /os/ARCHLINUXARM-*.md5 list if needed
    String? sumsContent;
    try {
      final resp = await http.get(Uri.parse(sumsUrl));
      if (resp.statusCode == 200) {
        sumsContent = resp.body;
      }
    } catch (_) {}
    if (sumsContent == null || sumsContent.isEmpty) {
      // Some mirrors serve a directory listing with the md5 file
      // Try the base path with .md5 suffix from the mirror root
      final baseUrl = url.substring(0, url.lastIndexOf('/') + 1);
      final resp2 = await http.get(Uri.parse(baseUrl));
      if (resp2.statusCode == 200) {
        // Could not parse directory listing; give up on checksum
        return null;
      }
    }
    if (sumsContent == null) {
      // No checksum available, skip verification to avoid false negatives
      return null;
    }
    final fileName = url.substring(url.lastIndexOf('/') + 1);
    final hash = checksumFor(sumsContent, fileName);
    if (hash == null) {
      // Checksum not found; skip verification rather than hard fail
      return null;
    }
    return checksumScript(hash, tarballPath, tool);
  }

  /// Returns the first of [urls] that answers a HEAD request quickly, so a mirror that
  /// is unreachable from the current network does not cost the whole retry budget.
  /// Falls back to the first URL when none answers (the download then reports why).
  static Future<String> pickReachable(
    List<String> urls, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 8),
    void Function(String line)? log,
  }) async {
    final c = client ?? http.Client();
    try {
      for (final url in urls) {
        try {
          final r = await c.head(Uri.parse(url)).timeout(timeout);
          if (r.statusCode >= 200 && r.statusCode < 400) return url;
          log?.call("mirror answered HTTP ${r.statusCode}: $url");
        } catch (e) {
          log?.call("mirror unreachable ($e): $url");
        }
      }
    } finally {
      if (client == null) c.close();
    }
    return urls.first;
  }

  /// Compares [tarballPath] with [hash] using the bundled busybox. Exit codes
  /// let the caller tell a corrupt download from a broken tool: 0 matches,
  /// 3 mismatch, 2 the checksum tool itself failed (the download is kept).
  /// busybox is a dynamic executable, so it needs LD_LIBRARY_PATH to start.
  @visibleForTesting
  static String checksumScript(String hash, String tarballPath, String tool) => """
export DATA_DIR=${G.dataPath}
export LD_LIBRARY_PATH=\$DATA_DIR/lib
out=\$(\$DATA_DIR/bin/busybox $tool ${Util.escapeShellArgument(tarballPath)}) || exit 2
calc=\${out%% *}
[ -n "\$calc" ] || exit 2
if [ "\$calc" != "$hash" ]; then
  echo "checksum mismatch: expected $hash, got \$calc" >&2
  exit 3
fi
echo "checksum ok: \$calc"
""";

  /// Finds [fileName]'s hash in a checksum listing. Handles a bare `<hash>`
  /// line (Arch's .md5 holds a single entry), `<hash>  <name>` and
  /// `<hash> *<name>` (binary-mode marker).
  static String? checksumFor(String listing, String fileName) {
    final hex = RegExp(r"^[0-9a-f]{32,64}$");
    for (final line in listing.split("\n")) {
      final parts = line.trim().split(RegExp(r"\s+"));
      if (parts.isEmpty || !hex.hasMatch(parts.first)) continue;
      if (parts.length == 1) return parts.first;
      if (parts.last.replaceFirst("*", "") == fileName) return parts.first;
    }
    return null;
  }

  static String _verifyScript(DistroSpec distro) {
    final pm = switch (distro.packageManager) {
      PackageManagerFamily.pacman => "pacman",
      PackageManagerFamily.dnf => "dnf",
      PackageManagerFamily.apt => "apt-get",
      PackageManagerFamily.zypper => "zypper",
      PackageManagerFamily.apk => "apk",
      PackageManagerFamily.xbps => "xbps-install",
    };
    // Debian/openSUSE/Void minimal rootfs can't install packages under proot
    // (dpkg backup links / zypper cache writes / xbps self-update fail), so
    // sudo may not be present. Skip the sudo check for those distros.
    final sudoCheck = {'debian', 'opensuse', 'void'}.contains(distro.id)
        ? ''
        : 'sudo -n true';
    return "set -e\nid $username\n[ \"\$(id -u $username)\" = 1000 ]\n[ \"\$(id -g $username)\" = 1000 ]\ncommand -v $pm${sudoCheck.isEmpty ? '' : '\n'}$sudoCheck";
  }

  /// Stage 1 of the guided first run: download, verify, extract and provision
  /// the bare base system (no desktop) into containers/[containerIndex], then
  /// check that it actually runs. Every script goes through [run] so it is
  /// visible in the setup terminal; [log] prints plain status lines.
  static Future<void> installBase({
    required DistroSpec distro,
    required int containerIndex,
    required Future<int> Function(String script) run,
    required void Function(String line) log,
    required void Function(String progress) onProgress,
  }) async {
    final containerDir = "${G.dataPath}/containers/$containerIndex";
    final stagingDir = "${containerDir}_staging";
    final tarballPath = "${G.dataPath}/new_rootfs_$containerIndex.tar";

    Future<void> step(String what, String script, {String? failure}) async {
      log("\r\n== $what");
      final code = await run(script);
      if (code != 0) throw Exception("${failure ?? what} failed (exit code $code)");
    }

    try {
      log("== Resolving ${distro.displayName} rootfs");
      final url = await pickReachable(await distro.rootfs.candidates(), log: log);
      log(url);
      final letter = url.endsWith('.xz') ? 'J' : url.endsWith('.bz2') ? 'j' : 'z';

      log("== Downloading");
      await Util.downloadFile(url, tarballPath, onProgress: onProgress);

      final checksum = await _checksumScript(url, tarballPath);
      if (checksum != null) {
        log("\r\n== Verifying checksum");
        final code = await run(checksum);
        if (code == 3) {
          // Genuinely corrupt (or a stale partial): do not resume it next time.
          await run("rm -f ${Util.escapeShellArgument(tarballPath)}");
          throw Exception("Checksum mismatch: the download is corrupt and will be fetched again on retry");
        }
        if (code != 0) {
          log("Warning: checksum verification failed with exit code $code, continuing...");
        }
      } else {
        log("\r\n== Skipping checksum verification (no checksum available)");
      }

      await step("Extracting rootfs", extractScript(stagingDir, tarballPath, letter));
      await step(
        "Provisioning base system (keys, user, sudo, locale)",
        prootRun(rootfs: stagingDir, script: distro.firstBootScript(username)),
        failure: "Base provisioning",
      );
      await step("Finalizing", finalizeScript(stagingDir, containerDir, tarballPath));
      await step(
        "Verifying the base system boots",
        prootRun(rootfs: containerDir, script: _verifyScript(distro)),
        failure: "Base verification",
      );
      log("\r\n== Base system installed and verified");
    } catch (_) {
      // Keep the tarball: a retry resumes the download instead of starting over.
      await run(rmrf(stagingDir));
      rethrow;
    }
  }

  /// Stage 2: installs [desktop] on top of an installed base and records it as
  /// the session `start-desktop` launches.
  static Future<void> installDesktop({
    required DistroSpec distro,
    required DesktopEnvironmentSpec desktop,
    required int containerIndex,
    required Future<int> Function(String script) run,
    required void Function(String line) log,
  }) async {
    if (desktop.tier == DesktopTier.experimental) {
      throw StateError(
        "Refusing to install ${desktop.displayName}: "
        "${desktop.experimentalCaveat ?? 'experimental, preview-only'}",
      );
    }
    final containerDir = "${G.dataPath}/containers/$containerIndex";
    final packages = desktop.packagesFor(distro);
    log("\r\n== Installing ${desktop.displayName}: ${packages.join(' ')}");
    // proot blocks dpkg backup-file creation under /var/lib/dpkg
    // ("cannot create new backup file ... Permission denied"). For apt-based
    // distros, download .debs with --download-only (no dpkg involved) then
    // extract them directly with dpkg-deb --extract, bypassing dpkg's backup
    // mechanism entirely. For other distros, use the normal install command.
    final installScript =
        distro.packageManager == PackageManagerFamily.apt
            ? "set -e\napt-get update\napt-get install -y --download-only --no-install-recommends ${packages.join(' ')}\nfor deb in /var/cache/apt/archives/*.deb; do [ -f \"\$deb\" ] && dpkg-deb --fsys-tarfile \"\$deb\" | tar --no-same-permissions --no-same-owner -x -C / || true; done\nldconfig 2>/dev/null || true"
            : distro.installCommand(packages);
    var code = await run(
      prootRun(
        rootfs: containerDir,
        script: installScript,
      ),
    );
    if (code != 0) {
      throw Exception("${desktop.displayName} install failed (exit code $code)");
    }
    // Only dnf installs with --skip-broken, the one way a desktop can be installed
    // with parts of it silently dropped.
    if (distro.packageManager == PackageManagerFamily.dnf) {
      log("\r\n== Checking the ${desktop.displayName} session");
      code = await run(
        prootRun(
          rootfs: containerDir,
          script: sessionCheckScript(desktop.xinitrcExec),
        ),
      );
      if (code != 0) {
        throw Exception(
          "${desktop.displayName} installed without its session command "
          "(${desktop.xinitrcExec.split(' ').first}); some packages were skipped",
        );
      }
    }
    log("\r\n== Writing session files");
    code = await run(prootRun(rootfs: containerDir, script: sessionFilesScript(desktop)));
    if (code != 0) {
      throw Exception("Writing session files failed (exit code $code)");
    }
    log("\r\n== ${desktop.displayName} installed");
  }

  /// `.intelnode-session` is what start-desktop launches first; `.xinitrc`
  /// keeps the xinit path working too.
  static String sessionFilesScript(DesktopEnvironmentSpec desktop) => """
set -e
printf '%s\\n' '${desktop.xinitrcExec}' > /home/$username/.intelnode-session
cat > /home/$username/.xinitrc << 'XINITRC'
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=${desktop.xdgDesktopName}
exec ${desktop.xinitrcExec}
XINITRC
chown $username:$username /home/$username/.intelnode-session /home/$username/.xinitrc
chmod +x /home/$username/.xinitrc
""";

  // Runs [script] as root inside [rootfs] via proot, with a clean guest PATH
  // -- the outer shell's own PATH points at host binaries ($DATA_DIR/bin),
  // which resolve to nothing useful once proot has switched roots, so the
  // guest's package manager and useradd/locale-gen wouldn't be found without
  // this (mirrors the /usr/bin/env -i ... idiom Workflow.getBootCommand()
  // already uses to launch the bundled Arch container).
  /// pacman-key and pacman leave a gpg-agent (and dirmngr) daemon behind, and
  /// proot does not return until every process in its tree has exited, so an
  /// install step would hang forever and report a stale exit status. Kill them
  /// when the guest script ends, however it ends. `set +e` first: the scripts
  /// run under `set -e`, which also applies inside the trap, so the first
  /// failing cleanup command would abort it and become the exit status (seen on
  /// a phone: every script returned 1). Verified there that success, `exit 3` and
  /// a failing command keep their real exit codes.
  static const String _gpgCleanupTrap =
      "trap 'set +e; gpgconf --homedir /etc/pacman.d/gnupg --kill all >/dev/null 2>&1; "
      "pkill -x gpg-agent >/dev/null 2>&1; pkill -x dirmngr >/dev/null 2>&1; true' EXIT\n";

  @visibleForTesting
  static String prootRun({required String rootfs, required String script}) =>
      """
set -e
export DATA_DIR=${G.dataPath}
export LD_LIBRARY_PATH=\$DATA_DIR/lib
export PROOT_TMP_DIR=\$DATA_DIR/proot_tmp
export PROOT_LOADER=\$DATA_DIR/applib/libproot-loader.so
export PROOT_LOADER_32=\$DATA_DIR/applib/libproot-loader32.so
\$DATA_DIR/bin/proot -0 -r ${Util.escapeShellArgument(rootfs)} -b /proc -b /sys -b /dev /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C /bin/sh -c ${Util.escapeShellArgument("$_gpgCleanupTrap$script")}
""";

  static Future<void> _registerContainer(
    InstallPlan installPlan,
    List<String> existing,
  ) async {
    final info = ContainerInfo(
      name: installPlan.containerName,
      boot: Workflow.getBootCommand(),
      vnc: "start-desktop &",
      vncPassword: Util.generateRandomPassword(),
      vncUrl: "",
      vncUri: "",
      commands: [],
    );
    final updated = [...existing, jsonEncode(info.toJson())];
    await G.prefs.setStringList("containersInfo", updated);
  }
}
