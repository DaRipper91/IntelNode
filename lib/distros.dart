// distros.dart -- distro manifest for on-device multi-distro bootstrap.
//
// Adding a new distro means adding one DistroSpec entry to Distros.all; no
// selector UI or installer logic needs to change (see ContainerInstaller in
// container_installer.dart).
//
// This fork does not vendor a proot-distro binary or any OCI/Docker Hub
// pulling mechanism -- the only bootstrap primitives available are the
// proot/tar/busybox binaries already staged by Workflow.setupBootstrap().
// Each DistroSpec therefore points at a plain rootfs tarball, downloaded
// directly and extracted the same way the bundled Arch rootfs already is.
import 'dart:convert';

import 'package:http/http.dart' as http;

enum PackageManagerFamily { pacman, dnf, apt }

enum RootfsSourceKind { direct, simplestreams }

// Where a distro's rootfs tarball comes from, and how confident this entry
// is that the source actually works right now.
class RootfsSource {
  final RootfsSourceKind kind;

  // RootfsSourceKind.direct: the literal download URL.
  final String? directUrl;

  // RootfsSourceKind.simplestreams: resolved at install time against a
  // LXC-style simplestreams image server (see resolve()) because these
  // servers version images under a build timestamp that changes constantly
  // -- there is no fixed "latest" URL to hardcode.
  final String? simplestreamsBase;
  final String? simplestreamsProduct; // "distro:release:arch:variant"

  // False means this entry has not been confirmed against the distro's
  // current release/mirror layout and must be checked before it is relied
  // on for a real (non-dry-run) install -- see task brief: "confirm this is
  // available ... before relying on it". ContainerInstaller refuses to
  // execute (not just dry-run) any plan whose source is unverified.
  final bool verified;
  final String notes;

  const RootfsSource.direct({
    required String url,
    required this.verified,
    this.notes = "",
  }) : kind = RootfsSourceKind.direct,
       directUrl = url,
       simplestreamsBase = null,
       simplestreamsProduct = null;

  const RootfsSource.simplestreams({
    required String base,
    required String product,
    required this.verified,
    this.notes = "",
  }) : kind = RootfsSourceKind.simplestreams,
       directUrl = null,
       simplestreamsBase = base,
       simplestreamsProduct = product;

  String get describeSource => switch (kind) {
    RootfsSourceKind.direct => directUrl!,
    RootfsSourceKind.simplestreams =>
      "$simplestreamsBase (product $simplestreamsProduct, "
          "resolved at install time)",
  };

  // Returns the concrete rootfs tarball URL to download. For simplestreams
  // sources this makes two small JSON requests to find the current build;
  // throws a descriptive Exception (never fails silently) if the product or
  // a rootfs.tar.xz item can't be found.
  Future<String> resolve() async {
    if (kind == RootfsSourceKind.direct) return directUrl!;

    final base = simplestreamsBase!;
    final indexResp = await http.get(Uri.parse("$base/streams/v1/index.json"));
    if (indexResp.statusCode != 200) {
      throw Exception(
        "Failed to fetch simplestreams index from $base "
        "(HTTP ${indexResp.statusCode})",
      );
    }
    final index = jsonDecode(indexResp.body) as Map<String, dynamic>;
    final imagesPath =
        (index['index'] as Map<String, dynamic>)['images']['path'] as String;

    final imagesResp = await http.get(Uri.parse("$base/$imagesPath"));
    if (imagesResp.statusCode != 200) {
      throw Exception(
        "Failed to fetch simplestreams product list from $base/$imagesPath "
        "(HTTP ${imagesResp.statusCode})",
      );
    }
    final images = jsonDecode(imagesResp.body) as Map<String, dynamic>;
    final products = images['products'] as Map<String, dynamic>?;
    final product = products?[simplestreamsProduct] as Map<String, dynamic>?;
    if (product == null) {
      throw Exception(
        "Simplestreams product '$simplestreamsProduct' was not found at "
        "$base/$imagesPath -- this release/arch/variant combination may no "
        "longer be published there.",
      );
    }

    final versions = product['versions'] as Map<String, dynamic>;
    if (versions.isEmpty) {
      throw Exception(
        "Simplestreams product '$simplestreamsProduct' has no versions "
        "published at $base.",
      );
    }
    final latestKey = (versions.keys.toList()..sort()).last;
    final items = (versions[latestKey] as Map<String, dynamic>)['items']
        as Map<String, dynamic>;

    Map<String, dynamic>? rootfsItem =
        items['rootfs.tar.xz'] as Map<String, dynamic>?;
    if (rootfsItem == null) {
      for (final v in items.values) {
        final path = (v as Map<String, dynamic>)['path'] as String?;
        if (path != null && path.endsWith('rootfs.tar.xz')) {
          rootfsItem = v;
          break;
        }
      }
    }
    if (rootfsItem == null) {
      throw Exception(
        "Simplestreams product '$simplestreamsProduct' version '$latestKey' "
        "has no rootfs.tar.xz item at $base.",
      );
    }

    return "$base/${rootfsItem['path']}";
  }
}

class DistroSpec {
  final String id; // proot-distro-style alias, e.g. "archlinux"
  final String displayName;
  final String description;
  final PackageManagerFamily packageManager;
  final RootfsSource rootfs;
  // Shell snippet (run as root inside the fresh rootfs via proot) that
  // performs first-boot provisioning: user creation, sudoers, polkit rule,
  // locale setup, and removing Termux-specific profile scripts that don't
  // apply outside the upstream prebuilt image (see upstream
  // tiny-computer/images README's baseline sequence).
  final String Function(String username) firstBootScript;

