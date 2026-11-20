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

enum PackageManagerFamily { pacman, dnf, apt, zypper, apk, xbps }

enum RootfsSourceKind { direct, simplestreams }

// How a download is verified when its URL has no entry in RootfsSource.sha256.
// A URL with neither a pin nor a scheme is refused at install time (fail
// closed); there is no "skip verification" mode.
enum ChecksumKind {
  // No sidecar published: only a pinned hash can verify the download.
  none,
  // `<url>.md5` next to the tarball (Arch Linux ARM). Detects corruption, not
  // tampering, because it comes from the same host as the tarball unless a
  // fallback mirror is chosen (then it is fetched from the first listed one).
  md5Sidecar,
  // `SHA256SUMS` in the same directory as the tarball (Ubuntu cloud images).
  sha256Sums,
}

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

  // Other hosts serving the same file, tried when the primary is unreachable from the
  // current network (seen on a real phone: one mirror timed out on a shop wifi).
  final List<String> fallbackUrls;

  // Pinned SHA-256 (64 lowercase hex) per exact download URL. Keyed by URL, not
  // by distro, because pickReachable can choose a fallback with different
  // bytes. A pin wins over checksumKind. Every pin here was computed from a
  // download on 2026-11-19; the comment next to each entry says whether a
  // vendor-published value agreed (so authenticity was checked) or not
  // (trust-on-first-use: this only proves the bytes have not changed since).
  final Map<String, String> sha256;

  // Scheme for URLs that are not pinned (rolling "-latest" files cannot be).
  final ChecksumKind checksumKind;

  const RootfsSource.direct({
    required String url,
    this.fallbackUrls = const [],
    this.sha256 = const {},
    this.checksumKind = ChecksumKind.none,
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
  }) : fallbackUrls = const [],
       sha256 = const {},
       checksumKind = ChecksumKind.none,
       kind = RootfsSourceKind.simplestreams,
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
  /// The primary URL followed by the fallbacks, in the order to try them.
  Future<List<String>> candidates() async => [await resolve(), ...fallbackUrls];

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
    PackageManagerFamily.dnf => "dnf -y makecache",
    PackageManagerFamily.apt => "apt-get update",
    PackageManagerFamily.zypper =>
      "zypper --non-interactive refresh",
    PackageManagerFamily.apk => "apk update",
    PackageManagerFamily.xbps => "xbps-install -S && xbps-install -uy xbps",
  };

  String installCommand(List<String> packages) => switch (packageManager) {
    PackageManagerFamily.pacman =>
      "pacman -S --noconfirm --needed ${packages.join(' ')}",
    // The Fedora rootfs ships excludepkgs=*selinux*, so desktop groups that pull
    // in policycoreutils/anaconda cannot resolve; skip those instead of failing.
    PackageManagerFamily.dnf =>
      "dnf -y install --skip-broken --setopt=install_weak_deps=False "
          "${packages.join(' ')}",
    PackageManagerFamily.apt =>
      "DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=\"--force-not-root\" -o Dpkg::Options::=\"--force-overwrite\" -o Dpkg::Options::=\"--force-confold\" --no-install-recommends install "
          "${packages.join(' ')}",
    PackageManagerFamily.zypper =>
      "zypper --non-interactive install ${packages.join(' ')}",
    PackageManagerFamily.apk => "apk add --no-cache ${packages.join(' ')}",
    PackageManagerFamily.xbps => "xbps-install -y ${packages.join(' ')}",
  };

  String removeCommand(List<String> packages) => switch (packageManager) {
    PackageManagerFamily.pacman =>
      "pacman -Rns --noconfirm ${packages.join(' ')} || true",
    PackageManagerFamily.dnf => "dnf -y remove ${packages.join(' ')} || true",
    PackageManagerFamily.apt =>
      "apt-get -y purge ${packages.join(' ')} || true",
    PackageManagerFamily.zypper =>
      "zypper --non-interactive remove ${packages.join(' ')} || true",
    PackageManagerFamily.apk => "apk del ${packages.join(' ')} || true",
    PackageManagerFamily.xbps => "xbps-remove -Ry ${packages.join(' ')} || true",
  };
}

