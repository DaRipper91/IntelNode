#!/usr/bin/env bash
# test-arch-commands.sh — run the app's shipped Arch quick-commands (install, then
# uninstall) inside an ARM64 Arch Linux ARM container on a dev machine, so command
# changes can be verified without installing APKs on a phone.
#
# How it works
#   1. tool/dump_commands.dart exports the exact command strings the app ships.
#   2. An Arch Linux ARM image is built from the official rootfs tarball, mirroring
#      the pacman.conf sandbox tweaks from build-arch-rootfs.sh (no Landlock/seccomp
#      under qemu-user). Runs via docker + qemu-user binfmt on any x86_64 host.
#   3. Each app's install command runs, then its uninstall command. Success is judged
#      from before/after filesystem snapshots, NOT exit codes: the install commands end
#      in `; rm /tmp/x.deb`, so a failed download/extraction still exits 0.
#
# What it does NOT cover: proot behaviour, Android permissions, X11/VNC. Use a device
# or emulator for those.
#
# Requirements: docker (daemon reachable), qemu-aarch64 binfmt registered, flutter,
# python3, ~2 GB disk for the cached rootfs + image, network for downloads.
#
# Usage: extra/test-arch-commands.sh [--apps wechat,wps,edraw,qq,dingtalk | --all]
#                                    [--rebuild-image] [--list]
# Default app: wechat (smallest payload that exercises the .deb extraction path).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${INTELNODE_TEST_CACHE:-$HOME/.cache/intelnode-test}"
TARBALL_URL="https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
MD5_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz.md5"
TARBALL="$CACHE/ArchLinuxARM-aarch64-latest.tar.gz"
BASE_IMAGE="intelnode-arch-base"
IMAGE="intelnode-arch-test"
WORK="$CACHE/work"
APP_TIMEOUT="${APP_TIMEOUT:-1800}"

# app key -> "install command name|uninstall command name" (names as shipped in D.commands)
declare -A APPS=(
  [wechat]="安装微信|卸载微信"
  [wps]="安装WPS|卸载WPS"
  [edraw]="安装亿图图示|卸载亿图图示"
  [qq]="安装QQ|卸载QQ"
  [dingtalk]="安装钉钉|卸载钉钉"
)

selected=(wechat)
rebuild=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apps) IFS=, read -r -a selected <<<"${2:?--apps needs a list}"; shift ;;
    --all) selected=(wechat wps edraw qq dingtalk) ;;
    --rebuild-image) rebuild=1 ;;
    --list) printf '%s\n' "${!APPS[@]}" | sort; exit 0 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
for a in "${selected[@]}"; do
  [ -n "${APPS[$a]:-}" ] || { echo "unknown app '$a' (try --list)" >&2; exit 2; }
done

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

preflight() {
  log "Preflight"
  command -v docker >/dev/null || die "docker not found"
  docker info >/dev/null 2>&1 || die "docker daemon not reachable (is it running, are you in the docker group?)"
  grep -qs '^enabled' /proc/sys/fs/binfmt_misc/qemu-aarch64 \
    || die "qemu-aarch64 binfmt not enabled (install qemu-user-static + binfmt, or run tonistiigi/binfmt)"
  command -v flutter >/dev/null || die "flutter not found"
  command -v python3 >/dev/null || die "python3 not found"
  mkdir -p "$CACHE" "$WORK"
}

fetch_rootfs() {
  log "Official Arch Linux ARM rootfs"
  curl -fL -C - --retry 5 -o "$TARBALL" "$TARBALL_URL"
  local want got
  want="$(curl -fsL "$MD5_URL" | awk '{print $1}')"
  got="$(md5sum "$TARBALL" | awk '{print $1}')"
  [ -n "$want" ] && [ "$want" = "$got" ] || die "md5 mismatch for rootfs (want '$want', got '$got')"
  echo "md5 ok: $got"
}

