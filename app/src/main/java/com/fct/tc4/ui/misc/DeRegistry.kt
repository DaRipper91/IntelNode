// DeRegistry.kt -- This file is part of tiny_container.
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

import android.content.Context
import org.yaml.snakeyaml.Yaml

enum class DeTier { STABLE, EXPERIMENTAL }

data class DeEntry(
    val alias: String,
    val displayName: String,
    val tier: DeTier,
    /** Only meaningful for [DeTier.EXPERIMENTAL] entries — see DeInstaller.kt. */
    val requiresBridge: Boolean,
    /** package_manager family name -> list of packages/groups to install. */
    val packageManagers: Map<PackageManagerFamily, List<String>>,
    /**
     * Command run inside the container's already-logged-in boot_command
     * session once the X11 socket is ready (see TinyYamlBuilder.kt) — null
     * for every current tier-2 entry, since how a Wayland-only compositor
     * actually gets a picture onto Termux:X11's X-server-shaped bridge is
     * exactly the unprototyped question the task brief asked to flag rather
     * than guess at.
     */
    val sessionCommand: String?,
) {
    /** Null if this DE has no known install command for [family] yet (see de_packages.yaml). */
    fun packagesFor(family: PackageManagerFamily): List<String>? = packageManagers[family]
}

/**
 * Loads the config-driven DE list from assets/de_packages.yaml. Adding a new
 * DE (tier 1 or tier 2) is a manifest edit only.
 */
object DeRegistry {

    private var cached: List<DeEntry>? = null

    fun load(context: Context): List<DeEntry> {
        cached?.let { return it }

        @Suppress("UNCHECKED_CAST")
        val root = context.assets.open("de_packages.yaml").use { stream ->
            Yaml().load<Map<String, Any>>(stream)
        }

        @Suppress("UNCHECKED_CAST")
        val rawList = root["des"] as? List<Map<String, Any>>
            ?: throw IllegalStateException("de_packages.yaml is missing a top-level 'des' list")

        val entries = rawList.map { raw -> parseEntry(raw) }
        cached = entries
        return entries
    }

    fun findByAlias(context: Context, alias: String): DeEntry? =
        load(context).firstOrNull { it.alias == alias }

    fun byTier(context: Context, tier: DeTier): List<DeEntry> =
        load(context).filter { it.tier == tier }

    @Suppress("UNCHECKED_CAST")
    private fun parseEntry(raw: Map<String, Any>): DeEntry {
        val alias = raw["alias"] as? String
            ?: throw IllegalStateException("DE entry missing 'alias': $raw")
        val displayName = raw["display_name"] as? String
            ?: throw IllegalStateException("DE '$alias' missing 'display_name'")
        val tier = when (val t = raw["tier"]) {
            1 -> DeTier.STABLE
            2 -> DeTier.EXPERIMENTAL
            else -> throw IllegalStateException("DE '$alias' has unknown tier: $t")
        }
        val requiresBridge = raw["requires_bridge"] as? Boolean ?: false
        val packageManagersRaw = raw["package_managers"] as? Map<String, List<String>>
            ?: throw IllegalStateException("DE '$alias' missing 'package_managers'")
        val packageManagers = packageManagersRaw.entries.associate { (key, value) ->
            PackageManagerFamily.fromString(key) to value
        }
        val sessionCommand = raw["session_command"] as? String

        return DeEntry(alias, displayName, tier, requiresBridge, packageManagers, sessionCommand)
    }
}
