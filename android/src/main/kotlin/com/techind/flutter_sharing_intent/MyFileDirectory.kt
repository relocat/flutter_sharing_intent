// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
package com.techind.flutter_sharing_intent

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
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
    private const val SHARE_PATH_SEGMENTS = 3
    private const val THUMBNAIL_PATH_SEGMENTS = 2
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
     * Copies every URI in [uris] and returns the paths of the copies, skipping
     * URIs that yield no copy. All-or-nothing: if any item fails, every copy
     * already made for this call is deleted before the failure propagates, so
     * a dropped share leaves no plaintext in the cache (FSI-104).
     */
    fun getAbsolutePaths(context: Context, uris: List<Uri>): List<String> {
        val copies = mutableListOf<String>()
        var isComplete = false
        try {
            for (uri in uris) {
                getAbsolutePath(context, uri)?.let { copies.add(it) }
            }
            isComplete = true
        } finally {
            if (!isComplete) deleteShareCopies(copies)
        }
        return copies
    }

    /**
     * Deletes the per-share directory of each copy in [paths]. Only paths of
     * the exact form `<root>/<UUID>/<file>` are honoured, and links are never
     * followed (FSI-104). A failure on one item never stops the others: the
     * first failure is rethrown after the loop with the rest suppressed.
     */
    fun deleteShareCopies(paths: List<String>) {
        var firstFailure: IOException? = null
        for (path in paths) {
            val shareDirectory = File(path).parentFile ?: continue
            val isShareDirectory = UUID_PATTERN.matches(shareDirectory.name) &&
                shareDirectory.parentFile?.name == SHARE_CACHE_DIR_NAME
            if (!isShareDirectory) continue
            try {
                deleteWithoutFollowingLinks(shareDirectory)
            } catch (e: IOException) {
                val earlier = firstFailure
                if (earlier == null) firstFailure = e else earlier.addSuppressed(e)
            }
        }
        firstFailure?.let { throw it }
    }

    /**
     * Runs a thumbnail or duration extraction, returning null instead of
     * failing the whole share when the media is malformed (FSI-104). Only I/O
     * and runtime failures are absorbed; errors such as out-of-memory still
     * propagate. The log carries the exception class only.
     */
    fun <T> orNullOnMediaFailure(extract: () -> T?): T? {
        return try {
            extract()
        } catch (e: IOException) {
            Log.w("FlutterSharingIntent", "Media extraction failed: ${e.javaClass.simpleName}")
            null
        } catch (e: RuntimeException) {
            Log.w("FlutterSharingIntent", "Media extraction failed: ${e.javaClass.simpleName}")
            null
        }
    }

    /**
     * Copies the stream behind [uri] into a fresh per-share directory below
     * the plugin cache root and returns the copy's path (FSI-100, FSI-102).
     *
     * The display name comes from the provider and is only ever used as the
     * leaf name, after [sanitizeDisplayName]. A URI without an authority names
     * no provider, so it yields null instead of falling back to a provider
     * supplied `_data` path. On ANY failure after the directory exists, the
     * directory and its partial content are deleted before the failure
     * propagates (FSI-104).
     *
     * @param context The context.
     * @param uri The Uri to copy.
     * @return The path of the cache copy, or null if there is nothing to copy.
     */
    private fun getDataColumn(context: Context, uri: Uri): String? {
        if (uri.authority.isNullOrEmpty()) return null

        val displayName = queryDisplayName(context, uri)
        val fileName = if (displayName != null) {
            sanitizeDisplayName(displayName)
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
            "${prefix}_${Date().time}.$type"
        }

        val targetFile = newShareTargetFile(context.cacheDir, fileName)
        var copiedPath: String? = null
        try {
            copiedPath = copyStream(context, uri, targetFile)
        } finally {
            if (copiedPath == null) targetFile.parentFile?.let { deleteWithoutFollowingLinks(it) }
        }
        return copiedPath
    }

    /**
     * Streams [uri] into [targetFile] and returns its path, or null if the
     * provider has no stream. SECURITY (FSI-90): enforces the 16 MiB cap.
     */
    private fun copyStream(context: Context, uri: Uri, targetFile: File): String? {
        val input = context.contentResolver.openInputStream(uri) ?: return null
        input.use {
            FileOutputStream(targetFile).use { fileOut ->
                val buffer = ByteArray(COPY_BUFFER_BYTES)
                var totalWritten: Long = 0
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    totalWritten += read
                    if (totalWritten > MAX_STREAM_BYTES) {
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
     * another cache file, and nothing is written to the cacheDir root. The
     * root is re-created on every call because the host may wipe it, and
     * stale per-share directories are pruned first.
     *
     * @param cacheDir The host app cache directory.
     * @param fileName An already sanitised leaf name.
     */
    internal fun newShareTargetFile(cacheDir: File, fileName: String): File {
        val root = ensureDirectory(File(cacheDir, SHARE_CACHE_DIR_NAME))
        pruneStaleEntries(root, requireUuidDirectories = true)
        val shareDirectory = File(root, UUID.randomUUID().toString())
        if (!shareDirectory.mkdir()) {
            throw IOException("flutter_sharing_intent: cannot create share directory")
        }
        return File(shareDirectory, fileName)
    }

    /**
     * Returns a fresh, unique PNG path for a video thumbnail (FSI-102).
     *
     * Thumbnails live in their own root,
     * `<cacheDir>/flutter_sharing_intent_thumbnails/<random UUID>.png`, never
     * inside a per-share directory and never under a sender-chosen name. The
     * root is re-created on every call. Stale thumbnails are pruned first
     * (FSI-23).
     */
    internal fun newThumbnailFile(cacheDir: File): File {
        val root = ensureDirectory(File(cacheDir, THUMBNAIL_CACHE_DIR_NAME))
        pruneStaleEntries(root, requireUuidDirectories = false)
        return File(root, "${UUID.randomUUID()}.png")
    }

    /** What a path is, judged WITHOUT following a final symbolic link. */
    internal enum class EntryType { MISSING, LINK, DIRECTORY, FILE, OTHER }

    /**
     * Classifies [file] with `lstat`, so a symbolic link is reported as
     * [EntryType.LINK] and never followed (FSI-104). Uses only API 21 calls.
     */
    internal fun entryType(file: File): EntryType {
        try {
            val mode = Os.lstat(file.path).st_mode
            return when {
                OsConstants.S_ISLNK(mode) -> EntryType.LINK
                OsConstants.S_ISDIR(mode) -> EntryType.DIRECTORY
                OsConstants.S_ISREG(mode) -> EntryType.FILE
                else -> EntryType.OTHER
            }
        } catch (e: ErrnoException) {
            if (e.errno == OsConstants.ENOENT || e.errno == OsConstants.ENOTDIR) return EntryType.MISSING
            throw IOException("flutter_sharing_intent: cannot inspect cache entry (errno ${e.errno})")
        }
    }

    /**
     * Makes sure [directory] exists as a real directory and returns it
     * (FSI-104). A symbolic link in its place is never followed: the call
     * fails closed. A plain file in its place is deleted and replaced, so a
     * leftover from an older layout cannot block sharing.
     */
    internal fun ensureDirectory(directory: File): File {
        when (entryType(directory)) {
            EntryType.DIRECTORY -> return directory
            EntryType.LINK -> throw IOException("flutter_sharing_intent: cache root is a symbolic link")
            EntryType.MISSING -> Unit
            else -> if (!directory.delete()) throw IOException("flutter_sharing_intent: cannot replace cache root")
        }
        directory.mkdirs()
        if (entryType(directory) != EntryType.DIRECTORY) {
            throw IOException("flutter_sharing_intent: cannot create cache root")
        }
        return directory
    }

    /**
     * Deletes [target] and everything below it WITHOUT following symbolic
     * links: a link is removed itself and its target is left alone (FSI-104).
     * Manual recursion over API 21 calls: each entry is classified with
     * `lstat`, only real directories are descended into, and `File.delete`
     * removes links as links. Errors do not stop the walk; the first one is
     * thrown at the end with the others suppressed, and a parent that cannot
     * be removed because a child failed adds no error of its own.
     */
    internal fun deleteWithoutFollowingLinks(target: File) {
        val failures = mutableListOf<IOException>()
        deleteEntry(target, failures)
        val first = failures.firstOrNull() ?: return
        failures.drop(1).forEach { first.addSuppressed(it) }
        throw first
    }

    private fun deleteEntry(entry: File, failures: MutableList<IOException>) {
        val type = try {
            entryType(entry)
        } catch (e: IOException) {
            failures.add(e)
            return
        }
        if (type == EntryType.MISSING) return
        if (type == EntryType.DIRECTORY) {
            val children = entry.list()
            if (children == null) {
                failures.add(IOException("flutter_sharing_intent: cannot list cache directory"))
                return
            }
            children.forEach { deleteEntry(File(entry, it), failures) }
        }
        if (!entry.delete() && failures.isEmpty()) {
            failures.add(IOException("flutter_sharing_intent: cannot delete cache entry"))
        }
    }

    /**
     * Writes a video thumbnail through [compress] into a fresh file in the
     * thumbnail root and returns its path (FSI-104). A `false` result or an
     * exception from [compress] deletes the file and yields null (or
     * rethrows), so a failed write never leaves a partial thumbnail.
     */
    internal fun writeThumbnail(cacheDir: File, compress: (java.io.OutputStream) -> Boolean): String? {
        val target = newThumbnailFile(cacheDir)
        var isWritten = false
        try {
            FileOutputStream(target).use { out -> isWritten = compress(out) }
        } finally {
            if (!isWritten) target.delete()
        }
        return if (isWritten) target.path else null
    }

    /**
     * Deletes the plugin's own copies named in [paths] and returns how many
     * files were removed (A-2, FSI-104). Only two shapes are owned, both
     * directly below [cacheDir]: a regular file `flutter_sharing_intent/<UUID>/<name>`
     * (its emptied directory is then removed, non-recursively) and a regular
     * file `flutter_sharing_intent_thumbnails/<UUID>.png`. Everything else, and
     * any path through a symbolic link, is refused.
     */
    fun removeOwnedFiles(cacheDir: File, paths: List<String>): Int {
        var removed = 0
        for (path in paths) {
            val owned = ownedFile(cacheDir, path) ?: continue
            if (!owned.delete()) continue
            removed++
            if (owned.parentFile?.name != THUMBNAIL_CACHE_DIR_NAME) owned.parentFile?.delete()
        }
        return removed
    }

    /** Returns the file for [path] if it is an owned regular file below real directories, else null. */
    private fun ownedFile(cacheDir: File, path: String): File? {
        val prefix = cacheDir.path + "/"
        if (!path.startsWith(prefix)) return null
        val segments = path.removePrefix(prefix).split("/")
        if (segments.any { it.isEmpty() || it == "." || it == ".." }) return null
        val isShareFile = segments.size == SHARE_PATH_SEGMENTS && segments[0] == SHARE_CACHE_DIR_NAME &&
            UUID_PATTERN.matches(segments[1]) && sanitizeDisplayName(segments[2]) == segments[2]
        val isThumbnail = segments.size == THUMBNAIL_PATH_SEGMENTS && segments[0] == THUMBNAIL_CACHE_DIR_NAME &&
            segments[1].endsWith(THUMBNAIL_SUFFIX) && UUID_PATTERN.matches(segments[1].removeSuffix(THUMBNAIL_SUFFIX))
        if (!isShareFile && !isThumbnail) return null
        return try {
            val directories = (1 until segments.size).map { File(cacheDir, segments.take(it).joinToString("/")) }
            val file = File(cacheDir, segments.joinToString("/"))
            val isReal = directories.all { entryType(it) == EntryType.DIRECTORY } &&
                entryType(file) == EntryType.FILE
            if (isReal) file else null
        } catch (e: IOException) {
            null
        }
    }

    /**
     * Deletes direct children of [root] last modified more than
     * [CACHE_ENTRY_TTL_MILLIS] ago. Only entries this plugin could have
     * created are touched: UUID-named directories under the share root, or
     * `.png` files under the thumbnail root. Symbolic links are neither
     * followed nor deleted. Best-effort: a failure on one entry is logged
     * without any path and the remaining entries are still pruned.
     */
    internal fun pruneStaleEntries(
        root: File,
        requireUuidDirectories: Boolean,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        val cutoff = nowMillis - CACHE_ENTRY_TTL_MILLIS
        val entries = try {
            root.listFiles()
        } catch (e: SecurityException) {
            Log.w("FlutterSharingIntent", "Cache prune failed: ${e.javaClass.simpleName}")
            null
        } ?: return
        for (entry in entries) {
            try {
                if (entryType(entry) == EntryType.LINK || entry.lastModified() >= cutoff) continue
                val isOurs = if (requireUuidDirectories) {
                    entry.isDirectory && UUID_PATTERN.matches(entry.name)
                } else {
                    entry.isFile && entry.name.endsWith(THUMBNAIL_SUFFIX)
                }
                if (isOurs) deleteWithoutFollowingLinks(entry)
            } catch (e: IOException) {
                Log.w("FlutterSharingIntent", "Cache prune failed: ${e.javaClass.simpleName}")
            } catch (e: SecurityException) {
                Log.w("FlutterSharingIntent", "Cache prune failed: ${e.javaClass.simpleName}")
            }
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
