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

  // Executes [installPlan] for real: downloads the rootfs, extracts it,
  // provisions the distro, installs the desktop, and registers a new
  // container entry. Throws StateError immediately (no partial work) if the
  // plan is blocked. Reports each step through onProgress as it starts.
  static Future<void> execute(
    InstallPlan installPlan, {
    required void Function(String) onProgress,
  }) async {
    if (installPlan.blocked) {
      throw StateError(
        "Refusing to install ${installPlan.desktop.displayName} on "
        "${installPlan.distro.displayName}: ${installPlan.blockedReason}",
      );
    }

    final distro = installPlan.distro;
    final desktop = installPlan.desktop;

    final existing = List<String>.from(
      Util.getGlobal("containersInfo") ?? <String>[],
    );
    final int containerIndex = existing.length;
    final String containerDir = "${G.dataPath}/containers/$containerIndex";
    final String stagingDir = "${containerDir}_staging";

    onProgress("Resolving rootfs download location...");
    final String rootfsUrl = await distro.rootfs.resolve();
    // busybox tar's compression auto-detection is inconsistent across
    // builds, so pick the flag explicitly from the resolved URL rather than
    // relying on it (Arch ships .tar.gz; Ubuntu and the linuxcontainers.org
    // mirror both serve .tar.xz).
    final String compressLetter = rootfsUrl.endsWith('.xz')
        ? 'J'
        : rootfsUrl.endsWith('.bz2')
            ? 'j'
            : 'z';
    final String tarballPath = "${G.dataPath}/new_rootfs_$containerIndex.tar";

    onProgress("Downloading ${distro.displayName} rootfs...");
    await Util.downloadFile(rootfsUrl, tarballPath, onProgress: onProgress);

    onProgress("Extracting rootfs...");
    Util.createDirFromString(stagingDir);
    int exitCode = await Util.execute("""
export DATA_DIR=${G.dataPath}
export LD_LIBRARY_PATH=\$DATA_DIR/lib
rm -rf ${Util.escapeShellArgument(stagingDir)}
mkdir -p ${Util.escapeShellArgument(stagingDir)}
\$DATA_DIR/bin/proot --link2symlink sh -c "\$DATA_DIR/bin/tar -x${compressLetter}f ${Util.escapeShellArgument(tarballPath)} -C ${Util.escapeShellArgument(stagingDir)}"
""");
    if (exitCode != 0) {
      throw Exception("Rootfs extraction failed with exit code $exitCode");
    }

    onProgress("Running first-boot provisioning...");
    exitCode = await Util.execute(
      _prootRun(rootfs: stagingDir, script: distro.firstBootScript(username)),
    );
    if (exitCode != 0) {
      throw Exception(
        "First-boot provisioning failed with exit code $exitCode",
      );
    }

    onProgress("Installing ${desktop.displayName}...");
    final packages = desktop.packagesFor(distro);
    exitCode = await Util.execute(
      _prootRun(
        rootfs: stagingDir,
        script: "${distro.updateCommand}\n${distro.installCommand(packages)}",
      ),
    );
    if (exitCode != 0) {
      throw Exception(
        "${desktop.displayName} package install failed with exit code $exitCode",
      );
    }

    onProgress("Writing session startup files...");
    exitCode = await Util.execute(
      _prootRun(
        rootfs: stagingDir,
        script:
            """
cat > /home/$username/.xinitrc << 'XINITRC'
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=${desktop.xdgDesktopName}
exec ${desktop.xinitrcExec}
XINITRC
chown $username:$username /home/$username/.xinitrc
chmod +x /home/$username/.xinitrc
""",
      ),
    );
    if (exitCode != 0) {
      throw Exception(
        "Writing session startup files failed with exit code $exitCode",
      );
    }

    onProgress("Finalizing container...");
    exitCode = await Util.execute("""
export DATA_DIR=${G.dataPath}
\$DATA_DIR/bin/busybox rm -rf ${Util.escapeShellArgument(containerDir)}
mv ${Util.escapeShellArgument(stagingDir)} ${Util.escapeShellArgument(containerDir)}
rm -f ${Util.escapeShellArgument(tarballPath)}
""");
    if (exitCode != 0) {
      throw Exception("Finalizing container failed with exit code $exitCode");
    }

    await _registerContainer(installPlan, existing);
    onProgress("Done.");
  }

  // Runs [script] as root inside [rootfs] via proot, with a clean guest PATH
  // -- the outer shell's own PATH points at host binaries ($DATA_DIR/bin),
  // which resolve to nothing useful once proot has switched roots, so the
  // guest's package manager and useradd/locale-gen wouldn't be found without
  // this (mirrors the /usr/bin/env -i ... idiom Workflow.getBootCommand()
  // already uses to launch the bundled Arch container).
  static String _prootRun({required String rootfs, required String script}) =>
      """
export DATA_DIR=${G.dataPath}
export LD_LIBRARY_PATH=\$DATA_DIR/lib
export PROOT_TMP_DIR=\$DATA_DIR/proot_tmp
\$DATA_DIR/bin/proot -0 -r ${Util.escapeShellArgument(rootfs)} -b /proc -b /sys -b /dev /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root /bin/sh -c ${Util.escapeShellArgument(script)}
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
