// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
package com.techind.flutter_sharing_intent

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.util.*

/**
 **  Author - Bhagat Singh
 **  Contact - https://www.linkedin.com/in/bhagat-singh-79496a14b/
 **  Created On - 25/11/2022
 **  Purpose -  Created [MyFileDirectory] to get path of a file
 */

object MyFileDirectory {

    /**
     * Hard per-file ceiling for content streamed via ContentResolver (FSI-90).
     * A malicious source app can offer an unbounded stream; this cap ensures
     * we abort and clean up rather than fill the host app's cacheDir.
     *
     * A host app cannot raise this limit at runtime: changing it means editing
     * this constant. When any one file in a share exceeds it, the resulting
     * IOException aborts the whole share: no item of that share reaches Dart,
     * and the plugin only logs the failure. A host app can enforce a lower
     * limit of its own, but not a higher one.
     */
    private const val MAX_STREAM_BYTES: Long = 16L * 1024L * 1024L // 16 MiB

    /**
     * Maximum byte length of a cache filename derived from _display_name (FSI-91).
     * Matches the POSIX NAME_MAX limit for most Linux/Android filesystems.
     */
    private const val MAX_DISPLAY_NAME_BYTES: Int = 255

    /** Root directory below cacheDir that holds every per-share directory (FSI-102). */
    const val SHARE_CACHE_DIR_NAME: String = "flutter_sharing_intent"

    /** Separate cacheDir root for generated video thumbnails (FSI-102). */
    const val THUMBNAIL_CACHE_DIR_NAME: String = "flutter_sharing_intent_thumbnails"

    private const val THUMBNAIL_SUFFIX = ".png"
    private const val DISPLAY_NAME_COLUMN = "_display_name"
    private const val COPY_BUFFER_BYTES = 8192
    private const val BYTES_PER_MIB = 1024 * 1024

    /** Age after which a per-share directory or thumbnail is pruned (FSI-23, FSI-102). */
    const val CACHE_ENTRY_TTL_MILLIS: Long = 7L * 24L * 60L * 60L * 1000L

    /** Canonical lowercase UUID v4 text form, as produced by [UUID.randomUUID]. */
    private val UUID_PATTERN = Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")

    /**
     * Copies the content behind [uri] into the plugin's cache and returns the
     * path of the copy, or null when the URI cannot be copied (FSI-100).
     *
     * No path is ever derived from the URI itself: its path, its document id
     * and the provider's `_data` column are all sender-controlled, so the only
     * path this function returns is one the plugin created under its own
     * per-share cache directory. Every content:// URI, document providers
     * included, takes the same capped copy.
     *
     * @param context The context.
     * @param uri The Uri to query.
     * @author paulburke
     */
    fun getAbsolutePath(context: Context, uri: Uri): String? {

        // SECURITY: Only content:// URIs are trusted from third-party intents.
        // file:// and other schemes from untrusted sharers can point at our
        // own sandbox (FSI-21).
        if (!"content".equals(uri.scheme, ignoreCase = true)) {
            Log.w("FlutterSharingIntent", "Rejected non-content URI scheme")
            return null
        }

        return getDataColumn(context, uri)
    }

