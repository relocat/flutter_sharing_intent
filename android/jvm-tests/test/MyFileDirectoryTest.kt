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
private var skipped = 0
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
    context.register(uri, "photo.jpg", "x".toByteArray())
    MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("R-2 an existing cache file with the same name is untouched", victim.readText() == "original")
    val traversal = "content://p.a/2"
    context.register(traversal, "../photo.jpg", "x".toByteArray())
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

private fun canBlockDeletes(directory: File): Boolean {
    directory.setWritable(false, false)
    return !directory.canWrite()
}

// F-3: one failing delete never stops the others, and never hides the first error.
private fun testDeleteContinuesAfterAFailure() {
    val context = freshContext()
    val first = "content://p.a/1"
    val second = "content://p.a/2"
    context.register(first, "a.txt", "x".toByteArray())
    context.register(second, "b.txt", "x".toByteArray())
    val firstPath = MyFileDirectory.getAbsolutePath(context, Uri.parse(first))!!
    val secondPath = MyFileDirectory.getAbsolutePath(context, Uri.parse(second))!!
    val firstDirectory = File(firstPath).parentFile
    if (!canBlockDeletes(firstDirectory)) {
        firstDirectory.setWritable(true, false)
        skipped++
        println("SKIPPED (root) F-3: this account can delete from read-only directories")
        return
    }
    val thrown = try { MyFileDirectory.deleteShareCopies(listOf(firstPath, secondPath)); null } catch (e: IOException) { e }
    firstDirectory.setWritable(true, false)
    check("F-3 the first failure is rethrown after the loop", thrown != null)
    check("F-3 a later copy is still deleted", !File(secondPath).parentFile.exists())
    check("F-3 the failed copy is left for a retry", File(firstPath).exists())

    val tree = File(context.cacheDir, "tree").apply { mkdirs() }
    val blocked = File(tree, "blocked").apply { mkdirs() }
    File(blocked, "f.txt").writeText("x")
    File(tree, "other.txt").writeText("x")
    canBlockDeletes(blocked)
    val treeFailure = try { MyFileDirectory.deleteWithoutFollowingLinks(tree); null } catch (e: IOException) { e }
    blocked.setWritable(true, false)
    check("F-3 recursive delete continued past the failure", !File(tree, "other.txt").exists())
    check("F-3 recursive delete reports the real error, not the parent's", treeFailure?.message?.contains("cannot delete cache entry") == true && treeFailure.suppressed.isEmpty(), "${treeFailure?.message} suppressed=${treeFailure?.suppressed?.size}")

    // L-4: independent failures in different subtrees are ALL recorded.
    val twoTrees = File(context.cacheDir, "two").apply { mkdirs() }
    val blockedA = File(twoTrees, "a").apply { mkdirs(); File(this, "f").writeText("x") }
    val blockedB = File(twoTrees, "b").apply { mkdirs(); File(this, "f").writeText("x") }
    canBlockDeletes(blockedA)
    canBlockDeletes(blockedB)
    val both = try { MyFileDirectory.deleteWithoutFollowingLinks(twoTrees); null } catch (e: IOException) { e }
    blockedA.setWritable(true, false)
    blockedB.setWritable(true, false)
    check("L-4 two failing subtrees give one error plus one suppressed", both != null && both.suppressed.size == 1, "suppressed=${both?.suppressed?.size}")

    // L-3: a failing cleanup never replaces the original failure.
    val result = try {
        MyFileDirectory.withCleanup(cleanup = { throw IOException("cleanup failed") }) { throw IOException("original") }
    } catch (e: IOException) { e }
    check("L-3 the original failure is rethrown", (result as IOException).message == "original")
    check("L-3 the cleanup failure is attached as suppressed", result.suppressed.size == 1 && result.suppressed[0].message == "cleanup failed")
}

