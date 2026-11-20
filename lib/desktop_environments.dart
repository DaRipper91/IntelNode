// desktop_environments.dart -- desktop environment manifest, tiered by
// maturity under proot + Termux:X11.
//
// Tier.stable entries are the X11 desktops upstream's own container-creation
// guide documents installing via apt; they follow the same shape of install
// sequence across distros with pacman/dnf swapped in for apt, driven by
// DesktopEnvironmentSpec.packagesFor(). Tier.experimental is for sessions that
// are not proven under this app's display path; ContainerInstaller (see
// container_installer.dart) only offers a dry-run preview for them and refuses
// to run their install steps. No experimental entries are defined at the
// moment: the Wayland previews (niri, COSMIC) were removed because they needed
// a nested Wayland-compositor bridge that was never prototyped here.
//
// Adding a new DE (either tier) means adding one entry to
// DesktopEnvironments.all; no selector UI needs to change.
import 'package:da_ripped_tiny_computer/distros.dart';

enum DesktopTier { stable, experimental }

enum SessionType { x11, wayland }

// Shown as separate sections in the first-run picker.
enum DesktopKind { environment, windowManager }

class DesktopEnvironmentSpec {
  final String id;
  final String displayName;
  final String description;
  final DesktopTier tier;
  final SessionType sessionType;
  final DesktopKind kind;
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
    this.kind = DesktopKind.environment,
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
        PackageManagerFamily.pacman: ["xfce4", "xfce4-goodies", "dbus"],
        PackageManagerFamily.dnf: [
          "xfce4-session",
          "xfwm4",
          "xfce4-panel",
          "xfce4-settings",
          "xfce4-terminal",
          "Thunar",
          "xfdesktop",
          "adwaita-icon-theme",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: ["xfce4", "xfce4-goodies", "dbus-x11"],
        PackageManagerFamily.zypper: ["patterns-xfce-xfce", "dbus-1-x11"],
        PackageManagerFamily.apk: ["xfce4", "xfce4-terminal", "dbus-x11"],
        PackageManagerFamily.xbps: ["xfce4", "xfce4-plugins", "dbus-x11"],
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
        PackageManagerFamily.pacman: ["lxqt", "openbox", "dbus"],
        PackageManagerFamily.dnf: [
          "lxqt-session",
          "openbox",
          "lxqt-panel",
          "lxqt-config",
          "qterminal",
          "pcmanfm-qt",
          "lxqt-themes",
          "breeze-icon-theme",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: ["lxqt", "openbox", "dbus-x11"],
        PackageManagerFamily.zypper: ["patterns-lxqt-lxqt", "openbox", "dbus-1-x11"],
        PackageManagerFamily.apk: ["lxqt-desktop", "openbox", "dbus-x11"],
        PackageManagerFamily.xbps: ["lxqt", "openbox", "dbus-x11"],
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
        PackageManagerFamily.pacman: ["mate", "mate-extra", "dbus"],
        PackageManagerFamily.dnf: [
          "mate-session-manager",
          "marco",
          "mate-panel",
          "mate-control-center",
          "mate-terminal",
          "caja",
          "mate-themes",
          "mate-icon-theme",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: ["mate-desktop-environment", "dbus-x11"],
        PackageManagerFamily.zypper: ["patterns-mate-mate", "dbus-1-x11"],
        PackageManagerFamily.apk: ["mate-desktop-environment", "dbus-x11"],
        PackageManagerFamily.xbps: ["mate", "mate-extra", "dbus-x11"],
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
      kind: DesktopKind.windowManager,
      packagesByFamily: {
        PackageManagerFamily.pacman: [
          "i3-wm",
          "i3status",
          "dmenu",
          "xterm",
          "dbus",
        ],
        PackageManagerFamily.dnf: [
          "i3",
          "i3status",
          "dmenu",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: [
          "i3",
          "i3status",
          "suckless-tools",
          "dbus-x11",
        ],
        PackageManagerFamily.zypper: [
          "i3",
          "i3status",
          "dmenu",
          "dbus-1-x11",
        ],
        PackageManagerFamily.apk: [
          "i3wm",
          "i3status",
          "dmenu",
          "xterm",
          "dbus-x11",
        ],
        PackageManagerFamily.xbps: [
          "i3",
          "i3status",
          "dmenu",
          "xterm",
          "dbus-x11",
        ],
      },
      xinitrcExec: "i3",
      xdgDesktopName: "i3",
    ),

    const DesktopEnvironmentSpec(
      id: "openbox",
      displayName: "Openbox",
      description: "Lightweight, highly configurable stacking window manager.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.windowManager,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["openbox", "tint2", "xterm", "dbus"],
        PackageManagerFamily.dnf: ["openbox", "tint2", "xterm", "dbus-x11"],
        PackageManagerFamily.apt: ["openbox", "tint2", "xterm", "dbus-x11"],
        PackageManagerFamily.zypper: ["openbox", "tint2", "xterm", "dbus-1-x11"],
        PackageManagerFamily.apk: ["openbox", "tint2", "xterm", "dbus-x11"],
        PackageManagerFamily.xbps: ["openbox", "tint2", "xterm", "dbus-x11"],
      },
      xinitrcExec: "openbox-session",
      xdgDesktopName: "Openbox",
    ),
    const DesktopEnvironmentSpec(
      id: "fluxbox",
      displayName: "Fluxbox",
      description: "Fast, minimal window manager with tabs and a toolbar.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.windowManager,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["fluxbox", "xterm", "dbus"],
        PackageManagerFamily.dnf: ["fluxbox", "xterm", "dbus-x11"],
        PackageManagerFamily.apt: ["fluxbox", "xterm", "dbus-x11"],
        PackageManagerFamily.zypper: ["fluxbox", "xterm", "dbus-1-x11"],
        PackageManagerFamily.apk: ["fluxbox", "xterm", "dbus-x11"],
        PackageManagerFamily.xbps: ["fluxbox", "xterm", "dbus-x11"],
      },
      xinitrcExec: "startfluxbox",
      xdgDesktopName: "Fluxbox",
    ),
    const DesktopEnvironmentSpec(
      id: "icewm",
      displayName: "IceWM",
      description: "Small, fast window manager with a familiar taskbar.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.windowManager,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["icewm", "xterm", "dbus"],
        PackageManagerFamily.dnf: ["icewm", "xterm", "dbus-x11"],
        PackageManagerFamily.apt: ["icewm", "xterm", "dbus-x11"],
        PackageManagerFamily.zypper: ["icewm", "xterm", "dbus-1-x11"],
        PackageManagerFamily.apk: ["icewm", "xterm", "dbus-x11"],
        PackageManagerFamily.xbps: ["icewm", "xterm", "dbus-x11"],
      },
      xinitrcExec: "icewm-session",
      xdgDesktopName: "IceWM",
    ),
    const DesktopEnvironmentSpec(
      id: "lxde",
      displayName: "LXDE",
      description: "Ultra-lightweight classic desktop. Minimal RAM, fast launch.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.environment,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["lxde", "dbus"],
        PackageManagerFamily.dnf: [
          "lxde-common",
          "lxsession",
          "openbox",
          "lxpanel",
          "lxappearance",
          "lxterminal",
          "pcmanfm",
          "lxde-icon-theme",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: ["lxde", "dbus-x11"],
        PackageManagerFamily.zypper: ["patterns-lxde-lxde", "dbus-1-x11"],
        PackageManagerFamily.apk: ["lxde-core", "dbus-x11"],
        PackageManagerFamily.xbps: ["lxde", "dbus-x11"],
      },
      xinitrcExec: "startlxde",
      xdgDesktopName: "LXDE",
    ),
    const DesktopEnvironmentSpec(
      id: "awesome",
      displayName: "AwesomeWM",
      description: "Highly configurable dynamic tiling & floating window manager.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.windowManager,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["awesome", "dmenu", "xterm", "dbus"],
        PackageManagerFamily.dnf: ["awesome", "dmenu", "xterm", "dbus-x11"],
        PackageManagerFamily.apt: ["awesome", "suckless-tools", "xterm", "dbus-x11"],
        PackageManagerFamily.zypper: ["awesome", "dmenu", "xterm", "dbus-1-x11"],
        PackageManagerFamily.apk: ["awesome", "dmenu", "xterm", "dbus-x11"],
        PackageManagerFamily.xbps: ["awesome", "dmenu", "xterm", "dbus-x11"],
      },
      xinitrcExec: "awesome",
      xdgDesktopName: "awesome",
    ),
    const DesktopEnvironmentSpec(
      id: "bspwm",
      displayName: "bspwm",
      description: "Fast binary space partitioning tiling window manager.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.windowManager,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["bspwm", "sxhkd", "dmenu", "xterm", "dbus"],
        PackageManagerFamily.dnf: ["bspwm", "sxhkd", "dmenu", "xterm", "dbus-x11"],
        PackageManagerFamily.apt: ["bspwm", "sxhkd", "suckless-tools", "xterm", "dbus-x11"],
        PackageManagerFamily.zypper: ["bspwm", "sxhkd", "dmenu", "xterm", "dbus-1-x11"],
        PackageManagerFamily.apk: ["bspwm", "sxhkd", "dmenu", "xterm", "dbus-x11"],
        PackageManagerFamily.xbps: ["bspwm", "sxhkd", "dmenu", "xterm", "dbus-x11"],
      },
      xinitrcExec: "bspwm",
      xdgDesktopName: "bspwm",
    ),
    const DesktopEnvironmentSpec(
      id: "enlightenment",
      displayName: "Enlightenment",
      description: "Fast, elegant EFL-powered desktop with touch profile support.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.environment,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["enlightenment", "terminology", "dbus"],
        PackageManagerFamily.dnf: ["enlightenment", "terminology", "dbus-x11"],
        PackageManagerFamily.apt: ["enlightenment", "terminology", "dbus-x11"],
        PackageManagerFamily.zypper: ["enlightenment", "terminology", "dbus-1-x11"],
        PackageManagerFamily.apk: ["enlightenment", "terminology", "dbus-x11"],
        PackageManagerFamily.xbps: ["enlightenment", "terminology", "dbus-x11"],
      },
      xinitrcExec: "enlightenment_start",
      xdgDesktopName: "Enlightenment",
    ),
    const DesktopEnvironmentSpec(
      id: "cinnamon",
      displayName: "Cinnamon",
      description: "Modern, traditional desktop with start menu and applets.",
      tier: DesktopTier.stable,
      sessionType: SessionType.x11,
      kind: DesktopKind.environment,
      packagesByFamily: {
        PackageManagerFamily.pacman: ["cinnamon", "dbus"],
        PackageManagerFamily.dnf: [
          "cinnamon-session",
          "cinnamon",
          "muffin",
          "cinnamon-control-center",
          "gnome-terminal",
          "nemo",
          "cinnamon-themes",
          "adwaita-icon-theme",
          "dbus-x11",
        ],
        PackageManagerFamily.apt: ["cinnamon-core", "dbus-x11"],
        PackageManagerFamily.zypper: ["patterns-cinnamon-cinnamon", "dbus-1-x11"],
        PackageManagerFamily.apk: ["cinnamon", "dbus-x11"],
        PackageManagerFamily.xbps: ["cinnamon", "dbus-x11"],
      },
      xinitrcExec: "cinnamon-session",
      xdgDesktopName: "X-Cinnamon",
    ),

  ];

  static List<DesktopEnvironmentSpec> forTier(DesktopTier tier) =>
      all.where((d) => d.tier == tier).toList();

  static DesktopEnvironmentSpec byId(String id) =>
      all.firstWhere((d) => d.id == id, orElse: () => all.first);
}