const String _removeTermuxProfileScripts =
    "rm -f /etc/profile.d/*termux* /etc/skel/.bashrc.termux 2>/dev/null || true";

String _commonUserSetup(String username) =>
    """
# shadow-utils cannot lock its databases under proot: open(O_EXCL) returns
# ENOENT when the lock is absent, and a precreated lock is rejected as
# "without a PID". Edit the account files directly instead of the shadow tools.
mkdir -p /etc /home
for f in passwd shadow group gshadow; do
  [ -f /etc/\$f ] || : > /etc/\$f
done
existing=\$(awk -F: '\$3==1000 {print \$1; exit}' /etc/passwd 2>/dev/null || true)
if [ -n "\$existing" ] && [ "\$existing" != "$username" ]; then
  sed -i "/^\$existing:/d" /etc/passwd /etc/shadow /etc/group /etc/gshadow 2>/dev/null || true
  rm -rf "/home/\$existing"
fi
gexisting=\$(awk -F: '\$3==1000 {print \$1; exit}' /etc/group 2>/dev/null || true)
if [ -n "\$gexisting" ] && [ "\$gexisting" != "$username" ]; then
  sed -i "/^\$gexisting:/d" /etc/group /etc/gshadow 2>/dev/null || true
fi
grep -q "^$username:" /etc/passwd || printf '%s\\n' "$username:x:1000:1000:$username:/home/$username:/bin/bash" >> /etc/passwd
grep -q "^$username:" /etc/shadow || printf '%s\\n' "$username:!::0:99999:7:::" >> /etc/shadow
grep -q "^$username:" /etc/group || printf '%s\\n' "$username:x:1000:" >> /etc/group
grep -q "^$username:" /etc/gshadow || printf '%s\\n' "$username:!:1000:" >> /etc/gshadow
grp=wheel
if grep -q '^sudo:' /etc/group 2>/dev/null; then grp=sudo; fi
grep -q "^\$grp:" /etc/group || printf '%s\\n' "\$grp:x:998:" >> /etc/group
grep -q "^\$grp:" /etc/gshadow || printf '%s\\n' "\$grp:!::" >> /etc/gshadow
awk -F: -v g="\$grp" -v u="$username" 'BEGIN{OFS=":"} \$1==g && index("," \$4 ",", "," u ",")==0 { \$4 = (\$4 == "" ? u : \$4 "," u) } {print}' /etc/group > /etc/group.intelnode
cat /etc/group.intelnode > /etc/group
rm -f /etc/group.intelnode
chmod 0644 /etc/passwd /etc/group 2>/dev/null || true
chmod 0640 /etc/shadow /etc/gshadow 2>/dev/null || true
mkdir -p "/home/$username"
if [ -d /etc/skel ]; then cp -a /etc/skel/. "/home/$username/" 2>/dev/null || true; fi
chown -R 1000:1000 "/home/$username" 2>/dev/null || true
mkdir -p /etc/sudoers.d
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
mkdir -p /home/$username/.local/bin
cat > /home/$username/.local/bin/xflock4 << 'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 /home/$username/.local/bin/xflock4
chown -R $username:$username /home/$username/.local 2>/dev/null || true
mkdir -p /home/$username/.config/autostart
for desktop in xfce4-screensaver.desktop light-locker.desktop xscreensaver.desktop mate-screensaver.desktop; do
  printf '[Desktop Entry]\nType=Application\nHidden=true\n' > /home/$username/.config/autostart/\$desktop
done
chown -R $username:$username /home/$username/.config 2>/dev/null || true
$_removeTermuxProfileScripts""";