    /**
     * Copies the stream behind [uri] into a fresh per-share directory below
     * the plugin cache root and returns the copy's path (FSI-100, FSI-102).
     *
     * The display name comes from the provider and is only ever used as the
     * leaf name, after [sanitizeDisplayName]. A URI without an authority names
     * no provider, so it yields null instead of falling back to a provider
     * supplied `_data` path.
     *
     * @param context The context.
     * @param uri The Uri to copy.
     * @return The path of the cache copy, or null if there is nothing to copy.
     */
    private fun getDataColumn(context: Context, uri: Uri): String? {
        if (uri.authority == null) return null

        val displayName = queryDisplayName(context, uri)
        val targetFile = if (displayName != null) {
            newShareTargetFile(context.cacheDir, sanitizeDisplayName(displayName))
        } else {
            val mimeType = context.contentResolver.getType(uri)
            val prefix = with(mimeType ?: "") {
                when {
                    startsWith("image") -> "IMG"
                    startsWith("video") -> "VID"
                    else -> "FILE"
                }
            }
            val type = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
            newShareTargetFile(context.cacheDir, "${prefix}_${Date().time}.$type")
        }

        // SECURITY (FSI-90): Enforce a 16 MiB cap on content streamed from
        // a provider-controlled URI. Abort and delete the partial file if
        // the source exceeds the cap.
        val input = context.contentResolver.openInputStream(uri)
        if (input == null) {
            targetFile.parentFile?.deleteRecursively()
            return null
        }
        input.use {
            FileOutputStream(targetFile).use { fileOut ->
                val buffer = ByteArray(COPY_BUFFER_BYTES)
                var totalWritten: Long = 0
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    totalWritten += read
                    if (totalWritten > MAX_STREAM_BYTES) {
                        fileOut.close()
                        targetFile.parentFile?.deleteRecursively()
                        throw IOException(
                            "flutter_sharing_intent: source exceeds ${MAX_STREAM_BYTES / BYTES_PER_MIB} MiB plugin cap"
                        )
                    }
                    fileOut.write(buffer, 0, read)
                }
            }
        }
        return targetFile.path
    }

    /** Returns the provider's `_display_name` for [uri], or null if it has none. */
    private fun queryDisplayName(context: Context, uri: Uri): String? {
        var cursor: Cursor? = null
        try {
            cursor = context.contentResolver.query(uri, arrayOf(DISPLAY_NAME_COLUMN), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndexOrThrow(DISPLAY_NAME_COLUMN)
                return cursor.getString(columnIndex)
            }
        } finally {
            cursor?.close()
        }
        return null
    }

    /**
     * Creates a new, empty per-share directory and returns the file to write
     * inside it (FSI-102).
     *
     * Layout: `<cacheDir>/flutter_sharing_intent/<random UUID>/<name>`. Each
     * share item gets its own directory, so a sender can never overwrite
     * another cache file, and nothing is written to the cacheDir root. Stale
     * per-share directories are pruned first.
     *
     * @param cacheDir The host app cache directory.
     * @param fileName An already sanitised leaf name.
     */
    internal fun newShareTargetFile(cacheDir: File, fileName: String): File {
        pruneStaleEntries(File(cacheDir, SHARE_CACHE_DIR_NAME), requireUuidDirectories = true)
        val shareDirectory = File(File(cacheDir, SHARE_CACHE_DIR_NAME), UUID.randomUUID().toString())
        if (!shareDirectory.mkdirs()) {
            throw IOException("flutter_sharing_intent: cannot create share directory")
        }
        return File(shareDirectory, fileName)
    }

    /**
     * Returns a fresh, unique PNG path for a video thumbnail (FSI-102).
     *
     * Thumbnails live in their own root,
     * `<cacheDir>/flutter_sharing_intent_thumbnails/<random UUID>.png`, never
     * inside a per-share directory and never under a sender-chosen name.
     * Stale thumbnails are pruned first (FSI-23).
     */
    internal fun newThumbnailFile(cacheDir: File): File {
        val root = File(cacheDir, THUMBNAIL_CACHE_DIR_NAME)
        pruneStaleEntries(root, requireUuidDirectories = false)
        if (!root.isDirectory && !root.mkdirs()) {
            throw IOException("flutter_sharing_intent: cannot create thumbnail directory")
        }
        return File(root, "${UUID.randomUUID()}.png")
    }

    /**
     * Deletes direct children of [root] last modified more than
     * [CACHE_ENTRY_TTL_MILLIS] ago. Only entries this plugin could have
     * created are touched: UUID-named directories under the share root, or
     * `.png` files under the thumbnail root. Symbolic links are never
     * followed or deleted. Best-effort: a failure is logged without any path.
     */
    internal fun pruneStaleEntries(
        root: File,
        requireUuidDirectories: Boolean,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        val cutoff = nowMillis - CACHE_ENTRY_TTL_MILLIS
        try {
            root.listFiles()?.forEach { entry ->
                if (Files.isSymbolicLink(entry.toPath()) || entry.lastModified() >= cutoff) return@forEach
                val isOurs = if (requireUuidDirectories) {
                    entry.isDirectory && UUID_PATTERN.matches(entry.name)
                } else {
                    entry.isFile && entry.name.endsWith(THUMBNAIL_SUFFIX)
                }
                if (isOurs) entry.deleteRecursively()
            }
        } catch (e: SecurityException) {
            Log.w("FlutterSharingIntent", "Cache prune failed: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Sanitize a provider-supplied _display_name so it is safe to use as a
     * cache-directory filename (FSI-91).
     *
     * Rules applied in order:
     * 1. Take only the component after the last '/' or '\\' (strip any embedded
     *    path prefix the provider might inject).
     * 2. Reject the special names "." and ".."; replace with "unnamed".
     * 3. Strip NUL bytes and C0 control characters (U+0000..U+001F).
     * 4. Cap at MAX_DISPLAY_NAME_BYTES (255) bytes in UTF-8, cutting at a code
     *    point boundary so the result is valid UTF-8 without U+FFFD.
     * 5. Fall back to "unnamed" for null, blank, or empty results.
     *
     * @param raw The raw _display_name string from the ContentResolver cursor.
     * @return A safe, non-empty filename component with no path separators.
     */
    internal fun sanitizeDisplayName(raw: String?): String {
        if (raw.isNullOrBlank()) return "unnamed"

        // Step 1: strip any path prefix (provider may inject slashes)
        val lastSlash = raw.lastIndexOfAny(charArrayOf('/', '\\'))
        val component = if (lastSlash >= 0) raw.substring(lastSlash + 1) else raw

        // Step 2: reject dot-only special names
        if (component == "." || component == "..") return "unnamed"

        // Step 3: strip NUL and C0 control characters (codepoint < 0x20)
        val stripped = component.filter { ch -> ch.code >= 0x20 }

        if (stripped.isBlank()) return "unnamed"

        // Step 4: cap at 255 UTF-8 bytes
        val bytes = stripped.toByteArray(Charsets.UTF_8)
        val safe: String = if (bytes.size <= MAX_DISPLAY_NAME_BYTES) {
            stripped
        } else {
            // Truncate at a code point boundary within the byte limit: step back
            // over UTF-8 continuation bytes (10xxxxxx), so no multi-byte sequence
            // is split and the decoder never substitutes U+FFFD.
            var end = MAX_DISPLAY_NAME_BYTES
            while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end--
            String(bytes, 0, end, Charsets.UTF_8)
        }

        // Final guard: ensure truncation didn't produce a blank or dot name
        if (safe.isBlank() || safe == "." || safe == "..") return "unnamed"
        return safe
    }
}
