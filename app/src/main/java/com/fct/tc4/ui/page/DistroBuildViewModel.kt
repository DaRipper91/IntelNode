// DistroBuildViewModel.kt -- This file is part of tiny_container.
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

package com.fct.tc4.ui.page

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fct.tc4.ui.misc.ConfigManager
import com.fct.tc4.ui.misc.DeEntry
import com.fct.tc4.ui.misc.DeInstaller
import com.fct.tc4.ui.misc.DeRegistry
import com.fct.tc4.ui.misc.DeTier
import com.fct.tc4.ui.misc.DistroEntry
import com.fct.tc4.ui.misc.DistroInstaller
import com.fct.tc4.ui.misc.DistroRegistry
import com.fct.tc4.ui.misc.Global
import com.fct.tc4.ui.misc.TinyYamlBuilder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Shared, activity-scoped state for the on-device distro+DE build flow —
 * DistroSelectFragment and DeSelectFragment both read/write this via
 * activityViewModels(), the same pattern ContainerManageViewModel uses.
 */
class DistroBuildViewModel(application: Application) : AndroidViewModel(application) {

    sealed interface BuildState {
        data object Idle : BuildState
        data class Progress(val message: String) : BuildState
        data class Completed(val code: String) : BuildState
        data class Failed(val message: String) : BuildState
    }

    private val _buildState = MutableStateFlow<BuildState>(BuildState.Idle)
    val buildState: StateFlow<BuildState> = _buildState.asStateFlow()

    val distros: List<DistroEntry> by lazy { DistroRegistry.load(getApplication()) }
    val tier1Des: List<DeEntry> by lazy { DeRegistry.byTier(getApplication(), DeTier.STABLE) }
    val tier2Des: List<DeEntry> by lazy { DeRegistry.byTier(getApplication(), DeTier.EXPERIMENTAL) }

    fun distroByAlias(alias: String): DistroEntry? =
        distros.firstOrNull { it.alias == alias }

    /** Whether [de] can actually be selected for [distro] right now (not just listed). */
    fun isSelectable(de: DeEntry, distro: DistroEntry): Boolean =
        de.sessionCommand != null && de.packagesFor(distro.packageManager) != null

    fun resetBuildState() {
        _buildState.value = BuildState.Idle
    }

    /**
     * Runs the full build: distro rootfs fetch/extract/first-boot, then (if
     * [de] is non-null) DE package install, then writes the synthesized
     * .tiny.yaml and registers the container. Mirrors
     * ContainerManageViewModel.performInstall()'s shape, reusing the same
     * "run in a fresh terminal session, suspend until it exits" execShell
     * pattern.
     */
    fun startBuild(distro: DistroEntry, de: DeEntry?, code: String) {
        viewModelScope.launch {
            try {
                val distroInstaller = DistroInstaller(getApplication(), ::execShell)
                _buildState.value = BuildState.Progress("Resolving ${distro.displayName}…")
                distroInstaller.install(distro, code) { progress ->
                    _buildState.value = BuildState.Progress(describeDistroProgress(progress))
                }

                if (de != null) {
                    val containerDir = getApplication<Application>().dataDir.resolve(code)
                    _buildState.value = BuildState.Progress("Installing ${de.displayName}…")
                    val deInstaller = DeInstaller(::execShell)
                    val result = deInstaller.install(de, distro, containerDir.absolutePath)
                    if (result is DeInstaller.Result.Refused) {
                        _buildState.value = BuildState.Failed(result.reason)
                        return@launch
                    }
                }

                val config = TinyYamlBuilder.build(code, distro, de)
                Global.installedContainers += code
                ConfigManager.save(code, config)

                _buildState.value = BuildState.Completed(code)
            } catch (e: Exception) {
                _buildState.value = BuildState.Failed(e.message ?: e.toString())
            }
        }
    }

    private fun describeDistroProgress(progress: DistroInstaller.Progress): String = when (progress) {
        is DistroInstaller.Progress.Resolving -> "Resolving ${progress.distro.displayName}…"
        is DistroInstaller.Progress.Downloading -> {
            val pct = if (progress.totalBytes > 0) {
                " (${(progress.bytesDownloaded * 100 / progress.totalBytes)}%)"
            } else ""
            "Downloading ${progress.distro.displayName}$pct"
        }
        is DistroInstaller.Progress.Extracting -> "Extracting ${progress.distro.displayName}…"
        is DistroInstaller.Progress.RunningFirstBootStep ->
            "First-boot setup (${progress.stepIndex + 1}/${progress.totalSteps})…"
        is DistroInstaller.Progress.Completed -> "Done."
    }

    /** Same "run in a fresh terminal session and suspend until it exits" helper as ContainerManageViewModel. */
    private suspend fun execShell(block: () -> Unit): Int = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine { cont ->
            Global.newSession(onFinished = { exitCode -> cont.resume(exitCode) })
            block()
        }
    }
}
