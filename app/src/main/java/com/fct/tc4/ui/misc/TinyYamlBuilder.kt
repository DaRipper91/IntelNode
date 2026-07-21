// TinyYamlBuilder.kt -- This file is part of tiny_container.
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
 * Synthesizes the config map a freshly on-device-built (distro + DE)
 * container needs — every other container's config comes from an
 * upstream-authored .tiny.yaml imported wholesale; this is the one built by
 * this app itself rather than imported.
 */
object TinyYamlBuilder {

    /** Matches the DISPLAY=:6 baked into ProotExec.bootCommandTemplate(). */
    private const val X11_DISPLAY = "6"

    /**
     * @throws IllegalStateException if [de] is non-null but has no
     *   [DeEntry.sessionCommand] (every current tier-2 entry) — there is
     *   nothing correct to write into `feature[].command` in that case, so
     *   this refuses rather than shipping a container with a guessed,
     *   probably-broken session launch command. Callers should check
     *   `de.sessionCommand != null` before offering a tier-2 DE as buildable.
     */
    fun build(code: String, distro: DistroEntry, de: DeEntry?): Map<String, Any> {
        val sessionCommand = de?.let {
            it.sessionCommand
                ?: throw IllegalStateException(
                    "DE '${it.alias}' has no session_command yet — its X11/Wayland launch " +
                        "path isn't validated, so there's nothing correct to write here.",
                )
        }

        val name = "${distro.displayName}${de?.let { " (${it.displayName})" } ?: ""}"
        val description = buildString {
            append("Built on-device from ${distro.displayName}")
            if (de != null) append(" with ${de.displayName}")
            append(".")
        }

        val config = mutableMapOf<String, Any>(
            "code" to code,
            "name" to name,
            "description" to description,
            "boot_command" to ProotExec.bootCommandTemplate(),
        )

        if (sessionCommand != null) {
            config["feature"] = listOf(
                mapOf(
                    "type" to "x11",
                    "name" to "X11",
                    "description" to "Termux:X11 graphical session.",
                    "enabled" to true,
                    "args" to listOf(":$X11_DISPLAY", "-extension", "MIT-SHM"),
                    "command" to sessionCommand,
                ),
            )
        }

        return config
    }
}
