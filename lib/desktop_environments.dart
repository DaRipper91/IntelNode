// desktop_environments.dart -- desktop environment manifest, tiered by
// maturity under proot + Termux:X11.
//
// Tier.stable entries are the X11 desktops upstream's own container-creation
// guide documents installing via apt; they follow the same shape of install
// sequence across distros with pacman/dnf swapped in for apt, driven by
// DesktopEnvironmentSpec.packagesFor(). Tier.experimental entries are
// Wayland compositors that would need a nested Wayland-compositor-to-
// display-backend bridge instead of the Termux:X11-as-X-server model
// Tier.stable relies on -- that bridge is unprototyped in this codebase, so
// ContainerInstaller (see container_installer.dart) only offers a dry-run
// preview for them and refuses to actually run their install steps.
//
// Adding a new DE (either tier) means adding one entry to
// DesktopEnvironments.all; no selector UI needs to change.
import 'package:da_ripped_tiny_computer/distros.dart';

enum DesktopTier { stable, experimental }

enum SessionType { x11, wayland }

class DesktopEnvironmentSpec {
  final String id;
  final String displayName;
  final String description;
  final DesktopTier tier;
  final SessionType sessionType;
  // Packages to install, keyed by package manager family. Package names
  // genuinely differ per distro for some desktops (not just per package
  // manager family) -- packagesByDistroId overrides packagesByFamily when
  // present for that distro id.
  final Map<PackageManagerFamily, List<String>> packagesByFamily;
  final Map<String, List<String>> packagesByDistroId;
  final String xinitrcExec; // command exec'd from .xinitrc / start-desktop
  final String xdgDesktopName; // XDG_CURRENT_DESKTOP value
  // Populated only for experimental entries: explains what remains
  // unvalidated before this can be presented as "supported" rather than a
  // preview.
  final String? experimentalCaveat;

  const DesktopEnvironmentSpec({
    required this.id,
    required this.displayName,
    required this.description,
    required this.tier,
    required this.sessionType,
    required this.packagesByFamily,
    this.packagesByDistroId = const {},
    required this.xinitrcExec,
    required this.xdgDesktopName,
    this.experimentalCaveat,
  });

  List<String> packagesFor(DistroSpec distro) =>
      packagesByDistroId[distro.id] ??
      packagesByFamily[distro.packageManager] ??
      const [];
}

class DesktopEnvironments {
  // Config-driven manifest -- add entries here to support more desktops. Do
  // not hardcode the length of this list, or of forTier() results, anywhere.
  static final List<DesktopEnvironmentSpec> all = [
    // ---- Tier 1: stable (X11) ----
    const DesktopEnvironmentSpec(
      id: "xfce4",
      displayName: "XFCE4",
      description: "Classic, feature-rich desktop. Best compatibility.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["xfce4", "xfce4-goodies", "dbus-x11"],
        PackageManagerFamily.dnf: ["@xfce-desktop-environment", "dbus-x11"],
        PackageManagerFamily.apt: ["xfce4", "xfce4-goodies", "dbus-x11"],
      },
      xinitrcExec: "startxfce4",
      xdgDesktopName: "XFCE",
    ),
    const DesktopEnvironmentSpec(
      id: "lxqt",
      displayName: "LXQt",
      description: "Lightweight, modern Qt-based desktop. Lower RAM usage.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["lxqt", "openbox", "dbus-x11"],
        PackageManagerFamily.dnf: ["@lxqt-desktop-environment", "dbus-x11"],
        PackageManagerFamily.apt: ["lxqt", "openbox", "dbus-x11"],
      },
      xinitrcExec: "startlxqt",
      xdgDesktopName: "LXQt",
    ),
    const DesktopEnvironmentSpec(
      id: "mate",
      displayName: "MATE",
      description: "Traditional GNOME 2-style desktop.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["mate", "mate-extra", "dbus-x11"],
        PackageManagerFamily.dnf: ["@mate-desktop-environment", "dbus-x11"],
        PackageManagerFamily.apt: ["mate-desktop-environment", "dbus-x11"],
      },
      xinitrcExec: "mate-session",
      xdgDesktopName: "MATE",
    ),
    const DesktopEnvironmentSpec(
      id: "i3",
      displayName: "i3wm",
      description: "Manual tiling window manager, minimal footprint.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      packagesByFamily: {
        PackageManagerFamily.pacman: [
          "i3-wm",
          "i3status",
          "i3lock",
          "dmenu",
          "dbus-x11",
        ],
        PackageManagerFamily.dnf: [
          "i3",
          "i3status",
          "i3lock",
          "dmenu",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: [
          "i3",
          "i3status",
          "i3lock",
          "suckless-tools",
          "dbus-x11",
        ],
      },
      xinitrcExec: "i3",
      xdgDesktopName: "i3",
    ),

    // ---- Tier 2: experimental (Wayland) ----
    const DesktopEnvironmentSpec(
      id: "niri",
      displayName: "niri",
      description: "Scrollable-tiling Wayland compositor. Experimental.",
      tier: DesktopTier.experimental,
      sessionType: SessionType.wayland,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["niri", "xwayland-satellite"],
        PackageManagerFamily.dnf: ["niri", "xwayland-satellite"],
        PackageManagerFamily.apt: ["niri", "xwayland-satellite"],
      },
      xinitrcExec: "niri-session",
      xdgDesktopName: "niri",
      experimentalCaveat:
          "niri is Wayland-only and needs xwayland-satellite for X11 app "
          "compatibility. This app's display path (Termux:X11 acting as an "
          "X server the container connects to as a client) has no proven "
          "nested Wayland-compositor bridge -- getting niri's own output "
          "onto Termux:X11/AVNC/noVNC needs prototyping (Arch first, per "
          "package freshness) before this can ship as supported rather than "
          "a preview. Package availability also varies by distro today "
          "(AUR on Arch, COPR on Fedora, no official Debian/Ubuntu "
          "packages) -- verify before install.",
    ),
    const DesktopEnvironmentSpec(
      id: "cosmic",
      displayName: "COSMIC",
      description: "System76's Wayland desktop. Experimental.",
      tier: DesktopTier.experimental,
      sessionType: SessionType.wayland,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["cosmic-session"],
        PackageManagerFamily.dnf: ["cosmic-desktop"],
        PackageManagerFamily.apt: ["cosmic-session"],
      },
      xinitrcExec: "cosmic-session",
      xdgDesktopName: "COSMIC",
      experimentalCaveat:
          "COSMIC is Wayland-only with no mature X11 fallback path -- same "
          "unproven nested-compositor-bridge problem as niri. Packages are "
          "unofficial/repo-specific on every target distro today (AUR on "
          "Arch, COPR on Fedora, no official Debian/Ubuntu packages). If "
          "the bridge prototype on Arch turns out to need substantially "
          "more custom work than niri's, the simpler fallback is to skip "
          "native Wayland output entirely and only ship COSMIC's apps "
          "running under Xwayland, rather than a full compositor bridge.",
    ),
  ];

  static List<DesktopEnvironmentSpec> forTier(DesktopTier tier) =>
      all.where((d) => d.tier == tier).toList();

  static DesktopEnvironmentSpec byId(String id) =>
      all.firstWhere((d) => d.id == id, orElse: () => all.first);
}
