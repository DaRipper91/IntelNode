#!/usr/bin/env bash
# Capture an IntelNode run from a connected phone into debug/logs/<stamp>/.
# usage: debug/capture.sh [adb-serial]   (e.g. 192.168.1.68:5555)
set -u
PKG=com.daripper91.daripped
ADB=(adb); [ $# -ge 1 ] && ADB=(adb -s "$1")
OUT="$(dirname "$0")/logs/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
"${ADB[@]}" shell getprop > "$OUT/getprop.txt"
"${ADB[@]}" shell dumpsys package "$PKG" > "$OUT/package.txt"
"${ADB[@]}" logcat -c
"${ADB[@]}" shell am force-stop "$PKG"
"${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Logging to $OUT (Ctrl-C to stop)"
# App writes little to logcat on Android 17; the events buffer and the sandbox
# denials are what show process starts and proot activity.
"${ADB[@]}" logcat -b all -v threadtime > "$OUT/logcat.txt" &
LP=$!
trap 'kill $LP 2>/dev/null' EXIT
while sleep 15; do
  {
    echo "== $(date +%T)"
    "${ADB[@]}" shell "run-as $PKG sh -c 'ls files/containers; ls files/containers/0_staging 2>/dev/null | head -3; ls -la files/containers/0/tmp/.X11-unix 2>/dev/null'"
    "${ADB[@]}" shell "run-as $PKG sh -c 'cat /proc/net/tcp | grep -i \":1ED9\" '"   # 7897 = X server
    "${ADB[@]}" shell ps -A | grep -E "proot|Xlorie|pulseaudio|xfce|dbus|busybox|tar"
  } >> "$OUT/state.txt" 2>&1
done
