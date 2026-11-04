// SPDX-License-Identifier: Apache-2.0
// Added by Relocat (2026); see NOTICE.
//
// JVM test harness for MyFileDirectory. It compiles the real Kotlin source
// against the Java stand-ins in ../stubs (no Android SDK, no Robolectric) and
// exits with the number of failed checks. Run it with ../run.sh.

import android.content.Context
import android.net.Uri
import com.techind.flutter_sharing_intent.MyFileDirectory
import java.io.File
import java.io.IOException
import java.nio.file.Files

private var failures = 0
private val uuidPattern = Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
private const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L
private const val SOURCE_OVER_CAP_BYTES = 16 * 1024 * 1024 + 1
private const val STALE_AGE_DAYS = 8L
private const val MID_READ_BYTES = 4096
private const val BOUNDARY_MARGIN_MILLIS = 60_000L
private const val MIN_EXPECTED_LOG_CALLS = 6

private fun check(name: String, ok: Boolean, detail: String = "") {
    println((if (ok) "PASS " else "FAIL ") + name + (if (ok) "" else "  $detail"))
    if (!ok) failures++
}

private fun freshContext(): Context =
    Context(Files.createTempDirectory("fsi-cache").toFile().canonicalFile)

private fun Context.register(uri: String, name: String?, bytes: ByteArray, mime: String? = null) {
    if (name != null) contentResolver.displayNames[uri] = name
    contentResolver.contents[uri] = bytes
    if (mime != null) contentResolver.types[uri] = mime
}

private fun isInsideShareRoot(context: Context, path: String?): Boolean {
    if (path == null) return false
    val root = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).canonicalFile
    return File(path).canonicalFile.toPath().startsWith(root.toPath())
}

// Test 1: a document id that tries to leave the storage root yields no path outside cacheDir.
private fun testPrimaryDocumentIdCannotEscape() {
    val context = freshContext()
    val uri = "content://com.android.externalstorage.documents/document/primary%3A..%2F..%2F..%2Fa%2Fb%2Fc"
    context.register(uri, "c", "x".toByteArray())
    val result = MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("1 primary document id: result is null or inside the share root", result == null || isInsideShareRoot(context, result), "got $result")
    check("1 primary document id: no raw storage path", result?.startsWith("/storage") != true, "got $result")
}

// Test 2: a third-party DocumentsProvider authority never yields uri.path.
private fun testThirdPartyDocumentProviderNeverReturnsUriPath() {
    val context = freshContext()
    val uriText = "content://com.thirdparty.docs/document/..%2F..%2Fa%2Fb%2Fc"
    val uri = Uri.parse(uriText)
    context.register(uriText, "c.xml", "x".toByteArray())
    val result = MyFileDirectory.getAbsolutePath(context, uri)
    check("2 third-party provider: result differs from uri.path", result != uri.path, "got $result")
    check("2 third-party provider: result is inside the share root", isInsideShareRoot(context, result), "got $result")
    val unregistered = Uri.parse("content://com.thirdparty.docs/document/other")
    check("2 third-party provider: unreadable source yields null", MyFileDirectory.getAbsolutePath(context, unregistered) == null)
}

// Test 3: a normal content:// share still yields a cacheDir copy.
private fun testNormalContentShareIsCopied() {
    val context = freshContext()
    val uri = "content://com.example.provider/files/42"
    val payload = "hello".toByteArray()
    context.register(uri, "photo.jpg", payload)
    val result = MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("3 normal share: copy inside the share root", isInsideShareRoot(context, result), "got $result")
    check("3 normal share: leaf is the display name", result != null && File(result).name == "photo.jpg")
    check("3 normal share: bytes copied", result != null && File(result).readBytes().contentEquals(payload))
}

private fun testRejectedInputs() {
    val context = freshContext()
    check("file:// is rejected", MyFileDirectory.getAbsolutePath(context, Uri.parse("file:///a/b/c")) == null)
    val noAuthority = "content:///a/b/c"
    context.register(noAuthority, "x", "x".toByteArray())
    check("content URI with an empty authority yields null", MyFileDirectory.getAbsolutePath(context, Uri.parse(noAuthority)) == null)
}

