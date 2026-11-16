#!/bin/bash
set -euo pipefail

# =============================================================================
# build-arch-rootfs.sh — Build Arch Linux ARM rootfs for DaRipped tiny_computer
# =============================================================================
# Prerequisites: 
#   - Arch Linux or CachyOS host (for systemd-nspawn + pacstrap)
#   - OR: any Linux with qemu-user-static-binfmt for cross-arch
#   - Root/sudo access on the build machine
#   - ~8GB free disk space
#
# Usage: sudo ./build-arch-rootfs.sh [--xfce|--lxqt] [--split-size SIZE]
# =============================================================================

DE="${1:---xfce}"
SPLIT_SIZE="${2:-98M}"
WORKDIR="$(pwd)/archroot-build"
ROOTFS="$WORKDIR/rootfs"
OUTPUT="$WORKDIR/output"

echo "=== DaRipped Arch Linux ARM rootfs Builder ==="
echo "Desktop: $DE"
echo "Split size: $SPLIT_SIZE"
echo "Working directory: $WORKDIR"
echo ""

# Step 1: Download Arch Linux ARM rootfs
echo "[1/8] Downloading Arch Linux ARM rootfs..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"
if [ ! -f ArchLinuxARM-aarch64-latest.tar.gz ]; then
    wget -c http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
fi

# Step 2: Extract base rootfs
echo "[2/8] Extracting base rootfs..."
if [ ! -d "$ROOTFS" ]; then
    mkdir -p "$ROOTFS"
    sudo tar xzf ArchLinuxARM-aarch64-latest.tar.gz -C "$ROOTFS"
else
    echo "Rootfs directory already exists. Skipping extraction to preserve progress/cache."
    echo "If you want a fresh build, delete $ROOTFS first."
fi

# Step 3: Configure inside container
echo "[3/8] Configuring system inside container..."
sudo systemd-nspawn -D "$ROOTFS" --bind-ro=/etc/resolv.conf /bin/bash -c '
    # Initialize pacman
    pacman-key --init
    pacman-key --populate archlinuxarm

    # Enable parallel downloads and color
    sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 5/" /etc/pacman.conf
    sed -i "/^\[options\]/a DisableDownloadTimeout" /etc/pacman.conf
    sed -i "s/#Color/Color/" /etc/pacman.conf

    # Disable sandbox (Landlock/Seccomp not available inside nspawn container)
    sed -i "s/#DisableSandboxFilesystem/DisableSandboxFilesystem/" /etc/pacman.conf
    sed -i "s/#DisableSandboxSyscalls/DisableSandboxSyscalls/" /etc/pacman.conf
    # Also handle the generic DisableSandbox if present
    sed -i "s/#DisableSandbox/DisableSandbox/" /etc/pacman.conf

    # Create vconsole.conf to prevent mkinitcpio warning
    touch /etc/vconsole.conf

    # Full system update
    pacman -Syu --noconfirm --overwrite "*"
'


# Step 4: Install desktop environments and mobile-friendly tools
echo "[4/8] Installing desktop environments and mobile optimizations..."
sudo systemd-nspawn -D "$ROOTFS" --bind-ro=/etc/resolv.conf /bin/bash -c "
    pacman -S --noconfirm --overwrite '*' \
        xfce4 xfce4-goodies xfce4-terminal \
        lxqt openbox \
        tigervnc \
        python python-pip python-numpy \
        firefox \
        noto-fonts noto-fonts-cjk ttf-dejavu \
        sudo base-devel git wget curl \
        bash-completion htop nano vim \
        xdg-utils xdg-user-dirs dbus \
        xorg-server xorg-xinit xorg-xauth \
        at-spi2-core \
        onboard plank \
        breeze-gtk papirus-icon-theme
"