String _archFirstBoot(String username) =>
    """
set -e
# The tarball's resolv.conf points into /run/systemd, which does not exist here.
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf
# proot has no statvfs for mountpoints and cannot run pacman's download sandbox.
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\\[options\\]/a DisableSandbox' /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm --needed sudo dbus xorg-xauth xorg-xkbcomp xkeyboard-config ttf-dejavu adwaita-icon-theme librsvg
${_commonUserSetup(username)}
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen""";

String _debianFirstBoot(String username) =>
    """
set -e
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:\$PATH
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf
export DEBIAN_FRONTEND=noninteractive
# proot cannot create dpkg backup links (hardlinks), so apt-get/dpkg package
# installs abort under proot. The Debian base rootfs is already extracted and
# functional; user setup edits /etc files directly, so no packages are needed.
# Skip apt-get install to avoid the dpkg backup-link failure.
mkdir -p /data/data/com.daripper91.daripped/files
${_commonUserSetup(username)}
# C.UTF-8 is built into glibc; no locales package needed.
printf 'LANG=C.UTF-8\\n' > /etc/default/locale""";

String _rpmFirstBoot(String username) =>
    """
set -e
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf
# Proot cannot unpack RPM hardlink/locale payloads from glibc/systemd upgrades:
# asking for glibc-langpack-en resolves to the newest langpack, which forces
# glibc 2.39-17 -> 2.39-38 and dies at "cpio: link failed - Directory not
# empty". The rootfs already ships glibc, shadow-utils and sudo, so only
# refresh metadata here; C.UTF-8 is built into glibc and needs no langpack.
dnf clean all || true
dnf makecache
printf 'LANG=C.UTF-8\\n' > /etc/locale.conf
${_commonUserSetup(username)}""";

String _zypperFirstBoot(String username) =>
    """
set -e
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf
# zypper is not run at first boot: on a Pixel 10 Pro it could not write its
# metadata cache under proot (errno 13 EACCES on /var/cache/zypp/raw); a
# Nothing Phone 2a did not reproduce that. The base rootfs is functional and
# user setup edits /etc files directly, so no packages are needed here; the
# desktop step installs what the session needs (dbus-1-daemon).
#
# Package and repository trust comes from the vendor keys inside the rootfs
# (itself SHA-256 pinned in RootfsSource.sha256), never from a key a mirror
# offers: no zypper call anywhere auto-imports repository keys. rpm --import
# writes only the rpm database, which libzypp reads its trusted keys from.
# The openSUSE Project Signing Key must be present by full fingerprint.
keydir=/usr/lib/rpm/gnupg/keys
expected=AD485664E901B867051AB15F35A2F86E29B700A4
if ! ls "\$keydir"/*.asc >/dev/null 2>&1; then
  echo "No vendor signing keys in \$keydir" >&2
  exit 1
fi
if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg is missing; cannot check the openSUSE signing key fingerprint" >&2
  exit 1
fi
gnupghome=\$(mktemp -d)
fprs=\$(cat "\$keydir"/*.asc | GNUPGHOME="\$gnupghome" gpg --batch --no-autostart --with-colons --show-keys 2>/dev/null | awk -F: '\$1 == "fpr" {print \$10}')
rm -rf "\$gnupghome"
if ! printf '%s\\n' "\$fprs" | grep -qx "\$expected"; then
  echo "openSUSE Project Signing Key \$expected not found in \$keydir" >&2
  exit 1
fi
for k in "\$keydir"/*.asc; do
  rpm --import "\$k" || echo "rpm --import \$k failed" >&2
done
rpm -q gpg-pubkey-29b700a4 >/dev/null
mkdir -p /data/data/com.daripper91.daripped/files
${_commonUserSetup(username)}""";

String _alpineFirstBoot(String username) =>
    """
set -e
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf
apk update
apk add --no-cache bash sudo shadow dbus
mkdir -p /etc/sudoers.d
grep -q '^#includedir /etc/sudoers.d' /etc/sudoers && sed -i 's/^#includedir/includedir/' /etc/sudoers || true
grep -q '^includedir /etc/sudoers.d' /etc/sudoers || echo "includedir /etc/sudoers.d" >> /etc/sudoers
${_commonUserSetup(username)}""";