// F-4: thumbnails.
private fun testThumbnailWriting() {
    val context = freshContext()
    val thumbnailRoot = File(context.cacheDir, MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME)
    val ok = MyFileDirectory.writeThumbnail(context.cacheDir) { out -> out.write(1); true }
    check("F-4 a successful thumbnail is written", ok != null && File(ok).length() == 1L)
    val failed = MyFileDirectory.writeThumbnail(context.cacheDir) { out -> out.write(1); false }
    check("F-4 compress returning false yields null", failed == null)
    val threw = try { MyFileDirectory.writeThumbnail(context.cacheDir) { out -> out.write(1); throw IOException("boom") }; false } catch (e: IOException) { true }
    check("F-4 compress throwing propagates", threw)
    check("F-4 no partial thumbnail is left", entriesOf(thumbnailRoot) == listOf(File(ok!!).name), "${entriesOf(thumbnailRoot)}")
    val removed = MyFileDirectory.removeOwnedFiles(context.cacheDir, listOf(ok))
    check("F-4 thumbnails created for a failed share are removable", removed == 1 && entriesOf(thumbnailRoot).isEmpty())
}

// A-2: Android cleanup(paths).
private fun testCleanupRemovesOnlyOwnedFiles() {
    val context = freshContext()
    val uri = "content://p.a/1"
    context.register(uri, "a.txt", "x".toByteArray())
    val shareFile = File(MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))!!)
    val thumbnail = MyFileDirectory.newThumbnailFile(context.cacheDir).apply { writeText("x") }
    val legacy = File(context.cacheDir, "photo.jpg").apply { writeText("x") }
    val outside = Files.createTempDirectory("fsi-outside").toFile().canonicalFile
    val foreign = File(outside, "keep.txt").apply { writeText("x") }
    val root = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME)
    val directoryAtFile = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs(); File(this, "sub").mkdirs(); File(this, "sub/inner.txt").writeText("x") }
    val notUuid = File(root, "not-a-uuid").apply { mkdirs(); File(this, "a.txt").writeText("x") }
    val badThumbnail = File(context.cacheDir, "${MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME}/t.png").apply { writeText("x") }
    val linkDirectory = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
    Files.createSymbolicLink(File(linkDirectory, "link.txt").toPath(), foreign.toPath())
    val siblingDirectory = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
    val siblingTarget = File(siblingDirectory, "a.txt").apply { writeText("x") }
    val siblingOther = File(siblingDirectory, "b.txt").apply { writeText("x") }

    val removed = MyFileDirectory.removeOwnedFiles(context.cacheDir, listOf(
        shareFile.path, thumbnail.path, legacy.path, foreign.path,
        File(directoryAtFile, "sub").path, File(notUuid, "a.txt").path, badThumbnail.path,
        File(linkDirectory, "link.txt").path, siblingTarget.path,
        shareFile.parentFile.path + "/../" + shareFile.name, shareFile.parentFile.path + "//" + shareFile.name, "relative/path", "",
    ))
    check("A-2 removes exactly the owned regular files", removed == 3, "removed=$removed")
    check("A-2 owned share file and its emptied directory are gone", !shareFile.exists() && !shareFile.parentFile.exists())
    check("A-2 owned thumbnail is gone", !thumbnail.exists())
    check("A-2 a share directory with another file keeps that file", siblingOther.exists() && siblingDirectory.exists())
    check("A-2 cacheDir root file is untouched", legacy.exists())
    check("A-2 file outside the cache is untouched", foreign.exists())
    check("A-2 a directory at the file position is untouched", File(directoryAtFile, "sub/inner.txt").exists())
    check("A-2 wrong shapes are untouched", File(notUuid, "a.txt").exists() && badThumbnail.exists())
    check("A-2 a symlink at the file position is neither followed nor removed", Files.isSymbolicLink(File(linkDirectory, "link.txt").toPath()) && foreign.exists())
    check("A-2 the plugin roots stay", root.isDirectory)

    val linked = freshContext()
    val target = File(outside, "linked-target").apply { mkdirs() }
    val victimDirectory = File(target, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
    val victim = File(victimDirectory, "a.txt").apply { writeText("x") }
    Files.createSymbolicLink(File(linked.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).toPath(), target.toPath())
    val viaLink = MyFileDirectory.removeOwnedFiles(linked.cacheDir, listOf(File(linked.cacheDir, "${MyFileDirectory.SHARE_CACHE_DIR_NAME}/${victimDirectory.name}/a.txt").path))
    check("A-2 a path through a symlinked root is refused", viaLink == 0 && victim.exists())
}

