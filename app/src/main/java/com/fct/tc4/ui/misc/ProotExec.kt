// ProotExec.kt -- This file is part of tiny_container.
//
// Copyright (C) 2026 Caten Hu
//
// Tiny Container is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License,
// or any later version.
//
// Tiny Container is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/.

package com.fct.tc4.ui.misc

/**
 * Builds shell commands that enter a container's rootfs via proot — used by
 * DistroInstaller (first-boot setup), DeInstaller (DE package install), and
 * for synthesizing a fresh container's `boot_command` (TinyYamlBuilder.kt).
 *
 * These flags are NOT a guess — they're copied from the real, live
 * `boot_command`/`export_command` in tiny-computer/images's
 * proot-distro.tiny.yaml (an actual upstream-authored, presumably-working
 * config for a real proot-distro-installed container), which is the
 * concrete example this repo itself doesn't check in anywhere (each
 * container's `boot_command` lives in its own imported .tiny.yaml, not in
 * source). [runAsRootCommand] mirrors that file's `export_command` (which
 * enters as root at /root — the shape first-boot/package-install commands
 * need); the DISPLAY=:6 / LANG=en_US.UTF-8 defaults used elsewhere in this
 * package for synthesized configs also come from that same file.
 *
 * One real gap this does NOT paper over: `export_command`'s bind mounts for
 * /proc/loadavg, /proc/stat, /proc/uptime, /proc/version, /proc/vmstat, and
 * two sysctl entries all target placeholder files
 * ($CONTAINER_DIR/proc/.loadavg etc.) that upstream's own export.sh creates
 * by literally snapshotting those paths out of a REAL, already-booted proot
 * session via `tar --transform`. A freshly-pulled Debian/Arch/Fedora/Ubuntu
 * image has none of these — DistroInstaller.kt creates them with plausible
 * static placeholder content (see createProcPlaceholders()) since there is
 * no live session to snapshot them from. This is a real, if probably minor,
 * behavioral difference from how every other container in this app was
 * actually built, and hasn't been device-tested.
 */
object ProotExec {

    /** The seven proc/sys placeholder files export.sh normally snapshots from a live session. */
    val procPlaceholders: Map<String, String> = mapOf(
        "sys/.empty" to "", // bind-mounted as a directory target for /sys/fs/selinux
        "proc/.loadavg" to "0.00 0.00 0.00 1/1 1\n",
        "proc/.stat" to "cpu  0 0 0 0 0 0 0 0 0 0\nbtime 0\nprocesses 1\n",
        "proc/.uptime" to "0.00 0.00\n",
        "proc/.version" to
            "Linux version 6.17.0-PRoot-Distro (proot@localhost) #1 SMP PREEMPT_DYNAMIC " +
            "Fri, 10 Oct 2025 00:00:00 +0000\n",
        "proc/.vmstat" to "nr_free_pages 0\n",
        "proc/.sysctl_entry_cap_last_cap" to "40\n",
        "proc/.sysctl_inotify_max_user_watches" to "524288\n",
    )

    /**
     * The shared bind-mount/env flag block from the real boot_command /
     * export_command, parameterized only by $CONTAINER_DIR and $CACHE_DIR
     * (both already exported by Global.setupEnvironment()).
     */
    private val commonProotFlags = $$"""--kill-on-exit --link2symlink --sysvipc \
                --kernel-release="Linux localhost 6.17.0-PRoot-Distro #1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000 aarch64 localdomain -1" \
                -L \
                --bind=/data --bind=/dev --bind=/proc --bind=/sys --bind=/dev/urandom:/dev/random \
                --bind=/proc/self/fd:/dev/fd --bind=/proc/self/fd/0:/dev/stdin --bind=/proc/self/fd/1:/dev/stdout --bind=/proc/self/fd/2:/dev/stderr \
                --bind=$CONTAINER_DIR/sys/.empty:/sys/fs/selinux \
                --bind=$CONTAINER_DIR/proc/.loadavg:/proc/loadavg \
                --bind=$CONTAINER_DIR/proc/.stat:/proc/stat \
                --bind=$CONTAINER_DIR/proc/.uptime:/proc/uptime \
                --bind=$CONTAINER_DIR/proc/.version:/proc/version \
                --bind=$CONTAINER_DIR/proc/.vmstat:/proc/vmstat \
                --bind=$CONTAINER_DIR/proc/.sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap \
                --bind=$CONTAINER_DIR/proc/.sysctl_inotify_max_user_watches:/proc/sys/fs/inotify/max_user_watches \
                --bind=$CACHE_DIR/tmp:/dev/shm --bind=$CACHE_DIR/tmp:/tmp --bind=$CACHE_DIR/run:/run"""
        .trimIndent()

    /**
     * Enters [containerDir] as root at /root and runs [command] — mirrors
     * the real export_command shape. Used for one-time, non-interactive
     * setup (first-boot steps, DE package installs), not for launching an
     * interactive session (that's [bootCommandTemplate]).
     */
    fun runAsRootCommand(containerDir: String, command: String): String {
        val escapedCommand = command.replace("'", "'\\''")
        return $$"""
            export CONTAINER_DIR=$$containerDir
            $BIN_DIR/proot -H $$commonProotFlags --rootfs=$CONTAINER_DIR --cwd=/root \
                /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
                LANG=en_US.UTF-8 HOME=/root USER=root TERM=xterm-256color \
                /bin/sh -c '$$escapedCommand'
        """.trimIndent()
    }

    /**
     * The `boot_command` string written into a freshly-built container's
     * .tiny.yaml (TinyYamlBuilder.kt) — logs in as the "tiny" user
     * interactively, matching every other container's real boot_command
     * shape (this exact template, minus the -H flag and swapping cwd/user,
     * is copied from tiny-computer/images's real proot-distro.tiny.yaml).
     */
    fun bootCommandTemplate(): String = $$"""
        $BIN_DIR/proot $EXTRA_ARGS -H $$commonProotFlags --rootfs=$CONTAINER_DIR --cwd=/home/tiny \
            --change-id=1000:1000 \
            --mount=$PUBLIC_DIR:/home/tiny/public \
            --mount=/storage/self/primary:/mnt/sdcard \
            /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$EXTRA_PATH \
            LD_LIBRARY_PATH=$EXTRA_LD_LIBRARY_PATH LD_PRELOAD=$EXTRA_LD_PRELOAD \
            DISPLAY=:6 LANG=en_US.UTF-8 \
            MOZ_FAKE_NO_SANDBOX=1 QTWEBENGINE_DISABLE_SANDBOX=1 ELECTRON_DISABLE_SANDBOX=1 \
            HOME=/home/tiny USER=tiny $EXTRA_ENV \
            TERM=xterm-256color COLORTERM=truecolor /bin/bash -l
    """.trimIndent()
}