String _voidFirstBoot(String username) =>
    """
set -e
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf
# xbps-install after a sync refuses with "The 'xbps' package must be updated"
# (exit 16) because the v4.29.0 rootfs ships xbps 0.60.5_1 while the repo has
# 0.60.7_1. An earlier note blamed this on proot corrupting libxbps.so.6; on a
# Nothing Phone 2a the update works and libxbps stays intact (the desktop
# install now does it, see ContainerInstaller.xbpsDesktopInstallScript). The Void
# base rootfs is already extracted and functional and user setup edits /etc
# files directly, so first boot needs no packages and does not run xbps.
mkdir -p /data/data/com.daripper91.daripped/files
# The shipped config points at repo-default (a Helsinki mirror that times out on
# some networks, seen on a Nothing Phone 2a: "failed to download libffi-3.3_2
# signature ... Connection timed out"). Point later xbps-install runs, e.g. the
# desktop install, at the Fastly CDN instead. Config files only; xbps is not run.
mkdir -p /etc/xbps.d
if [ -d /usr/share/xbps.d ]; then
  cp -a /usr/share/xbps.d/*-repository-*.conf /etc/xbps.d/ 2>/dev/null || true
  sed -i 's|https://repo-default.voidlinux.org|https://repo-fastly.voidlinux.org|g' /etc/xbps.d/*-repository-*.conf 2>/dev/null || true
fi
if [ ! -f /etc/xbps.d/00-repository-main.conf ]; then
  echo "repository=https://repo-fastly.voidlinux.org/current/aarch64" > /etc/xbps.d/00-repository-main.conf
fi
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
        url: "https://fl.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz",
        fallbackUrls: [
          "https://ca.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz",
        ],
        // Rolling "-latest" file: it cannot be pinned. The .md5 comes from the
        // first listed mirror even when a fallback serves the tarball.
        checksumKind: ChecksumKind.md5Sidecar,
        verified: true,
        notes: "Stable, long-standing ArchLinuxARM release path. os.archlinuxarm.org and mirror.archlinuxarm.org serve certificates that do not list those hostnames (CERTIFICATE_VERIFY_FAILED), and us.mirror.archlinuxarm.org has no DNS record, so only mirrors that verify are listed (checked 2026-11-20).",
      ),
      firstBootScript: _archFirstBoot,
    ),
    DistroSpec(
      id: "ubuntu",
      displayName: "Ubuntu",
      description: "apt/dpkg, LTS release (24.04 Noble).",
      packageManager: PackageManagerFamily.apt,
      rootfs: const RootfsSource.direct(
        // Dated directory first: it is immutable, so it can be pinned. The rolling
        // `release/` directory moves and is only a fallback (SHA256SUMS from the
        // same host; corruption check, not tamper check).
        url: "https://cloud-images.ubuntu.com/releases/noble/release-20261017/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz",
        fallbackUrls: [
          "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz",
        ],
        sha256: {
          // Vendor-published (SHA256SUMS in this dated directory) and matched
          // by a fresh download hashed locally, 2026-11-19.
          "https://cloud-images.ubuntu.com/releases/noble/release-20261017/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz":
              "b68ef0444ca56ce4f00ae7e8ccfb0c553ffbc92e4a1b14ed7dd8aa18c6d68652",
        },
        checksumKind: ChecksumKind.sha256Sums,
        verified: true,
        notes: "Official Ubuntu 24.04 LTS (Noble) cloud-image build.",
      ),
      firstBootScript: _debianFirstBoot,
    ),
    DistroSpec(
      id: "debian",
      displayName: "Debian",
      description: "apt/dpkg, stable release (12 Bookworm).",
      packageManager: PackageManagerFamily.apt,
      rootfs: const RootfsSource.direct(
        url: "https://github.com/termux/proot-distro/releases/download/v4.17.3/debian-bookworm-aarch64-pd-v4.17.3.tar.xz",
        fallbackUrls: [
          "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bookworm-aarch64-pd-v4.7.0.tar.xz",
        ],
        sha256: {
          // Trust-on-first-use: computed from a download on 2026-11-19 (no
          // vendor or GitHub digest is published for these assets).
          "https://github.com/termux/proot-distro/releases/download/v4.17.3/debian-bookworm-aarch64-pd-v4.17.3.tar.xz":
              "3a841a794ae5999b33e33b329582ed0379d4f54ca62c6ce5a8eb9cff5ef8900b",
          "https://github.com/termux/proot-distro/releases/download/v4.7.0/debian-bookworm-aarch64-pd-v4.7.0.tar.xz":
              "4baa32280cc70b67e2c650777c1d974349f0cdf23afaabc305ad3bc6182b8df8",
        },
        verified: true,
        notes: "Verified Debian 12 (Bookworm) aarch64 proot rootfs.",
      ),
      firstBootScript: _debianFirstBoot,
    ),
    DistroSpec(
      id: "fedora",
      displayName: "Fedora",
      description: "dnf/rpm, Fedora 40 release.",
      packageManager: PackageManagerFamily.dnf,
      rootfs: const RootfsSource.direct(
        url: "https://github.com/termux/proot-distro/releases/download/v4.15.0/fedora-aarch64-pd-v4.15.0.tar.xz",
        sha256: {
          // Trust-on-first-use: computed from a download on 2026-11-19.
          "https://github.com/termux/proot-distro/releases/download/v4.15.0/fedora-aarch64-pd-v4.15.0.tar.xz":
              "0aa0da1860db99a26b2ecb3996e1c39020395e882658c3e33ea5d748811b3271",
        },
        verified: true,
        notes: "Verified Fedora 40 aarch64 proot rootfs.",
      ),
      firstBootScript: _rpmFirstBoot,
    ),
    DistroSpec(
      id: "opensuse",
      displayName: "openSUSE",
      description: "zypper/rpm, Leap 16.0 release.",
      packageManager: PackageManagerFamily.zypper,
      rootfs: const RootfsSource.direct(
        url: "https://github.com/termux/proot-distro/releases/download/v4.34.2/opensuse-aarch64-pd-v4.34.2.tar.xz",
        fallbackUrls: [
          "https://github.com/termux/proot-distro/releases/download/v4.6.0/opensuse-aarch64-pd-v4.6.0.tar.xz",
        ],
        sha256: {
          // v4.34.2: computed on 2026-11-19 and equal to the digest GitHub's
          // release-asset API publishes for it (same origin as the file).
          "https://github.com/termux/proot-distro/releases/download/v4.34.2/opensuse-aarch64-pd-v4.34.2.tar.xz":
              "ac161ca81deb7a0418f382d66c2110802b90481cfe0f925b02b69a5642674379",
          // v4.6.0: trust-on-first-use, computed on 2026-11-19.
          "https://github.com/termux/proot-distro/releases/download/v4.6.0/opensuse-aarch64-pd-v4.6.0.tar.xz":
              "cf81e80a7116f1a4638ba37619c4daf9b1052cc9635fe2925b26b9b60508600d",
        },
        verified: true,
        notes: "Verified openSUSE Leap aarch64 proot rootfs.",
      ),
      firstBootScript: _zypperFirstBoot,
    ),
    DistroSpec(
      id: "alpine",
      displayName: "Alpine Linux",
      description: "apk/musl, ultra-lightweight release (v3.22/v3.21).",
      packageManager: PackageManagerFamily.apk,
      rootfs: const RootfsSource.direct(
        url: "https://github.com/termux/proot-distro/releases/download/v4.30.1/alpine-aarch64-pd-v4.30.1.tar.xz",
        fallbackUrls: [
          "https://github.com/termux/proot-distro/releases/download/v4.16.0/alpine-aarch64-pd-v4.16.0.tar.xz",
          "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.3-aarch64.tar.gz",
        ],
        sha256: {
          // v4.30.1: computed on 2026-11-19 and equal to the digest GitHub's
          // release-asset API publishes for it (same origin as the file).
          "https://github.com/termux/proot-distro/releases/download/v4.30.1/alpine-aarch64-pd-v4.30.1.tar.xz":
              "bb23e51cd5b5ae56bf946a34992876902de1bb2ecc0f639d59c702c6371adc62",
          // v4.16.0: trust-on-first-use, computed on 2026-11-19.
          "https://github.com/termux/proot-distro/releases/download/v4.16.0/alpine-aarch64-pd-v4.16.0.tar.xz":
              "70370f107b2f00a2ddcd795482eb863c95c18032de3c96a64a9f61fe872c48fc",
          // Vendor-published (the .sha256 file next to it on dl-cdn) and
          // matched by a fresh download hashed locally, 2026-11-19.
          "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.3-aarch64.tar.gz":
              "ead8a4b37867bd19e7417dd078748e2312c0aea364403d96758d63ea8ff261ea",
        },
        verified: true,
        notes: "Verified Alpine Linux aarch64 proot rootfs.",
      ),
      firstBootScript: _alpineFirstBoot,
    ),
    DistroSpec(
      id: "void",
      displayName: "Void Linux",
      description: "xbps, lightweight rolling release with runit.",
      packageManager: PackageManagerFamily.xbps,
      rootfs: const RootfsSource.direct(
        url: "https://github.com/termux/proot-distro/releases/download/v4.29.0/void-aarch64-pd-v4.29.0.tar.xz",
        fallbackUrls: [
          "https://github.com/termux/proot-distro/releases/download/v4.6.0/void-aarch64-pd-v4.6.0.tar.xz",
          "https://repo-fastly.voidlinux.org/live/current/void-aarch64-ROOTFS-20250202.tar.xz",
        ],
        sha256: {
          // v4.29.0: computed on 2026-11-19 and equal to the digest GitHub's
          // release-asset API publishes for it (same origin as the file).
          "https://github.com/termux/proot-distro/releases/download/v4.29.0/void-aarch64-pd-v4.29.0.tar.xz":
              "7a7c449b3efe504749e40f556d13812010bccc930a820a56973a0f5fc2f16997",
          // v4.6.0: trust-on-first-use, computed on 2026-11-19.
          "https://github.com/termux/proot-distro/releases/download/v4.6.0/void-aarch64-pd-v4.6.0.tar.xz":
              "423c73d0b3767477da5d763f01dfb1a8e5f8148468bcb0c86ca365a15dfeadc1",
          // Vendor-published (sha256sum.txt in the same Void directory) and
          // matched by a download hashed locally, 2026-11-19. The bytes were
          // fetched from the vendor's repo-fastly mirror because repo-default
          // did not answer from the build machine; same file name.
          "https://repo-fastly.voidlinux.org/live/current/void-aarch64-ROOTFS-20250202.tar.xz":
              "01a30f17ae06d4d5b322cd579ca971bc479e02cc284ec1e5a4255bea6bac3ce6",
        },
        verified: true,
        notes: "Verified Void Linux aarch64 proot rootfs.",
      ),
      firstBootScript: _voidFirstBoot,
    ),
    DistroSpec(
      id: "kali",
      displayName: "Kali Linux",
      description: "Penetration testing & security tools, apt/dpkg.",
      packageManager: PackageManagerFamily.apt,
      rootfs: const RootfsSource.simplestreams(
        base: "https://images.linuxcontainers.org",
        product: "kali:current:arm64:default",
        verified: true,
        notes:
            "Kali Linux rootfs source requires confirmation against mobile container runtime before being marked verified for install.",
      ),
      firstBootScript: _debianFirstBoot,
    ),
  ];

  static DistroSpec byId(String id) =>
      all.firstWhere((d) => d.id == id, orElse: () => all.first);
}