// R-2: per-share directories.
private fun testEachShareGetsItsOwnDirectory() {
    val context = freshContext()
    val first = "content://p.a/1"
    val second = "content://p.b/2"
    context.register(first, "same.txt", "one".toByteArray())
    context.register(second, "same.txt", "two".toByteArray())
    val pathOne = MyFileDirectory.getAbsolutePath(context, Uri.parse(first))
    val pathTwo = MyFileDirectory.getAbsolutePath(context, Uri.parse(second))
    check("R-2 two shares with one name land in different files", pathOne != null && pathOne != pathTwo, "$pathOne / $pathTwo")
    check("R-2 neither share overwrote the other", File(pathOne!!).readText() == "one" && File(pathTwo!!).readText() == "two")
    val parents = listOf(pathOne, pathTwo).map { File(it).parentFile }
    check("R-2 parent directories are lowercase UUID v4", parents.all { uuidPattern.matches(it.name) })
    check("R-2 each per-share directory holds exactly one file", parents.all { it.list()!!.size == 1 })
    check("R-2 cacheDir root holds only the plugin root", context.cacheDir.list()!!.toList() == listOf(MyFileDirectory.SHARE_CACHE_DIR_NAME), "${context.cacheDir.list()!!.toList()}")
    check("R-2 per-share directory sits directly below the root", parents.all { it.parentFile.name == MyFileDirectory.SHARE_CACHE_DIR_NAME && it.parentFile.parentFile == context.cacheDir })
}

private fun testExistingCacheFileIsNeverOverwritten() {
    val context = freshContext()
    val victim = File(context.cacheDir, "photo.jpg").apply { writeText("original") }
    val uri = "content://p.a/1"
    context.register(uri, "photo.jpg", "attacker".toByteArray())
    MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("R-2 an existing cache file with the same name is untouched", victim.readText() == "original")
    val traversal = "content://p.a/2"
    context.register(traversal, "../photo.jpg", "attacker".toByteArray())
    val path = MyFileDirectory.getAbsolutePath(context, Uri.parse(traversal))
    check("R-2 traversal in a display name stays in the share directory", isInsideShareRoot(context, path) && victim.readText() == "original")
}

private fun testOversizedSourceLeavesNothingBehind() {
    val context = freshContext()
    val uri = "content://p.a/big"
    context.register(uri, "big.bin", ByteArray(SOURCE_OVER_CAP_BYTES))
    val failed = try { MyFileDirectory.getAbsolutePath(context, Uri.parse(uri)); false } catch (e: IOException) { true }
    val leftovers = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).list()?.size ?: 0
    check("FSI-90 over-cap source aborts the share", failed)
    check("FSI-90 over-cap source leaves no directory behind", leftovers == 0, "$leftovers entries")
}

private fun testPruning() {
    val context = freshContext()
    val root = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).apply { mkdirs() }
    val staleAge = System.currentTimeMillis() - STALE_AGE_DAYS * MILLIS_PER_DAY
    val staleShare = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs(); File(this, "a.txt").writeText("a"); setLastModified(staleAge) }
    val freshShare = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
    val foreign = File(root, "not-a-uuid").apply { mkdirs(); setLastModified(staleAge) }
    val uri = "content://p.a/1"
    context.register(uri, "n.txt", "n".toByteArray())
    MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("prune: stale UUID share directory removed", !staleShare.exists())
    check("prune: fresh UUID share directory kept", freshShare.exists())
    check("prune: non-UUID entry kept", foreign.exists())

    val first = MyFileDirectory.newThumbnailFile(context.cacheDir)
    val second = MyFileDirectory.newThumbnailFile(context.cacheDir)
    val thumbRoot = File(context.cacheDir, MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME)
    check("thumbnail: separate root, unique UUID-named png", first != second && first.parentFile == thumbRoot && uuidPattern.matches(first.name.removeSuffix(".png")))
    val oldPng = File(thumbRoot, "old.png").apply { writeText("x"); setLastModified(staleAge) }
    val oldOther = File(thumbRoot, "old.txt").apply { writeText("x"); setLastModified(staleAge) }
    val rootPng = File(context.cacheDir, "host-image.png").apply { writeText("x"); setLastModified(staleAge) }
    MyFileDirectory.newThumbnailFile(context.cacheDir)
    check("thumbnail prune: stale png removed", !oldPng.exists())
    check("thumbnail prune: stale non-png kept", oldOther.exists())
    check("thumbnail prune: cacheDir root files untouched", rootPng.exists())
}


private fun shareRoot(context: Context) = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME)
private fun entriesOf(dir: File): List<String> = dir.list()?.toList() ?: emptyList()

