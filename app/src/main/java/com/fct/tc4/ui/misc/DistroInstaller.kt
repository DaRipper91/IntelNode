// DistroInstaller.kt -- This file is part of tiny_container.
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

import android.app.Application
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches a [DistroEntry]'s base rootfs (via [OciRegistryClient] for `oci`
 * sources, or a plain HTTP(S) download for `static_tarball` sources) and
 * extracts it using the exact same `proot --link2symlink tar` pipeline
 * already used for the app's bundled rootfs.tar.zst
 * (see ContainerManageViewModel.performInstall()), then runs the distro's
 * `first_boot_steps`.
 *
 * The caller supplies [execShell], which should be the same
 * "run this in a fresh terminal session and suspend until it exits"
 * function ContainerManageViewModel already uses — this class only builds
 * the commands, it doesn't own the terminal session.
 */
class DistroInstaller(
    private val app: Application,
    private val execShell: suspend (block: () -> Unit) -> Int,
) {
    sealed interface Progress {
        data class Resolving(val distro: DistroEntry) : Progress
        data class Downloading(val distro: DistroEntry, val bytesDownloaded: Long, val totalBytes: Long) : Progress
        data class Extracting(val distro: DistroEntry) : Progress
        data class RunningFirstBootStep(
            val distro: DistroEntry,
            val stepIndex: Int,
            val totalSteps: Int,
            val command: String,
        ) : Progress
        data class Completed(val distro: DistroEntry, val code: String) : Progress
    }

    /** What [dryRun] reports, without downloading/extracting/running anything. */
    data class DryRunReport(
        val distro: DistroEntry,
        val resolvedSizeBytes: Long?,
        val sourceDescription: String,
        val extractionCommandPreview: String,
        val firstBootStepsPreview: List<String>,
    )

    /**
     * Resolves what an install WOULD do — real network calls to find the
     * real download size (OCI manifest lookup, or a HEAD request for static
     * tarballs), but no download, no extraction, no first-boot commands run.
     */
    suspend fun dryRun(distro: DistroEntry): DryRunReport {
        val (sizeBytes, description) = when (val source = distro.source) {
            is DistroSource.StaticTarball -> {
                val size = headContentLength(source.url)
                size to buildString {
                    append("static tarball: ${source.url}")
                    if (size != null) append(" (${formatBytes(size)})")
                    else append(" (size unknown — server did not report Content-Length on HEAD)")
                }
            }
            is DistroSource.Oci -> {
                val token = OciRegistryClient.fetchPullToken(source)
                val layer = OciRegistryClient.resolveArm64Layer(source, token)
                layer.sizeBytes to
                    "OCI ${source.repository}:${source.tag} — layer ${layer.digest} (${formatBytes(layer.sizeBytes)})"
            }
        }

        return DryRunReport(
            distro = distro,
            resolvedSizeBytes = sizeBytes,
            sourceDescription = description,
            extractionCommandPreview = extractionCommand(distro.alias),
            firstBootStepsPreview = distro.firstBootSteps,
        )
    }

    /** Actually installs [distro] into a new container directory named [code]. */
    suspend fun install(
        distro: DistroEntry,
        code: String,
        onProgress: (Progress) -> Unit = {},
    ) {
        onProgress(Progress.Resolving(distro))
        val cacheFile = File(app.cacheDir, "distro-rootfs-$code.tar.gz")

        when (val source = distro.source) {
            is DistroSource.StaticTarball -> downloadPlain(source.url, cacheFile) { downloaded, total ->
                onProgress(Progress.Downloading(distro, downloaded, total))
            }
            is DistroSource.Oci -> {
                val token = OciRegistryClient.fetchPullToken(source)
                val layer = OciRegistryClient.resolveArm64Layer(source, token)
                OciRegistryClient.downloadLayerBlob(source, layer, token, cacheFile) { downloaded, total ->
                    onProgress(Progress.Downloading(distro, downloaded, total))
                }
            }
        }

        onProgress(Progress.Extracting(distro))
        val dir = File(app.dataDir, code)
        if (dir.exists()) dir.deleteRecursively()
        dir.mkdirs()

        execShell {
            Global.setupEnvironment()
            Global.sendCommand(extractionCommand(code, cacheFile.absolutePath))
            distro.firstBootSteps.forEachIndexed { index, step ->
                onProgress(Progress.RunningFirstBootStep(distro, index, distro.firstBootSteps.size, step))
                Global.sendCommand(ProotExec.runInContainerCommand(dir.absolutePath, step))
            }
            Global.sendCommand("rm -f ${cacheFile.absolutePath}")
            Global.sendCommand("exit")
        }

        onProgress(Progress.Completed(distro, code))
    }

    /** Same tar+proot extraction flags ContainerManageViewModel already uses for rootfs.tar.zst. */
    private fun extractionCommand(alias: String): String =
        extractionCommand(alias, "\$CACHE_DIR/distro-rootfs-$alias.tar.gz")

    private fun extractionCommand(code: String, tarballPath: String): String = $$"""
        export CONTAINER_DIR=$${app.dataDir}/$$code
        mkdir -p $CONTAINER_DIR
        $BIN_DIR/proot --link2symlink $BIN_DIR/tar -xzf $$tarballPath -C $CONTAINER_DIR --delay-directory-restore --preserve-permissions
    """.trimIndent()

    private suspend fun headContentLength(url: String): Long? = withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "HEAD"
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 15_000
        }
        try {
            connection.connect()
            connection.contentLengthLong.takeIf { it >= 0 }
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun downloadPlain(
        url: String,
        destFile: File,
        onProgress: (downloaded: Long, total: Long) -> Unit,
    ) = withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 30_000
        }
        try {
            check(connection.responseCode == HttpURLConnection.HTTP_OK) {
                "Download failed: HTTP ${connection.responseCode} for $url"
            }
            val total = connection.contentLengthLong
            var downloaded = 0L
            connection.inputStream.use { input ->
                destFile.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        downloaded += read
                        onProgress(downloaded, total)
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun formatBytes(bytes: Long): String {
        val mb = bytes / (1024.0 * 1024.0)
        return "%.1f MB".format(mb)
    }
}