// L-2: a close() that fails must not leave a partial thumbnail that counts as written.
private fun testThumbnailCloseFailure() {
    val context = freshContext()
    val closeFails = { file: File ->
        object : java.io.FilterOutputStream(java.io.FileOutputStream(file)) {
            override fun write(b: ByteArray, off: Int, len: Int) { out.write(b, off, len) }
            override fun close() { out.close(); throw IOException("close failed") }
        }
    }
    val threw = try { MyFileDirectory.writeThumbnail(context.cacheDir, closeFails) { out -> out.write(1); true }; false } catch (e: IOException) { true }
    val thumbnailRoot = File(context.cacheDir, MyFileDirectory.THUMBNAIL_CACHE_DIR_NAME)
    check("L-2 a failing close propagates", threw)
    check("L-2 a failing close leaves no thumbnail", entriesOf(thumbnailRoot).isEmpty(), "${entriesOf(thumbnailRoot)}")
}

// L-1: the thumbnail is recorded as soon as it exists, even if the next step dies with an Error.
private fun testThumbnailIsRecordedBeforeTheDurationStep() {
    val context = freshContext()
    val created = mutableListOf<String>()
    val died = try {
        MyFileDirectory.extractMediaDetails(
            created,
            thumbnail = { MyFileDirectory.writeThumbnail(context.cacheDir) { out -> out.write(1); true } },
            duration = { throw OutOfMemoryError() },
        )
        false
    } catch (e: OutOfMemoryError) { true }
    check("L-1 the Error propagates", died)
    check("L-1 the thumbnail was already recorded", created.size == 1 && File(created[0]).exists())
    check("L-1 the recorded thumbnail can be deleted", MyFileDirectory.removeOwnedFiles(context.cacheDir, created) == 1 && !File(created[0]).exists())
    val details = MyFileDirectory.extractMediaDetails(mutableListOf(), thumbnail = { throw IllegalStateException("bad") }, duration = { 5L })
    check("L-1 a failing thumbnail still yields the duration", details.thumbnail == null && details.duration == 5L)
}

// L-8: a symlinked per-share directory is refused by cleanup.
private fun testCleanupRefusesSymlinkedShareDirectory() {
    val context = freshContext()
    val outside = Files.createTempDirectory("fsi-outside").toFile().canonicalFile
    val victim = File(outside, "a.txt").apply { writeText("x") }
    val root = File(context.cacheDir, MyFileDirectory.SHARE_CACHE_DIR_NAME).apply { mkdirs() }
    val linkName = java.util.UUID.randomUUID().toString()
    Files.createSymbolicLink(File(root, linkName).toPath(), outside.toPath())
    val removed = MyFileDirectory.removeOwnedFiles(context.cacheDir, listOf(File(root, "$linkName/a.txt").path))
    check("L-8 a symlinked per-share directory is refused", removed == 0 && victim.exists())
}

// F-1: the plugin must not use java.nio.file (API 26) or File.toPath().
private val api26Pattern = Regex("""java\.nio\.file|\.toPath\(|\bFiles\.""")

private fun testNoApi26Calls(scanDirectory: File) {
    val offenders = scanDirectory.walkTopDown().filter { it.extension == "kt" }.flatMap { file ->
        file.readLines().withIndex().filter { (_, line) -> api26Pattern.containsMatchIn(line) }.map { "${file.name}:${it.index + 1}" }
    }.toList()
    check("F-1 no java.nio.file or File.toPath in the plugin sources", offenders.isEmpty(), offenders.joinToString(" | "))
}