  const DistroSpec({
    required this.id,
    required this.displayName,
    required this.description,
    required this.packageManager,
    required this.rootfs,
    required this.firstBootScript,
  });

  String get updateCommand => switch (packageManager) {
    PackageManagerFamily.pacman => "pacman -Syu --noconfirm",
    PackageManagerFamily.dnf => "dnf -y upgrade --refresh",
    PackageManagerFamily.apt => "apt-get update && apt-get -y upgrade",
  };

  String installCommand(List<String> packages) => switch (packageManager) {
    PackageManagerFamily.pacman =>
      "pacman -S --noconfirm --needed ${packages.join(' ')}",
    PackageManagerFamily.dnf => "dnf -y install ${packages.join(' ')}",
    PackageManagerFamily.apt =>
      "DEBIAN_FRONTEND=noninteractive apt-get -y install "
          "${packages.join(' ')}",
  };

  String removeCommand(List<String> packages) => switch (packageManager) {
    PackageManagerFamily.pacman =>
      "pacman -Rns --noconfirm ${packages.join(' ')} || true",
    PackageManagerFamily.dnf => "dnf -y remove ${packages.join(' ')} || true",
    PackageManagerFamily.apt =>
      "apt-get -y purge ${packages.join(' ')} || true",
  };
}

const String _removeTermuxProfileScripts =
    "rm -f /etc/profile.d/*termux* /etc/skel/.bashrc.termux 2>/dev/null || true";

String _commonUserSetup(String username) =>
    """
useradd -m -s /bin/bash $username 2>/dev/null || true
echo "$username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$username
chmod 0440 /etc/sudoers.d/$username
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-nopasswd.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel") || subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF
$_removeTermuxProfileScripts""";

String _archFirstBoot(String username) =>
    """
set -e
pacman-key --init
pacman-key --populate archlinux
${_commonUserSetup(username)}
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen""";

String _debianFirstBoot(String username) =>
    """
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install sudo locales policykit-1
${_commonUserSetup(username)}
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen""";

String _rpmFirstBoot(String username) =>
    """
set -e
dnf -y install sudo glibc-langpack-en polkit
${_commonUserSetup(username)}""";

class Distros {
  // Config-driven manifest -- add entries here to support more distros. Do
  // not hardcode the length of this list anywhere; read Distros.all.length.
  static final List<DistroSpec> all = [
    DistroSpec(
      id: "archlinux",
      displayName: "Arch Linux ARM",
      description:
          "Rolling release, pacman. Matches the bundled default container.",
      packageManager: PackageManagerFamily.pacman,
      rootfs: const RootfsSource.direct(
        url: "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz",
        verified: true,
        notes: "Stable, long-standing ArchLinuxARM release path.",
      ),
      firstBootScript: _archFirstBoot,
    ),
    DistroSpec(
      id: "fedora",
      displayName: "Fedora",
      description: "dnf/rpm, current Fedora release cadence.",
      packageManager: PackageManagerFamily.dnf,
      rootfs: const RootfsSource.simplestreams(
        base: "https://images.linuxcontainers.org",
        product: "fedora:41:arm64:default",
        verified: false,
        notes:
            "Fedora's own Container Base images (dl.fedoraproject.org) ship "
            "as OCI tarballs (*.oci.tar.xz) as of Fedora 42, not plain "
            "rootfs tarballs -- this toolchain has no OCI-layer unpacker "
            "(no skopeo/podman), so those can't be used directly. This "
            "entry instead sources from the third-party linuxcontainers.org "
            "image mirror, which needs its product id/version confirmed "
            "against a real device before being trusted for a real install.",
      ),
      firstBootScript: _rpmFirstBoot,
    ),
    DistroSpec(
      id: "debian",
      displayName: "Debian",
      description: "apt/dpkg, stable release.",
      packageManager: PackageManagerFamily.apt,
      rootfs: const RootfsSource.simplestreams(
        base: "https://images.linuxcontainers.org",
        product: "debian:bookworm:arm64:default",
        verified: false,
        notes:
            "Debian does not publish one fixed rootfs tarball URL; this "
            "resolves against linuxcontainers.org's simplestreams index at "
            "install time (see RootfsSource.resolve) instead of a hardcoded "
            "path, but the product id/version still needs confirming "
            "against a real device before being trusted for a real install.",
      ),
      firstBootScript: _debianFirstBoot,
    ),
    DistroSpec(
      id: "ubuntu",
      displayName: "Ubuntu",
      description: "apt/dpkg, LTS release.",
      packageManager: PackageManagerFamily.apt,
      rootfs: const RootfsSource.direct(
        url: "https://cloud-images.ubuntu.com/releases/noble/release/"
            "ubuntu-24.04-server-cloudimg-arm64-root.tar.xz",
        verified: true,
        notes:
            "Official Ubuntu cloud-image release build for 24.04 LTS "
            "(Noble) -- released builds under /releases/<codename>/release/ "
            "are immutable once published, unlike the /current/ daily path.",
      ),
      firstBootScript: _debianFirstBoot,
    ),
  ];

  static DistroSpec byId(String id) =>
      all.firstWhere((d) => d.id == id, orElse: () => all.first);
}
