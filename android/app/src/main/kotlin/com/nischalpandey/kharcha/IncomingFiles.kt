package com.nischalpandey.kharcha

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.File
import java.io.IOException
import java.util.UUID

/**
 * Takes a file another app shared with Kharcha (the Share sheet, or "Open
 * with") and copies it into the app's own cache.
 *
 * Android only lends access to a shared file: the grant belongs to this
 * activity and ends with it. Copying at once means the rest of the app reads
 * an ordinary private file and needs no storage permission.
 */
object IncomingFiles {
    /** A statement is a few hundred kilobytes; this only stops a runaway copy. */
    private const val MAX_BYTES = 12L * 1024 * 1024
    private const val FOLDER = "incoming"

    /** The file an intent carries, or null when it carries none. */
    fun uriOf(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> streamOf(intent)
            Intent.ACTION_SEND_MULTIPLE -> streamsOf(intent)?.firstOrNull()
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamsOf(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }

    /**
     * Copies [uri] into the cache and describes the copy. Never throws: a file
     * that cannot be taken is reported with an `error` instead of a `path`.
     * Runs on a background thread.
     */
    fun copy(context: Context, uri: Uri, declaredType: String?): Map<String, Any?> {
        val name = displayName(context, uri)
        val mimeType = try {
            context.contentResolver.getType(uri)
        } catch (_: Exception) {
            null
        } ?: declaredType

        // "Open with" can come from any app, naming any file:// path. One
        // that points into this app's own storage is not a statement someone
        // shared: it is this app's private data being fed back to it.
        if (isOwnFile(context, uri)) {
            return mapOf("error" to "unreadable", "name" to name, "mimeType" to mimeType)
        }

        val folder = File(context.cacheDir, FOLDER)
        // Anything left from an earlier share that was never read.
        folder.listFiles()?.forEach { it.delete() }
        folder.mkdirs()
        val target = File(folder, "${UUID.randomUUID()}-${safe(name)}")

        return try {
            var total = 0L
            val input = context.contentResolver.openInputStream(uri)
                ?: throw IOException("No stream for the shared file")
            input.use { source ->
                target.outputStream().use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_BYTES) throw TooLarge()
                        sink.write(buffer, 0, read)
                    }
                }
            }
            mapOf(
                "path" to target.absolutePath,
                "name" to name,
                "mimeType" to mimeType,
                "size" to total,
            )
        } catch (_: TooLarge) {
            target.delete()
            mapOf("error" to "too_large", "name" to name, "mimeType" to mimeType)
        } catch (_: Exception) {
            // The grant has lapsed, the sender withdrew the file, or it is not
            // a readable stream at all.
            target.delete()
            mapOf("error" to "unreadable", "name" to name, "mimeType" to mimeType)
        }
    }

    private class TooLarge : IOException()

    /** Whether a `file://` address resolves to somewhere inside this app's own data. */
    private fun isOwnFile(context: Context, uri: Uri): Boolean {
        if (uri.scheme != "file") return false
        val path = uri.path ?: return true
        return try {
            val target = File(path).canonicalPath
            listOfNotNull(
                context.dataDir,
                context.applicationInfo.dataDir?.let { File(it) },
                context.externalCacheDir?.parentFile,
            ).any { own ->
                val root = own.canonicalPath
                target == root || target.startsWith(root + File.separator)
            }
        } catch (_: IOException) {
            // A path that cannot be resolved is not one to read.
            true
        }
    }

    private fun displayName(context: Context, uri: Uri): String {
        if (uri.scheme == "content") {
            try {
                context.contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            cursor.getString(index)?.let { if (it.isNotBlank()) return it }
                        }
                    }
                }
            } catch (_: Exception) {
                // Some providers refuse the query; the path is used instead.
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "statement"
    }

    /** A name that is only ever a file name, never a path. */
    private fun safe(name: String): String =
        name.replace(Regex("[^A-Za-z0-9._-]"), "_").takeLast(80)
}
