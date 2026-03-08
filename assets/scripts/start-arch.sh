#!/bin/bash
# start-arch.sh: Bypasses systemd and initializes the environment for proot on Android 14+

# --- 1. Dynamic DNS Injection ---
ANDROID_DNS1=$(/system/bin/getprop net.dns1)
ANDROID_DNS2=$(/system/bin/getprop net.dns2)
echo "nameserver ${ANDROID_DNS1:-1.1.1.1}" > /etc/resolv.conf
echo "nameserver ${ANDROID_DNS2:-8.8.8.8}" >> /etc/resolv.conf

# --- 2. Inner Payload (D-Bus & Cleanup) ---
rm -f /var/run/dbus/pid
rm -rf /tmp/.X11-unix/*
if [ ! -d /var/run/dbus ]; then
    mkdir -p /var/run/dbus
fi
dbus-daemon --system --fork
chmod 1777 /tmp

# --- 3. Execute Desktop Session ---
exec /bin/su - tiny -c "/usr/local/bin/start-desktop"
