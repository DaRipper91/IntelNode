// DistroRegistry.kt -- This file is part of tiny_container.
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

/** One of the package-manager families a distro entry can declare. */
enum class PackageManagerFamily {
    PACMAN, DNF, APT;

    companion object {
        fun fromString(value: String): PackageManagerFamily =
            entries.firstOrNull { it.name.equals(value, ignoreCase = true) }
                ?: throw IllegalArgumentException("Unknown package_manager: $value")
    }
}

/** Where a distro's base rootfs actually comes from. See distros.yaml's header comment. */
sealed interface DistroSource {
    data class StaticTarball(val url: String) : DistroSource

    data class Oci(
        val registry: String,
        val authRealm: String,
        val authService: String,
        val repository: String,
        val tag: String,
    ) : DistroSource
}

data class DistroEntry(
    val alias: String,
    val displayName: String,
    val packageManager: PackageManagerFamily,
    val source: DistroSource,
    val firstBootSteps: List<String>,
)

/**
 * Loads the config-driven distro list from assets/distros.yaml. Adding a new
 * distro is a manifest edit only — nothing here or in the selector UI needs
 * to change.
 */
object DistroRegistry {

    private var cached: List<DistroEntry>? = null

    fun load(context: Context): List<DistroEntry> {
        cached?.let { return it }

        @Suppress("UNCHECKED_CAST")
        val root = context.assets.open("distros.yaml").use { stream ->
            Yaml().load<Map<String, Any>>(stream)
        }

        @Suppress("UNCHECKED_CAST")
        val rawList = root["distros"] as? List<Map<String, Any>>
            ?: throw IllegalStateException("distros.yaml is missing a top-level 'distros' list")

        val entries = rawList.map { raw -> parseEntry(raw) }
        cached = entries
        return entries
    }

    /** Look up a single entry by alias, or null if the manifest has no such distro. */
    fun findByAlias(context: Context, alias: String): DistroEntry? =
        load(context).firstOrNull { it.alias == alias }

    @Suppress("UNCHECKED_CAST")
    private fun parseEntry(raw: Map<String, Any>): DistroEntry {
        val alias = raw["alias"] as? String
            ?: throw IllegalStateException("distro entry missing 'alias': $raw")
        val displayName = raw["display_name"] as? String
            ?: throw IllegalStateException("distro '$alias' missing 'display_name'")
        val packageManager = PackageManagerFamily.fromString(
            raw["package_manager"] as? String
                ?: throw IllegalStateException("distro '$alias' missing 'package_manager'")
        )
        val sourceRaw = raw["source"] as? Map<String, Any>
            ?: throw IllegalStateException("distro '$alias' missing 'source'")
        val source = parseSource(alias, sourceRaw)
        val firstBootSteps = (raw["first_boot_steps"] as? List<String>) ?: emptyList()

        return DistroEntry(alias, displayName, packageManager, source, firstBootSteps)
    }

    private fun parseSource(alias: String, raw: Map<String, Any>): DistroSource {
        return when (val type = raw["type"] as? String) {
            "static_tarball" -> DistroSource.StaticTarball(
                url = raw["url"] as? String
                    ?: throw IllegalStateException("distro '$alias' static_tarball source missing 'url'")
            )
            "oci" -> DistroSource.Oci(
                registry = raw["registry"] as? String
                    ?: throw IllegalStateException("distro '$alias' oci source missing 'registry'"),
                authRealm = raw["auth_realm"] as? String
                    ?: throw IllegalStateException("distro '$alias' oci source missing 'auth_realm'"),
                authService = raw["auth_service"] as? String
                    ?: throw IllegalStateException("distro '$alias' oci source missing 'auth_service'"),
                repository = raw["repository"] as? String
                    ?: throw IllegalStateException("distro '$alias' oci source missing 'repository'"),
                tag = raw["tag"] as? String
                    ?: throw IllegalStateException("distro '$alias' oci source missing 'tag'"),
            )
            else -> throw IllegalStateException("distro '$alias' has unknown source type: $type")
        }
    }
}
