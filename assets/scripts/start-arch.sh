#!/bin/bash
# start-arch.sh: Bypasses systemd and initializes the environment for proot on Android 16+

# --- 1. Dynamic DNS Injection ---
# The Arch ARM tarball ships /etc/resolv.conf as a symlink into /run/systemd,
# which does not exist here; writing through it fails with ENOENT. Replace it.
ANDROID_DNS1=$(/system/bin/getprop net.dns1)
ANDROID_DNS2=$(/system/bin/getprop net.dns2)
rm -f /etc/resolv.conf
echo "nameserver ${ANDROID_DNS1:-1.1.1.1}" > /etc/resolv.conf
echo "nameserver ${ANDROID_DNS2:-8.8.8.8}" >> /etc/resolv.conf

# --- 2. Inner Payload (D-Bus & Cleanup) ---
rm -f /var/run/dbus/pid
rm -rf /tmp/.X11-unix/*
if [ ! -d /var/run/dbus ]; then
    mkdir -p /var/run/dbus
fi
# The session runs as the unprivileged `tiny` user (proot --change-id); the
# system bus needs root, which sudo provides inside proot.
sudo -n dbus-daemon --system --fork 2>/dev/null || dbus-daemon --system --fork
chmod 1777 /tmp

# --- 3. Execute Desktop Session ---
# `su` from a non-root user prompts for a password and hangs forever; only
# switch users when actually started as root. start-desktop is run through bash
# because the app copies assets without the executable bit.
if [ "$(id -u)" = "0" ]; then
    exec /bin/su - tiny -c "/bin/bash /usr/local/bin/start-desktop"
fi
exec /bin/bash /usr/local/bin/start-desktop