build_image() {
  if [ "$rebuild" = 0 ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    log "Image $IMAGE already built (use --rebuild-image to redo)"
    return
  fi
  fetch_rootfs
  log "Importing rootfs as $BASE_IMAGE"
  docker import --platform linux/arm64 "$TARBALL" "$BASE_IMAGE" >/dev/null
  log "Building $IMAGE (full -Syu under emulation; takes a while once, then cached)"
  # sudo shim: setuid binaries don't work under qemu-user binfmt, and inside the app's
  # proot the user is already faked-root. The shim only drops flags and execs.
  docker build --platform linux/arm64 -t "$IMAGE" - <<EOF
FROM $BASE_IMAGE
RUN pacman-key --init && pacman-key --populate archlinuxarm \\
 && sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/; s/^CheckSpace/#CheckSpace/; s/#DisableSandboxFilesystem/DisableSandboxFilesystem/; s/#DisableSandboxSyscalls/DisableSandboxSyscalls/; s/#DisableSandbox/DisableSandbox/' /etc/pacman.conf \\
 && pacman -Syu --noconfirm --needed wget curl libarchive \\
 && useradd -m -s /bin/bash tiny \\
 && printf '#!/bin/sh\nwhile [ "\${1#-}" != "\$1" ]; do shift; done\nexec "\$@"\n' > /usr/local/bin/sudo \\
 && chmod +x /usr/local/bin/sudo \\
 && pacman -Scc --noconfirm
ENV LANG=C
EOF
}

dump_commands() {
  log "Dumping shipped commands from Dart (tool/dump_commands.dart)"
  (cd "$ROOT" && flutter test tool/dump_commands.dart --dart-define=OUT="$WORK/commands.json" >/dev/null)
  [ -s "$WORK/commands.json" ] || die "command dump produced no output"
}

prepare_app() { # app-key -> writes $WORK/<app>.{install,uninstall}.sh
  local app="$1" names inst uninst
  names="${APPS[$app]}"; inst="${names%%|*}"; uninst="${names##*|}"
  python3 -I - "$WORK/commands.json" "$WORK" "$app" "$inst" "$uninst" <<'PY'
import json, sys
path, work, app, inst, uninst = sys.argv[1:6]
cmds = {c["name"]: c["command"] for c in json.load(open(path))["pacman"]}
for kind, name in (("install", inst), ("uninstall", uninst)):
    if name not in cmds:
        sys.exit(f"command '{name}' not found in shipped pacman list")
    open(f"{work}/{app}.{kind}.sh", "w").write(cmds[name] + "\n")
PY
}

# Runs inside the container; prints markers the host parses.
read -r -d '' INNER <<'EOS' || true
app="$1"; out="/work/out/$app"; rm -rf "$out"; mkdir -p "$out"
snap() { find /opt /usr /etc /home /root /var/lib -xdev \( -type f -o -type l \) 2>/dev/null | sort; }
snap > "$out/before"
echo "--- INSTALL ---";   bash "/work/$app.install.sh";   echo "install-exit=$?"
snap > "$out/after_install"
comm -13 "$out/before" "$out/after_install" > "$out/new_files"
echo "--- UNINSTALL ---"; bash "/work/$app.uninstall.sh"; echo "uninstall-exit=$?"
snap > "$out/after_uninstall"
comm -12 "$out/new_files" "$out/after_uninstall" > "$out/leftovers"
EOS

run_app() { # app-key -> sets RESULT[app]
  local app="$1" out="$WORK/out/$1" new_opt left_opt left_all new_all
  log "[$app] install -> uninstall in ARM64 Arch container"
  prepare_app "$app"
  mkdir -p "$WORK/out"
  timeout "$APP_TIMEOUT" docker run --rm --platform linux/arm64 -v "$WORK:/work" "$IMAGE" \
    bash -c "$INNER" _ "$app" 2>&1 | tee "$WORK/$app.log" | sed 's/^/    /' || true
  [ -f "$out/new_files" ] || { RESULT[$app]="FAIL (container run did not complete; see $WORK/$app.log)"; return; }
  new_all=$(wc -l < "$out/new_files")
  new_opt=$(grep -c '^/opt/' "$out/new_files" || true)
  left_all=$(wc -l < "$out/leftovers")
  left_opt=$(grep -c '^/opt/' "$out/leftovers" || true)
  echo "    installed: $new_all files ($new_opt under /opt); left after uninstall: $left_all ($left_opt under /opt)"
  echo "    top-level install dirs:"; awk -F/ 'NF>3{print "/"$2"/"$3}' "$out/new_files" | sort | uniq -c | sort -rn | head -6 | sed 's/^/      /'
  if [ "$left_all" -gt 0 ]; then
    echo "    leftover (not removed by uninstall):"; head -8 "$out/leftovers" | sed 's/^/      /'
  fi
  if [ "$new_opt" -eq 0 ]; then RESULT[$app]="FAIL (install put nothing under /opt)"
  elif [ "$left_opt" -gt 0 ]; then RESULT[$app]="FAIL ($left_opt files under /opt survive uninstall)"
  elif [ "$left_all" -gt 0 ]; then RESULT[$app]="PASS with warnings ($left_all leftover files outside /opt)"
  else RESULT[$app]="PASS"; fi
}

declare -A RESULT=()
preflight
build_image
dump_commands
for app in "${selected[@]}"; do run_app "$app"; done

log "Summary"
status=0
for app in "${selected[@]}"; do
  printf '  %-9s %s\n' "$app" "${RESULT[$app]}"
  case "${RESULT[$app]}" in FAIL*) status=1 ;; esac
done
exit "$status"