# Step 5: Install noVNC
echo "[5/8] Installing noVNC..."
sudo systemd-nspawn -D "$ROOTFS" --bind-ro=/etc/resolv.conf /bin/bash -c '
    # Install websockify via pip (missing in Arch ARM repos)
    pip install --break-system-packages websockify

    cd /tmp
    git clone --depth 1 https://github.com/novnc/noVNC.git /usr/share/novnc
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html
    rm -rf /usr/share/novnc/.git
'

# Step 6: Configure users, locale, scripts, and mobile UI
echo "[6/8] Configuring users, locale, and mobile-friendly UI..."
sudo systemd-nspawn -D "$ROOTFS" /bin/bash -c '
    # Create user
    useradd -m -G wheel -s /bin/bash tiny
    echo "tiny:tiny" | chpasswd
    
    # Sudoers
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel
    
    # Configure XFCE for Touch/Mobile
    su - tiny -c "mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml"
    
    # Increase Icon Size and Panel Height for touch
    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-panel\" version=\"1.0\">
  <property name=\"panels\" type=\"array\">
    <value type=\"int\" value=\"1\"/>
  </property>
  <property name=\"panel-1\" type=\"empty\">
    <property name=\"position\" type=\"string\" value=\"p=6;x=0;y=0\"/>
    <property name=\"size\" type=\"uint\" value=\"48\"/>
    <property name=\"icon-size\" type=\"uint\" value=\"32\"/>
    <property name=\"plugin-ids\" type=\"array\">
      <value type=\"int\" value=\"1\"/>
      <value type=\"int\" value=\"2\"/>
      <value type=\"int\" value=\"3\"/>
    </property>
  </property>
</channel>
EOF"

    # Set modern theme and icons
    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xsettings\" version=\"1.0\">
  <property name=\"Net\" type=\"empty\">
    <property name=\"ThemeName\" type=\"string\" value=\"Breeze-Dark\"/>
    <property name=\"IconThemeName\" type=\"string\" value=\"Papirus-Dark\"/>
  </property>
</channel>
EOF"

    # Suppress lock screen, DPMS, and screensavers for mobile container UX
    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-power-manager\" version=\"1.0\">
  <property name=\"xfce4-power-manager\" type=\"empty\">
    <property name=\"lock-screen-suspend-hibernate\" type=\"bool\" value=\"false\"/>
    <property name=\"dpms-enabled\" type=\"bool\" value=\"false\"/>
    <property name=\"presentation-mode\" type=\"bool\" value=\"true\"/>
    <property name=\"blank-on-ac\" type=\"int\" value=\"0\"/>
    <property name=\"blank-on-battery\" type=\"int\" value=\"0\"/>
    <property name=\"dpms-on-ac-sleep\" type=\"int\" value=\"0\"/>
    <property name=\"dpms-on-ac-off\" type=\"int\" value=\"0\"/>
    <property name=\"dpms-on-battery-sleep\" type=\"int\" value=\"0\"/>
    <property name=\"dpms-on-battery-off\" type=\"int\" value=\"0\"/>
    <property name=\"power-button-action\" type=\"uint\" value=\"0\"/>
    <property name=\"sleep-button-action\" type=\"uint\" value=\"0\"/>
    <property name=\"hibernate-button-action\" type=\"uint\" value=\"0\"/>
    <property name=\"battery-button-action\" type=\"uint\" value=\"0\"/>
  </property>
</channel>
EOF"

    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-screensaver\" version=\"1.0\">
  <property name=\"saver\" type=\"empty\">
    <property name=\"enabled\" type=\"bool\" value=\"false\"/>
    <property name=\"mode\" type=\"int\" value=\"0\"/>
    <property name=\"idle-activation-enabled\" type=\"bool\" value=\"false\"/>
  </property>
  <property name=\"lock\" type=\"empty\">
    <property name=\"enabled\" type=\"bool\" value=\"false\"/>
    <property name=\"saver-activation\" type=\"empty\">
      <property name=\"enabled\" type=\"bool\" value=\"false\"/>
      <property name=\"delay\" type=\"int\" value=\"0\"/>
    </property>
    <property name=\"user-switch\" type=\"empty\">
      <property name=\"enabled\" type=\"bool\" value=\"false\"/>
    </property>
    <property name=\"logout\" type=\"empty\">
      <property name=\"enabled\" type=\"bool\" value=\"false\"/>
    </property>
  </property>