private fun failingCopy(name: String, configure: (Context, String) -> Unit, expectIo: Boolean = true) {
    val context = freshContext()
    val uri = "content://p.a/fail"
    context.register(uri, "f.bin", ByteArray(MID_READ_BYTES * 2))
    configure(context, uri)
    val threw = try { MyFileDirectory.getAbsolutePath(context, Uri.parse(uri)); false } catch (e: Exception) { true }
    check("I-1 $name: failure propagates", threw == expectIo)
    check("I-1 $name: no per-share directory remains", entriesOf(shareRoot(context)).isEmpty(), "${entriesOf(shareRoot(context))}")
    check("I-1 $name: nothing in the cache root but the share root", entriesOf(context.cacheDir).all { it == MyFileDirectory.SHARE_CACHE_DIR_NAME })
}

private fun testFailedCopiesLeaveNothingBehind() {
    failingCopy("open throws IOException", { c, _ -> c.contentResolver.openThrows = IOException("boom") })
    failingCopy("open throws SecurityException", { c, _ -> c.contentResolver.openThrows = SecurityException("denied") })
    failingCopy("open throws FileNotFoundException", { c, _ -> c.contentResolver.openThrows = java.io.FileNotFoundException("gone") })
    failingCopy("read fails mid-copy", { c, _ -> c.contentResolver.failReadAfterBytes = MID_READ_BYTES })
    val context = freshContext()
    context.contentResolver.queryThrows = SecurityException("denied")
    val threw = try { MyFileDirectory.getAbsolutePath(context, Uri.parse("content://p.a/q")); false } catch (e: SecurityException) { true }
    check("I-1 query throws: propagates and leaves nothing", threw && entriesOf(context.cacheDir).isEmpty())
}

private fun testMultipleItemsAreAllOrNothing() {
    val context = freshContext()
    val good = "content://p.a/good"
    val bad = "content://p.a/bad"
    context.register(good, "good.txt", "g".toByteArray())
    context.register(bad, "bad.txt", ByteArray(MID_READ_BYTES * 2))
    // The first item copies; the second fails. The first item's directory must go too.
    val copies = MyFileDirectory.getAbsolutePaths(context, listOf(Uri.parse(good)))
    check("I-1 multi: successful batch keeps its copy", copies.size == 1 && File(copies[0]).exists())
    context.contentResolver.failingUris.add(bad)
    val failed = try { MyFileDirectory.getAbsolutePaths(context, listOf(Uri.parse(good), Uri.parse(bad))); false } catch (e: IOException) { true }
    val remaining = entriesOf(shareRoot(context)).size
    check("I-1 multi: failing batch propagates", failed)
    check("I-1 multi: failing batch deletes the copies it made", remaining == 1, "$remaining directories (only the earlier batch may remain)")
    MyFileDirectory.deleteShareCopies(copies)
    check("I-1 multi: deleteShareCopies removes a directory", entriesOf(shareRoot(context)).isEmpty())
    val strayDirectory = File(context.cacheDir, "keep").apply { mkdirs() }
    MyFileDirectory.deleteShareCopies(listOf(File(strayDirectory, "x").path))
    check("I-1 multi: deleteShareCopies ignores paths outside the layout", strayDirectory.exists())
}

private fun testMediaFailuresAreAbsorbed() {
    check("I-1 media: runtime failure becomes null", MyFileDirectory.orNullOnMediaFailure<Long> { throw IllegalStateException("bad video") } == null)
    check("I-1 media: IOException becomes null", MyFileDirectory.orNullOnMediaFailure<String> { throw IOException("bad video") } == null)
    check("I-1 media: success passes through", MyFileDirectory.orNullOnMediaFailure { 42L } == 42L)
    val escaped = try { MyFileDirectory.orNullOnMediaFailure<Long> { throw OutOfMemoryError() }; false } catch (e: OutOfMemoryError) { true }
    check("I-1 media: errors are not absorbed", escaped)
}

private fun testRootsAreRecreated() {
    val context = freshContext()
    val uri = "content://p.a/1"
    context.register(uri, "n.txt", "n".toByteArray())
    MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    MyFileDirectory.newThumbnailFile(context.cacheDir)
    File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).deleteRecursively()
    File(context.cacheDir, MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME).deleteRecursively()
    val path = MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    val thumbnail = MyFileDirectory.newThumbnailFile(context.cacheDir)
    check("roots: share root recreated after a wipe", isInsideShareRoot(context, path) && File(path!!).exists())
    check("roots: thumbnail root recreated and writable after a wipe", thumbnail.parentFile.isDirectory && thumbnail.createNewFile())
}

