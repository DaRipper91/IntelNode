// DeInstaller.kt -- This file is part of tiny_container.
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
 * Builds the package-manager-appropriate install command for a [DeEntry]
 * inside an already-installed container, then runs it via [ProotExec].
 *
 * Tier-2 (experimental/Wayland) entries are currently pacman-only by
 * design — see de_packages.yaml's tier-2 header comment for why (Fedora
 * lacks niri/cosmic-desktop in its official repos; Debian/Ubuntu's apt
 * situation wasn't verified to the same standard as tier 1). This class
 * refuses a tier-2 install for any other package manager rather than
 * silently attempting something unverified, per the task brief's "flag
 * simpler alternatives before building harder ones" requirement.
 */
class DeInstaller(private val execShell: suspend (block: () -> Unit) -> Int) {

    sealed interface Result {
        data class Installed(val de: DeEntry) : Result
        data class Refused(val de: DeEntry, val reason: String) : Result
    }

    /** What [dryRun] reports, without running anything. */
    data class DryRunReport(
        val de: DeEntry,
        val packageManager: PackageManagerFamily,
        val packages: List<String>?,
        val installCommandPreview: String?,
        val refusalReason: String?,
    )

    fun dryRun(de: DeEntry, distro: DistroEntry): DryRunReport {
        val family = distro.packageManager
        val refusal = refusalReasonFor(de, family)
        val packages = de.packagesFor(family)
        return DryRunReport(
            de = de,
            packageManager = family,
            packages = packages,
            installCommandPreview = packages?.let { installCommand(family, it) },
            refusalReason = refusal,
        )
    }

    suspend fun install(de: DeEntry, distro: DistroEntry, containerDir: String): Result {
        val family = distro.packageManager
        refusalReasonFor(de, family)?.let { reason ->
            return Result.Refused(de, reason)
        }

        val packages = de.packagesFor(family)
            ?: return Result.Refused(
                de,
                "No ${family.name.lowercase()} package list for '${de.alias}' in de_packages.yaml",
            )

        execShell {
            Global.setupEnvironment()
            Global.sendCommand(
                ProotExec.runInContainerCommand(containerDir, installCommand(family, packages)),
            )
            Global.sendCommand("exit")
        }
        return Result.Installed(de)
    }

    private fun refusalReasonFor(de: DeEntry, family: PackageManagerFamily): String? {
        if (de.tier != DeTier.EXPERIMENTAL) return null
        if (family == PackageManagerFamily.PACMAN) return null
        return "'${de.alias}' is tier-2/experimental and has only been prototyped on Arch (pacman) " +
            "so far — installing it on ${family.name.lowercase()} is refused rather than guessed. " +
            "Simpler fallback: pick a tier-1 DE, or switch this container's distro to Arch Linux."
    }

    private fun installCommand(family: PackageManagerFamily, packages: List<String>): String {
        val list = packages.joinToString(" ")
        return when (family) {
            PackageManagerFamily.PACMAN -> "pacman -Sy --noconfirm $list"
            PackageManagerFamily.APT -> "apt-get update && apt-get install -y $list"
            PackageManagerFamily.DNF -> {
                // "@group-id" is dnf4's group-install syntax. Not verified
                // against whatever dnf major version actually ends up
                // inside the Fedora base image — dnf5 changed group-command
                // syntax in places. Needs a real-device check.
                val groups = packages.filter { it.startsWith("@") }
                val plain = packages.filter { !it.startsWith("@") }
                buildString {
                    groups.forEach { append("dnf group install -y \"$it\" && ") }
                    if (plain.isNotEmpty()) append("dnf install -y ${plain.joinToString(" ")}")
                    else if (groups.isNotEmpty()) setLength(length - 4) // trim trailing " && "
                }
            }
        }
    }
}