</channel>
EOF"

    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-session\" version=\"1.0\">
  <property name=\"general\" type=\"empty\">
    <property name=\"LockCommand\" type=\"string\" value=\"/bin/true\"/>
  </property>
  <property name=\"shutdown\" type=\"empty\">
    <property name=\"ShowSuspend\" type=\"bool\" value=\"false\"/>
    <property name=\"ShowHibernate\" type=\"bool\" value=\"false\"/>
  </property>
</channel>
EOF"

    # XFCE Window Manager performance tuning: disable compositing, vblank blocking, and shadows
    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfwm4\" version=\"1.0\">
  <property name=\"general\" type=\"empty\">
    <property name=\"use_compositing\" type=\"bool\" value=\"false\"/>
    <property name=\"vblank_mode\" type=\"string\" value=\"off\"/>
    <property name=\"show_dock_shadow\" type=\"bool\" value=\"false\"/>
    <property name=\"show_frame_shadow\" type=\"bool\" value=\"false\"/>
    <property name=\"show_popup_shadow\" type=\"bool\" value=\"false\"/>
    <property name=\"box_move\" type=\"bool\" value=\"true\"/>
    <property name=\"box_resize\" type=\"bool\" value=\"true\"/>
    <property name=\"unredirect_overlays\" type=\"bool\" value=\"true\"/>
  </property>
</channel>
EOF"

    # XSettings: disable animations and cursor blink
    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xsettings\" version=\"1.0\">
  <property name=\"Net\" type=\"empty\">
    <property name=\"CursorBlink\" type=\"bool\" value=\"false\"/>
  </property>
  <property name=\"Xft\" type=\"empty\">
    <property name=\"RGBA\" type=\"string\" value=\"none\"/>
  </property>
  <property name=\"Gtk\" type=\"empty\">
    <property name=\"EnableAnimations\" type=\"bool\" value=\"false\"/>
    <property name=\"CursorBlink\" type=\"bool\" value=\"false\"/>
    <property name=\"DecorationLayout\" type=\"string\" value=\"icon,menu:minimize,maximize,close\"/>
  </property>
</channel>
EOF"

    # Thunar: disable thumbnail generation CPU storms
    su - tiny -c "cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml << EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"thunar\" version=\"1.0\">
  <property name=\"last-view\" type=\"string\" value=\"ThunarIconView\"/>
  <property name=\"misc-thumbnail-mode\" type=\"string\" value=\"THUNAR_THUMBNAIL_MODE_NEVER\"/>
  <property name=\"misc-thumbnail-draw-frames\" type=\"bool\" value=\"false\"/>
</channel>
EOF"

    # GTK settings
    su - tiny -c "mkdir -p ~/.config/gtk-3.0 && cat > ~/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-enable-animations = false
gtk-cursor-blink = false
gtk-xft-rgba = none
EOF"

    su - tiny -c "cat > ~/.gtkrc-2.0 << EOF
gtk-enable-animations = 0
gtk-cursor-blink = 0
EOF"

    # Mask out screensaver autostarts
    su - tiny -c "mkdir -p ~/.config/autostart && for desktop in xfce4-screensaver.desktop light-locker.desktop xscreensaver.desktop mate-screensaver.desktop; do
        printf '[Desktop Entry]\nType=Application\nHidden=true\n' > ~/.config/autostart/\$desktop
    done"

    # Stub out locker scripts and pm-is-supported
    su - tiny -c "mkdir -p ~/.local/bin && for stub in xflock4 xfce4-screensaver xfce4-screensaver-command light-locker light-locker-command xscreensaver xscreensaver-command mate-screensaver mate-screensaver-command i3lock; do
        printf '#!/bin/sh\nexit 0\n' > ~/.local/bin/\$stub
        chmod +x ~/.local/bin/\$stub
    done && printf '#!/bin/sh\nexit 1\n' > ~/.local/bin/pm-is-supported && chmod +x ~/.local/bin/pm-is-supported"

    ln -sf /bin/true /usr/local/bin/xflock4
    ln -sf /bin/true /usr/bin/xflock4

    # Locale
    sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    
    # X session init
    cat > /etc/X11/xinit/xinitrc << "XINITRC"