private fun testRootThatIsAFileOrALink() {
    val context = freshContext()
    val uri = "content://p.a/1"
    context.register(uri, "n.txt", "n".toByteArray())
    File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).writeText("legacy file")
    File(context.cacheDir, MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME).writeText("legacy file")
    val path = MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    val thumbnail = MyFileDirectory.newThumbnailFile(context.cacheDir)
    check("M-1 share root that is a plain file is replaced by a directory", isInsideShareRoot(context, path))
    check("M-1 thumbnail root that is a plain file is replaced by a directory", thumbnail.parentFile.isDirectory)

    val linked = freshContext()
    val outside = Files.createTempDirectory("fsi-outside").toFile().canonicalFile
    Files.createSymbolicLink(File(linked.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).toPath(), outside.toPath())
    Files.createSymbolicLink(File(linked.cacheDir, MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME).toPath(), outside.toPath())
    linked.register(uri, "n.txt", "n".toByteArray())
    val shareFailed = try { MyFileDirectory.getAbsolutePath(linked, Uri.parse(uri)); false } catch (e: IOException) { true }
    val thumbnailFailed = try { MyFileDirectory.newThumbnailFile(linked.cacheDir); false } catch (e: IOException) { true }
    check("M-1 symlinked share root fails closed", shareFailed)
    check("M-1 symlinked thumbnail root fails closed", thumbnailFailed)
    check("M-1 nothing was written through the links", entriesOf(outside).isEmpty(), "${entriesOf(outside)}")
}

private fun testRecursiveDeleteNeverFollowsLinks() {
    val context = freshContext()
    val root = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).apply { mkdirs() }
    val outside = Files.createTempDirectory("fsi-outside").toFile().canonicalFile
    val precious = File(outside, "precious.txt").apply { writeText("keep") }
    val staleShare = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
    Files.createSymbolicLink(File(staleShare, "link").toPath(), outside.toPath())
    staleShare.setLastModified(System.currentTimeMillis() - STALE_AGE_DAYS * MILLIS_PER_DAY)
    MyFileDirectory.pruneStaleEntries(root, requireUuidDirectories = true)
    check("M-2 prune removed the stale directory", !staleShare.exists())
    check("M-2 prune did not follow a link inside it", precious.exists() && precious.readText() == "keep")

    val partial = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
    Files.createSymbolicLink(File(partial, "link").toPath(), outside.toPath())
    MyFileDirectory.deleteWithoutFollowingLinks(partial)
    check("M-2 direct delete removed the tree", !partial.exists())
    check("M-2 direct delete did not follow a link", precious.exists())
    val linkedStale = File(root, java.util.UUID.randomUUID().toString())
    Files.createSymbolicLink(linkedStale.toPath(), outside.toPath())
    MyFileDirectory.pruneStaleEntries(root, requireUuidDirectories = true, nowMillis = System.currentTimeMillis() + 2 * STALE_AGE_DAYS * MILLIS_PER_DAY)
    check("M-3 prune skips a symlink child", Files.isSymbolicLink(linkedStale.toPath()) && precious.exists())
}

private fun testPruneAgeBoundary() {
    val context = freshContext()
    val root = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).apply { mkdirs() }
    val now = System.currentTimeMillis()
    val ttl = MyFileDirectory.CACHE_ENTRY_TTL_MILLIS
    val justUnder = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs(); setLastModified(now - ttl + BOUNDARY_MARGIN_MILLIS) }
    val justOver = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs(); setLastModified(now - ttl - BOUNDARY_MARGIN_MILLIS) }
    MyFileDirectory.pruneStaleEntries(root, requireUuidDirectories = true, nowMillis = now)
    check("M-3 prune keeps an entry just under the TTL", justUnder.exists())
    check("M-3 prune removes an entry just over the TTL", !justOver.exists())
}

private fun testNullStreamRemovesItsDirectory() {
    val context = freshContext()
    val uri = "content://p.a/nostream"
    context.contentResolver.displayNames[uri] = "n.txt"
    val result = MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("M-3 provider without a stream yields null", result == null)
    check("M-3 provider without a stream leaves no directory", entriesOf(shareRoot(context)).isEmpty(), "${entriesOf(shareRoot(context))}")
}

// R-1 / I-2: allowlist of log interpolations.
private val logCallStart = Regex("""Log\.[a-z]\(""")
private val bracedInterpolation = Regex("""\$\{([^}]*)\}""")
private val bareInterpolation = Regex("""\$([A-Za-z_][A-Za-z0-9_]*)""")
private val allowedExpressions = listOf(
    Regex("tag"),
    Regex("intent\\.action"),
    Regex("intent\\.type"),
    Regex("""[A-Za-z0-9_.?]+\.javaClass\.simpleName"""),
    Regex("""[A-Za-z0-9_.?]+(\.size|\.length\(\))( \?: 0)?"""),
)
private val allowedBareNames = setOf("tag")

