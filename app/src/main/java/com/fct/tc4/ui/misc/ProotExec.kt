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
 * Builds a shell command that chroots into a container's rootfs via proot
 * and runs a command as root inside it — used by both DistroInstaller
 * (first-boot setup) and DeInstaller (desktop-environment package install).
 *
 * NOT YET VALIDATED ON A REAL DEVICE. This mirrors the flag conventions
 * ContainerManageViewModel.performInstall() already uses for extraction
 * (--link2symlink, $BIN_DIR/proot, the PROOT_LOADER*/PROOT_TMP_DIR env vars
 * from Global.setupEnvironment()) plus the standard proot chroot flags
 * (-r rootfs, -w workdir, -b bind-mounts for /dev, /proc, /sys — needed by
 * most package managers). This app's actual per-container `boot_command`
 * (the real, working proot invocation for LAUNCHING a container) lives
 * inside each container's own .tiny.yaml, authored per upstream image and
 * never checked into this repo, so there was no concrete example to copy
 * exactly for this kind of one-time, non-interactive invocation. This is
 * the single most significant open risk across the distro/DE selector
 * work — flagging per the task brief's "surface real proot/Android 16
 * sandboxing limits early" requirement rather than presenting it as
 * verified. Needs a real-device smoke test against each of the four
 * distros before this can be considered done.
 */
object ProotExec {
    fun runInContainerCommand(containerDir: String, command: String): String {
        val escapedCommand = command.replace("'", "'\\''")
        return $$"""
            $BIN_DIR/proot --link2symlink -r $$containerDir -w /root -b /dev -b /proc -b /sys \
                /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
                /bin/sh -c '$$escapedCommand'
        """.trimIndent()
    }
}