#!/bin/bash
exec bash ~/.xinitrc
XINITRC
    chmod +x /etc/X11/xinit/xinitrc
    
    # User xinitrc
    su - tiny -c "cat > ~/.xinitrc << EOF
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
# Start Plank and Onboard in background for mobile feel
plank &
onboard &
exec startxfce4
EOF
chmod +x ~/.xinitrc"
    
    # VNC scripts
    cat > /usr/local/bin/start-vnc << "SCRIPT"
#!/bin/bash
export USER=tiny HOME=/home/tiny DISPLAY=:4
vncserver -kill :4 2>/dev/null || true
mkdir -p /home/tiny/.vnc
echo "12345678" | vncpasswd -f > /home/tiny/.vnc/passwd
chmod 600 /home/tiny/.vnc/passwd
chown -R tiny:tiny /home/tiny/.vnc
cat > /home/tiny/.vnc/xstartup << "XS"
#!/bin/bash
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
exec bash ~/.xinitrc
XS
chmod +x /home/tiny/.vnc/xstartup
su - tiny -c "vncserver :4 -geometry 2424x1080 -depth 24 -localhost no"
SCRIPT
    chmod +x /usr/local/bin/start-vnc
    
    cat > /usr/local/bin/start-novnc << "SCRIPT"
#!/bin/bash
/usr/share/novnc/utils/novnc_proxy --vnc localhost:5904 --listen 36082 --web /usr/share/novnc &
echo "noVNC: http://localhost:36082/vnc.html"
SCRIPT
    chmod +x /usr/local/bin/start-novnc
    
    cat > /usr/local/bin/start-desktop << "SCRIPT"
#!/bin/bash
echo "Starting VNC..."
start-vnc
sleep 2
echo "Starting noVNC..."
start-novnc
echo "Desktop ready — VNC :5904 / noVNC :36082"
SCRIPT
    chmod +x /usr/local/bin/start-desktop
    ln -sf /usr/local/bin/start-desktop /usr/local/bin/startnovnc
'

# Step 7: Clean up
echo "[7/8] Cleaning up..."
sudo systemd-nspawn -D "$ROOTFS" /bin/bash -c '
    pacman -Scc --noconfirm
    rm -rf /var/cache/pacman/pkg/* /tmp/* /var/tmp/*
    rm -f /home/tiny/.bash_history /root/.bash_history
    rm -rf /home/tiny/.cache /root/.cache
    rm -f /home/tiny/.vnc/*.log /home/tiny/.vnc/*.pid
'

# Step 8: Package
echo "[8/8] Packaging rootfs..."
mkdir -p "$OUTPUT"
cd "$ROOTFS"
sudo tar -Jcpf "$OUTPUT/archlinux.tar.xz" \
    --exclude=dev --exclude=proc --exclude=sys \
    --exclude=archlinux.tar.xz .

cd "$OUTPUT"
split -b "$SPLIT_SIZE" archlinux.tar.xz

echo ""
echo "=== Build Complete ==="
echo "Rootfs: $OUTPUT/archlinux.tar.xz"
echo "Size: $(du -sh archlinux.tar.xz | cut -f1)"
echo "Chunks: $(ls x* 2>/dev/null | wc -l) files at $SPLIT_SIZE each"

echo ""
echo "Copy the x* files to your Flutter project's assets/ directory."
echo "Rename them to match the expected pattern (xaa, xab, xac, etc.)"
