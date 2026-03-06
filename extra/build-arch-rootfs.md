# Building the Arch Linux ARM Rootfs

This document outlines the manual process for creating the `archlinux.tar.xz` rootfs that is bundled with the application. The automated version of this process is available in the `build-arch-rootfs.sh` script.

## Prerequisites

-   A host machine running a modern Linux distribution. An Arch-based distro (like CachyOS or vanilla Arch) is recommended as it has `systemd-nspawn` readily available.
-   `sudo` or root access on the build machine.
-   Required packages: `wget`, `tar`, `systemd-nspawn`.
-   If your host machine is not `aarch64`, you will also need `qemu-user-static` and `binfmt-support` to run the ARM-based environment.

## Build Procedure

### 1. Download and Extract the Base Rootfs

First, download the latest generic Arch Linux ARM rootfs for the `aarch64` architecture.

```bash
# Create a working directory
mkdir -p archroot-build/rootfs
cd archroot-build

# Download the rootfs tarball
wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz

# Extract the tarball into the rootfs directory as root
sudo tar -xzf ArchLinuxARM-aarch64-latest.tar.gz -C rootfs/
```

### 2. Configure the System via `systemd-nspawn`

`systemd-nspawn` allows you to enter the new rootfs as if it were a container, using your host's kernel.

```bash
# Enter the container. We bind the host's DNS settings to ensure network access.
sudo systemd-nspawn -D "$(pwd)/rootfs" --bind-ro=/etc/resolv.conf /bin/bash
```

### 3. Inside the Container: System Initialization

Once you are inside the container's shell, you need to initialize the `pacman` keyring and update the system.

```bash
# Initialize pacman's keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Enable parallel downloads for faster package installation
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf

# Perform a full system upgrade
pacman -Syu --noconfirm
```

### 4. Inside the Container: Install Packages

Install the desktop environment (XFCE), VNC server, and other necessary utilities.

```bash
pacman -S --noconfirm \
    xfce4 xfce4-goodies xfce4-terminal \
    tigervnc \
    novnc \
    python python-websockify python-numpy \
    firefox \
    noto-fonts noto-fonts-cjk ttf-dejavu \
    sudo base-devel git wget curl \
    bash-completion htop neofetch nano vim \
    xdg-utils xdg-user-dirs dbus \
    xorg-server xorg-xinit xorg-xauth
```

> **LXQt alternative:** To build an LXQt rootfs instead of XFCE, replace the `xfce4 xfce4-goodies xfce4-terminal` packages with:
> ```bash
> pacman -S --noconfirm \
>     lxqt lxqt-panel lxqt-session qterminal \
>     openbox obconf
> ```
> All other packages in the block above remain the same.

---

#### Note: Building a Dual-DE Rootfs (for v2.0.7+ DE Selection Dialog)

Starting with **v2.0.7**, the app shows a DE selection dialog on first container boot. This dialog lets the user choose between XFCE and LXQt, then **purges the unchosen DE** (~400 MB reclaimed). This feature only activates when the rootfs contains **both** DEs — if only one DE is detected, the dialog is silently skipped and the single DE is used as-is.

To build a dual-DE rootfs (the format expected by the v2.0.7 dialog), install **both** package sets inside the container:

```bash
# XFCE
pacman -S --noconfirm xfce4 xfce4-goodies xfce4-terminal

# LXQt
pacman -S --noconfirm lxqt lxqt-panel lxqt-session qterminal openbox obconf
```

Then proceed with the shared packages (tigervnc, novnc, fonts, etc.) as listed above.

**Key points:**
- The automated script (`build-arch-rootfs.sh --xfce` or `--lxqt`) always produces a **single-DE** rootfs. Dual-DE requires combining both package sets manually, as shown above.
- Single-DE builds are fully supported — the selection dialog simply won't appear.
- The purge step runs once on first boot inside the container, not at APK install time.

---

### 5. Inside the Container: User and Locale Setup

Create the default `tiny` user and configure the system locale.

```bash
# Create the 'tiny' user, add them to the 'wheel' group for sudo access
useradd -m -G wheel -s /bin/bash tiny
echo "tiny:tiny" | chpasswd

# Configure sudo to allow the 'wheel' group to execute commands without a password
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Generate the en_US.UTF-8 locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

### 6. Inside the Container: Cleanup

Before packaging the rootfs, clean up package caches and temporary files to reduce the final size.

```bash
pacman -Scc --noconfirm
rm -rf /var/cache/pacman/pkg/*
rm -rf /tmp/*
rm -f /root/.bash_history
# Exit the container shell
exit
```

### 7. Package the Rootfs

Now, back on your host machine, create the final compressed tarball.

```bash
# Navigate into the rootfs directory
cd rootfs/

# Create the tarball, excluding pseudo-filesystems
sudo tar -Jcpf ../archlinux.tar.xz \
    --exclude=./dev \
    --exclude=./proc \
    --exclude=./sys \
    --exclude=./archlinux.tar.xz .

cd ..
```

### 8. Split the Tarball for APK Bundling

The Android build system has a limit on asset file sizes. Split the large tarball into 98MB chunks.

```bash
split -b 98M archlinux.tar.xz
```

This will produce chunk files named `xaa`, `xab`, etc. Copy these into the `assets/` directory of the Flutter project before building the APK — the app reassembles them at runtime using those exact filenames (`xaa`, `xab`, …) to reconstruct `archlinux.tar.xz` on the device.

> **Note:** The Flutter app resolves these chunks by name at runtime. If you add or remove chunks (e.g. by changing the `-b` size), update the corresponding asset list in the app's `pubspec.yaml` and the runtime reassembly logic to match.

