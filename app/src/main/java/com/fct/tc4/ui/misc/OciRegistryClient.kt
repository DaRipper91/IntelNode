// OciRegistryClient.kt -- This file is part of tiny_container.
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

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * A small, purpose-built Docker Registry v2 (OCI distribution spec) HTTP
 * client — NOT upstream proot-distro. proot-distro's own 2026 rewrite moved
 * to Python and this app does not bundle a Python runtime, so distro pulls
 * for [DistroSource.Oci] entries go through this instead. It only implements
 * the handful of calls needed to resolve an anonymous-pull public image tag
 * to its single arm64 layer blob and stream that blob to a file — it is not
 * a general OCI/registry client (no auth beyond anonymous pull tokens, no
 * multi-layer image support, since every currently-configured OCI distro in
 * distros.yaml was verified to resolve to exactly one layer).
 */
object OciRegistryClient {

    data class LayerInfo(val digest: String, val sizeBytes: Long)

    private const val ARCH = "arm64"
    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 30_000

    /** Fetches a short-lived anonymous pull token for [source]'s repository. */
    suspend fun fetchPullToken(source: DistroSource.Oci): String = withContext(Dispatchers.IO) {
        val url = "${source.authRealm}?service=${source.authService}" +
            "&scope=repository:${source.repository}:pull"
        val body = httpGetString(url, emptyMap())
        JSONObject(body).getString("token")
    }

    /**
     * Resolves [source]'s tag to the single arm64 layer that image tag
     * actually contains. Two HTTP round-trips: the manifest list (to find
     * the arm64-specific manifest's digest), then that manifest (to read
     * its layer list). Throws if the image isn't exactly one layer, since
     * that's the only shape this client supports (see class kdoc).
     */
    suspend fun resolveArm64Layer(source: DistroSource.Oci, token: String): LayerInfo =
        withContext(Dispatchers.IO) {
            val manifestListUrl =
                "https://${source.registry}/v2/${source.repository}/manifests/${source.tag}"
            val listAccept = "application/vnd.oci.image.index.v1+json," +
                "application/vnd.docker.distribution.manifest.list.v2+json"
            val listBody = httpGetString(
                manifestListUrl,
                mapOf("Authorization" to "Bearer $token", "Accept" to listAccept),
            )
            val manifests = JSONObject(listBody).getJSONArray("manifests")
            var archDigest: String? = null
            for (i in 0 until manifests.length()) {
                val entry = manifests.getJSONObject(i)
                val platform = entry.optJSONObject("platform") ?: continue
                if (platform.optString("architecture") == ARCH) {
                    archDigest = entry.getString("digest")
                    break
                }
            }
            requireNotNull(archDigest) {
                "No $ARCH manifest found for ${source.repository}:${source.tag}"
            }

            val manifestUrl = "https://${source.registry}/v2/${source.repository}/manifests/$archDigest"
            val manifestAccept = "application/vnd.oci.image.manifest.v1+json," +
                "application/vnd.docker.distribution.manifest.v2+json"
            val manifestBody = httpGetString(
                manifestUrl,
                mapOf("Authorization" to "Bearer $token", "Accept" to manifestAccept),
            )
            val layers = JSONObject(manifestBody).getJSONArray("layers")
            require(layers.length() == 1) {
                "Expected exactly 1 layer for ${source.repository}:${source.tag}, found ${layers.length()}"
            }
            val layer = layers.getJSONObject(0)
            LayerInfo(layer.getString("digest"), layer.getLong("size"))
        }

    /**
     * Streams the given layer blob to [destFile], calling [onProgress] with
     * bytes-downloaded-so-far as it goes. The blob is itself a gzip tarball
     * (application/vnd.oci.image.layer.v1.tar+gzip) — callers extract it
     * exactly like the app's existing bundled rootfs.tar.zst, just gzip
     * instead of zstd.
     */
    suspend fun downloadLayerBlob(
        source: DistroSource.Oci,
        layer: LayerInfo,
        token: String,
        destFile: File,
        onProgress: (bytesDownloaded: Long, totalBytes: Long) -> Unit = { _, _ -> },
    ) = withContext(Dispatchers.IO) {
        val url = URL("https://${source.registry}/v2/${source.repository}/blobs/${layer.digest}")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            setRequestProperty("Authorization", "Bearer $token")
            instanceFollowRedirects = true
        }
        try {
            check(connection.responseCode == HttpURLConnection.HTTP_OK) {
                "Blob download failed: HTTP ${connection.responseCode} for ${layer.digest}"
            }
            var downloaded = 0L
            connection.inputStream.use { input ->
                destFile.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        downloaded += read
                        onProgress(downloaded, layer.sizeBytes)
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun httpGetString(url: String, headers: Map<String, String>): String {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            headers.forEach { (key, value) -> setRequestProperty(key, value) }
        }
        try {
            check(connection.responseCode == HttpURLConnection.HTTP_OK) {
                "GET $url failed: HTTP ${connection.responseCode}"
            }
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }
}