// F-2: allowlist of log calls.
private val bracedInterpolation = Regex("""\$\{([^}]*)\}""")
private val bareInterpolation = Regex("""\$([A-Za-z_][A-Za-z0-9_]*)""")
private val stringLiteral = Regex(""""(?:[^"\\]|\\.)*"""")
private val allowedExpressions = listOf(
    Regex("tag"),
    Regex("""[A-Za-z0-9_.?]+\.javaClass\.simpleName"""),
    Regex("""[A-Za-z0-9_.?]+(\.size|\.length\(\))( \?: 0)?"""),
)
private val allowedBareNames = setOf("tag")
private const val LOG_TAG_ARGUMENT = "TAG"
private const val LOG_ARGUMENT_COUNT = 2

private fun logCallRanges(text: String): List<IntRange> {
    val calls = mutableListOf<IntRange>()
    for (start in Regex("""Log\.\w+\(""").findAll(text)) {
        var depth = 0
        var inString = false
        var index = start.range.last
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
        calls.add(start.range.first..minOf(index, text.length - 1))
    }
    return calls
}

/** Splits the arguments of one call at top-level commas, string- and bracket-aware. */
private fun topLevelArguments(call: String): List<String> {
    val arguments = mutableListOf<String>()
    var depth = 0
    var inString = false
    var begin = call.indexOf('(') + 1
    var index = begin
    while (index < call.length) {
        val ch = call[index]
        if (inString) {
            if (ch == '\\') index++ else if (ch == '"') inString = false
        } else when (ch) {
            '"' -> inString = true
            '(', '{', '[' -> depth++
            ')', '}', ']' -> { if (depth == 0) { arguments.add(call.substring(begin, index).trim()); return arguments }; depth-- }
            ',' -> if (depth == 0) { arguments.add(call.substring(begin, index).trim()); begin = index + 1 }
        }
        index++
    }
    arguments.add(call.substring(begin).trim())
    return arguments
}

/** Returns a description of every disallowed part of every Log call in [text]. */
private fun logViolations(text: String): List<String> {
    val violations = mutableListOf<String>()
    for (range in logCallRanges(text)) {
        val call = text.substring(range)
        val shown = call.replace(Regex("\\s+"), " ")
        val arguments = topLevelArguments(call)
        if (arguments.size != LOG_ARGUMENT_COUNT) { violations.add("not exactly tag and message: $shown"); continue }
        val tag = arguments[0]
        if (tag != LOG_TAG_ARGUMENT && !stringLiteral.matches(tag)) violations.add("tag is neither TAG nor a literal: $shown")
        val message = arguments[1]
        if (!stringLiteral.matches(message)) { violations.add("message is not a single string literal: $shown"); continue }
        for (match in bracedInterpolation.findAll(message)) {
            val expression = match.groupValues[1].trim()
            if (allowedExpressions.none { it.matches(expression) }) violations.add("interpolation \${$expression} in $shown")
        }
        for (match in bareInterpolation.findAll(bracedInterpolation.replace(message, ""))) {
            if (match.groupValues[1] !in allowedBareNames) violations.add("interpolation \$${match.groupValues[1]} in $shown")
        }
    }
    return violations
}

private val perFileLogCallFloor = mapOf("FlutterSharingIntentPlugin.kt" to 6, "MyFileDirectory.kt" to 5)

private fun testLogAllowlist(scanDirectory: File) {
    fun flagged(source: String) = logViolations(source).isNotEmpty()
    check("F-2 scanner flags a multi-line URI interpolation", flagged("Log.w(TAG,\n  \"Rejected \${uri.scheme}\")"))
    check("F-2 scanner flags a payload interpolation", flagged("Log.w(TAG, \"x \$value\")"))
    check("F-2 scanner flags string concatenation", flagged("Log.w(TAG, \"a\" + b)"))
    check("F-2 scanner flags a bare expression message", flagged("Log.w(TAG, message)"))
    check("F-2 scanner flags the throwable two-argument form", flagged("Log.w(TAG, e)"))
    check("F-2 scanner flags a third argument", flagged("Log.e(TAG, \"x\", t)"))
    check("F-2 scanner flags wtf with content", flagged("Log.wtf(TAG, \"x \$value\")"))
    check("F-2 scanner flags println", flagged("Log.println(Log.WARN, TAG, \"x\")"))
    check("F-2 scanner flags a computed tag", flagged("Log.w(tagFor(x), \"x\")"))
    check("F-2 scanner flags the intent type", flagged("Log.w(TAG, \"t \${intent.type}\")"))
    check("F-2 scanner accepts the allowed forms", !flagged(
        "Log.w(TAG, \"\$tag \${e.javaClass.simpleName} \${value?.length() ?: 0} \${list.size}\")\nLog.wtf(\"Tag\", \"ok\")"))

    val sources = scanDirectory.walkTopDown().filter { it.extension == "kt" }.toList()
    for ((name, floor) in perFileLogCallFloor) {
        val file = sources.firstOrNull { it.name == name }
        val count = file?.let { logCallRanges(it.readText()).size } ?: 0
        check("F-2 the scan found the Log calls in $name (not vacuous)", count >= floor, "found $count, floor $floor")
    }
    val offenders = sources.flatMap { file -> logViolations(file.readText()).map { "${file.name}: $it" } }
    check("F-2 every Log call is two literals with allowed interpolations", offenders.isEmpty(), offenders.joinToString(" | "))
}

private fun guarded(name: String, body: () -> Unit) {
    try {
        body()
    } catch (e: Throwable) {
        check("$name completed without an uncaught ${e.javaClass.simpleName}", false, e.message ?: "")
    }
}

fun main(args: Array<String>) {
    val scan = File(args[0])
    guarded("1") { testPrimaryDocumentIdCannotEscape() }
    guarded("2") { testThirdPartyDocumentProviderNeverReturnsUriPath() }
    guarded("3") { testNormalContentShareIsCopied() }
    guarded("rejected") { testRejectedInputs() }
    guarded("R-2") { testEachShareGetsItsOwnDirectory() }
    guarded("overwrite") { testExistingCacheFileIsNeverOverwritten() }
    guarded("cap") { testOversizedSourceLeavesNothingBehind() }
    guarded("prune") { testPruning() }
    guarded("I-1") { testFailedCopiesLeaveNothingBehind() }
    guarded("multi") { testMultipleItemsAreAllOrNothing() }
    guarded("media") { testMediaFailuresAreAbsorbed() }
    guarded("roots") { testRootsAreRecreated() }
    guarded("M-1") { testRootThatIsAFileOrALink() }
    guarded("M-2") { testRecursiveDeleteNeverFollowsLinks() }
    guarded("ttl") { testPruneAgeBoundary() }
    guarded("M-3") { testNullStreamRemovesItsDirectory() }
    guarded("F-3") { testDeleteContinuesAfterAFailure() }
    guarded("F-4") { testThumbnailWriting() }
    guarded("A-2") { testCleanupRemovesOnlyOwnedFiles() }
    guarded("L-2") { testThumbnailCloseFailure() }
    guarded("L-1") { testThumbnailIsRecordedBeforeTheDurationStep() }
    guarded("L-8") { testCleanupRefusesSymlinkedShareDirectory() }
    guarded("F-1") { testNoApi26Calls(scan) }
    guarded("F-2") { testLogAllowlist(scan) }
    println(when {
        failures > 0 -> "FAILURES: $failures"
        skipped > 0 -> "ALL PASS WITH SKIPS (root): $skipped"
        else -> "ALL PASS"
    })
    System.exit(failures)
}
