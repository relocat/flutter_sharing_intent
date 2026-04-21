// SPDX-License-Identifier: Apache-2.0
package com.techind.flutter_sharing_intent

import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
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
     * Plugin-level size cap for content streamed via ContentResolver.
     * A malicious source app can offer an unbounded stream; this cap ensures
     * we abort and clean up rather than fill the host app's cacheDir (FSI-90).
     * Host apps that legitimately need a higher cap should override at the
     * service layer (the host app enforces its own, larger limit; 16 MiB here is the plugin floor).
     */
    private const val MAX_STREAM_BYTES: Long = 16L * 1024L * 1024L // 16 MiB

    /**
     * Maximum byte length of a cache filename derived from _display_name (FSI-91).
     * Matches the POSIX NAME_MAX limit for most Linux/Android filesystems.
     */
    private const val MAX_DISPLAY_NAME_BYTES: Int = 255

    /**
     * Get a file path from a Uri. This will get the the path for Storage Access
     * Framework Documents, as well as the _data field for the MediaStore and
     * other file-based ContentProviders.
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
            Log.w("FlutterSharingIntent",
                "Rejected non-content URI scheme: ${uri.scheme}")
            return null
        }

        // DocumentProvider
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT && DocumentsContract.isDocumentUri(context, uri)) {
            // ExternalStorageProvider
            if (isExternalStorageDocument(uri)) {
                val docId = DocumentsContract.getDocumentId(uri)
                val split = docId.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
                val type = split[0]

                return if ("primary".equals(type, ignoreCase = true)) {
                    Environment.getExternalStorageDirectory().toString() + "/" + split[1]
                } else {
                    getDataColumn(context, uri, null, null)
                }
            } else if (isDownloadsDocument(uri)) {
                return try {
                    val id = DocumentsContract.getDocumentId(uri)
                    val contentUri = ContentUris.withAppendedId(
                        Uri.parse("content://downloads/public_downloads"), java.lang.Long.valueOf(id))

                    getDataColumn(context, contentUri, null, null)
                } catch (exception: Exception) {
                    getDataColumn(context, uri, null, null)
                }
            } else if (isMediaDocument(uri)) {
                val docId = DocumentsContract.getDocumentId(uri)
                val split = docId.split(":".toRegex()).dropLastWhile { it.isEmpty() }.toTypedArray()
                val type = split[0]

                var contentUri: Uri? = null
                when (type) {
                    "image" -> contentUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    "video" -> contentUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    "audio" -> contentUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                }

                if (contentUri == null) return null

                val selection = "_id=?"
                val selectionArgs = arrayOf(split[1])
                return getDataColumn(context, contentUri, selection, selectionArgs)
            }// MediaProvider
            // DownloadsProvider
        } else if ("content".equals(uri.scheme, ignoreCase = true)) {
            return getDataColumn(context, uri, null, null)
        }

        return uri.path
    }

    /**
     * Get the value of the data column for this Uri. This is useful for
     * MediaStore Uris, and other file-based ContentProviders.
     *
     * @param context The context.
     * @param uri The Uri to query.
     * @param selection (Optional) Filter used in the query.
     * @param selectionArgs (Optional) Selection arguments used in the query.
     * @return The value of the _data column, which is typically a file path.
     */
    private fun getDataColumn(context: Context, uri: Uri, selection: String?,
                              selectionArgs: Array<String>?): String? {

        if (uri.authority != null) {
            var cursor: Cursor? = null
            val column = "_display_name"
            val projection = arrayOf(column)
            var targetFile: File? = null
            try {
                cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, null)
                if (cursor != null && cursor.moveToFirst()) {
                    val columnIndex = cursor.getColumnIndexOrThrow(column)
                    val rawName = cursor.getString(columnIndex)
                    // SECURITY (FSI-91): _display_name is provider-controlled. Sanitize
                    // before using as a cache filename to prevent path traversal.
                    val fileName = sanitizeDisplayName(rawName)
                    Log.i("FileDirectory", "File name (sanitized): $fileName")
                    targetFile = File(context.cacheDir, fileName)
                }
            } finally {
                cursor?.close()
            }

            if (targetFile == null) {
                val mimeType = context.contentResolver.getType(uri)
                val prefix = with(mimeType ?: "") {
                    when {
                        startsWith("image") -> "IMG"
                        startsWith("video") -> "VID"
                        else -> "FILE"
                    }
                }
                val type = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
                targetFile = File(context.cacheDir, "${prefix}_${Date().time}.$type")
            }

            // SECURITY (FSI-90): Enforce a 16 MiB cap on content streamed from
            // a provider-controlled URI. Abort and delete the partial file if
            // the source exceeds the cap.
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(targetFile).use { fileOut ->
                    val buffer = ByteArray(8192)
                    var totalWritten: Long = 0
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        totalWritten += read
                        if (totalWritten > MAX_STREAM_BYTES) {
                            fileOut.close()
                            targetFile!!.delete()
                            throw IOException(
                                "flutter_sharing_intent: source exceeds ${MAX_STREAM_BYTES / (1024 * 1024)} MiB plugin cap"
                            )
                        }
                        fileOut.write(buffer, 0, read)
                    }
                }
            }
            return targetFile.path
        }

        var cursor: Cursor? = null
        val column = "_data"
        val projection = arrayOf(column)

        try {
            cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, null)
            if (cursor != null && cursor.moveToFirst()) {
                val columnIndex = cursor.getColumnIndexOrThrow(column)
                return cursor.getString(columnIndex)
            }
        } finally {
            cursor?.close()
        }
        return null
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
     * 4. Cap at MAX_DISPLAY_NAME_BYTES (255) bytes in UTF-8.
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
            // Truncate at a character boundary within the byte limit
            String(bytes, 0, MAX_DISPLAY_NAME_BYTES, Charsets.UTF_8)
        }

        // Final guard: ensure truncation didn't produce a blank or dot name
        if (safe.isBlank() || safe == "." || safe == "..") return "unnamed"
        return safe
    }

    /**
     * @param uri The Uri to check.
     * @return Whether the Uri authority is ExternalStorageProvider.
     */
    private fun isExternalStorageDocument(uri: Uri): Boolean {
        return "com.android.externalstorage.documents" == uri.authority
    }

    /**
     * @param uri The Uri to check.
     * @return Whether the Uri authority is DownloadsProvider.
     */
    private fun isDownloadsDocument(uri: Uri): Boolean {
        return "com.android.providers.downloads.documents" == uri.authority
    }

    /**
     * @param uri The Uri to check.
     * @return Whether the Uri authority is MediaProvider.
     */
    private fun isMediaDocument(uri: Uri): Boolean {
        return "com.android.providers.media.documents" == uri.authority
    }
}