/** Returns the full text of every `Log.x(...)` call, joined across lines up to the matching parenthesis. */
private fun logCalls(text: String): List<String> {
    val calls = mutableListOf<String>()
    for (start in logCallStart.findAll(text)) {
        var depth = 0
        var inString = false
        var index = start.range.last
        val begin = start.range.first
        while (index < text.length) {
            val ch = text[index]
            if (inString) {
                if (ch == '\\') index++ else if (ch == '"') inString = false
            } else when (ch) {
                '"' -> inString = true
                '(' -> depth++
                ')' -> { depth--; if (depth == 0) break }
            }
            index++
        }
        calls.add(text.substring(begin, minOf(index + 1, text.length)))
    }
    return calls
}

private fun topLevelArgumentCount(call: String): Int {
    var depth = 0
    var inString = false
    var commas = 0
    var index = call.indexOf('(')
    while (index < call.length) {
        val ch = call[index]
        if (inString) {
            if (ch == '\\') index++ else if (ch == '"') inString = false
        } else when (ch) {
            '"' -> inString = true
            '(', '{' -> depth++
            ')', '}' -> depth--
            ',' -> if (depth == 1) commas++
        }
        index++
    }
    return commas + 1
}

/** Returns a description of every disallowed part of every Log call in [text]. */
private fun logViolations(text: String): List<String> {
    val violations = mutableListOf<String>()
    for (call in logCalls(text)) {
        val oneLine = call.replace(Regex("\\s+"), " ")
        if (topLevelArgumentCount(call) > 2) violations.add("more than tag and message: $oneLine")
        for (match in bracedInterpolation.findAll(call)) {
            val expression = match.groupValues[1].trim()
            if (allowedExpressions.none { it.matches(expression) }) violations.add("interpolation \${$expression} in $oneLine")
        }
        val withoutBraced = bracedInterpolation.replace(call, "")
        for (match in bareInterpolation.findAll(withoutBraced)) {
            if (match.groupValues[1] !in allowedBareNames) violations.add("interpolation \$${match.groupValues[1]} in $oneLine")
        }
    }
    return violations
}

private fun testLogAllowlist(scanDirectory: File) {
    check("R-1 scanner flags a multi-line URI interpolation", logViolations("Log.w(TAG,\n  \"Rejected \${uri.scheme}\")").isNotEmpty())
    check("R-1 scanner flags a payload interpolation", logViolations("Log.w(TAG, \"x \$value\")").isNotEmpty())
    check("R-1 scanner flags a throwable argument", logViolations("Log.e(TAG, \"x\", t)").isNotEmpty())
    check("R-1 scanner accepts the allowed forms", logViolations(
        "Log.w(TAG, \"\$tag \${intent.action} \${intent.type} \${e.javaClass.simpleName} \${value?.length() ?: 0} \${list.size}\")").isEmpty())

    val sources = scanDirectory.walkTopDown().filter { it.extension == "kt" }.toList()
    val allCalls = sources.flatMap { logCalls(it.readText()) }
    check("R-1 the scan found Log calls (not vacuous)", allCalls.size >= MIN_EXPECTED_LOG_CALLS, "found ${allCalls.size}")
    val offenders = sources.flatMap { file -> logViolations(file.readText()).map { "${file.name}: $it" } }
    check("R-1 every Log call uses only allowed interpolations", offenders.isEmpty(), offenders.joinToString(" | "))
}

fun main(args: Array<String>) {
    testPrimaryDocumentIdCannotEscape()
    testThirdPartyDocumentProviderNeverReturnsUriPath()
    testNormalContentShareIsCopied()
    testRejectedInputs()
    testEachShareGetsItsOwnDirectory()
    testExistingCacheFileIsNeverOverwritten()
    testOversizedSourceLeavesNothingBehind()
    testPruning()
    testFailedCopiesLeaveNothingBehind()
    testMultipleItemsAreAllOrNothing()
    testMediaFailuresAreAbsorbed()
    testRootsAreRecreated()
    testRootThatIsAFileOrALink()
    testRecursiveDeleteNeverFollowsLinks()
    testPruneAgeBoundary()
    testNullStreamRemovesItsDirectory()
    testLogAllowlist(File(args[0]))
    println(if (failures == 0) "ALL PASS" else "FAILURES: $failures")
    System.exit(failures)
}
