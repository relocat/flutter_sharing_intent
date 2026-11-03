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
    val uri = "content://com.android.externalstorage.documents/document/primary%3A..%2F..%2F..%2Fdata%2Fdata%2Fhost.app%2Fdb"
    context.register(uri, "db", "x".toByteArray())
    val result = MyFileDirectory.getAbsolutePath(context, Uri.parse(uri))
    check("1 primary document id: result is null or inside the share root", result == null || isInsideShareRoot(context, result), "got $result")
    check("1 primary document id: no raw storage path", result?.startsWith("/storage") != true, "got $result")
}

// Test 2: a third-party DocumentsProvider authority never yields uri.path.
private fun testThirdPartyDocumentProviderNeverReturnsUriPath() {
    val context = freshContext()
    val uriText = "content://com.thirdparty.docs/document/..%2F..%2Fdata%2Fdata%2Fhost.app%2Fprefs"
    val uri = Uri.parse(uriText)
    context.register(uriText, "prefs.xml", "x".toByteArray())
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
    check("file:// is rejected", MyFileDirectory.getAbsolutePath(context, Uri.parse("file:///data/data/host.app/x")) == null)
    val noAuthority = "content:///data/data/host.app/x"
    context.register(noAuthority, "x", "x".toByteArray())
    check("content URI without authority yields null", MyFileDirectory.getAbsolutePath(context, Uri.parse(noAuthority)) == null)
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

fun main(args: Array<String>) {
    testPrimaryDocumentIdCannotEscape()
    testThirdPartyDocumentProviderNeverReturnsUriPath()
    testNormalContentShareIsCopied()
    testRejectedInputs()
    testEachShareGetsItsOwnDirectory()
    testExistingCacheFileIsNeverOverwritten()
    testOversizedSourceLeavesNothingBehind()
    testPruning()
    println(if (failures == 0) "ALL PASS" else "FAILURES: $failures")
    System.exit(failures)
}
