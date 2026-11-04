#!/usr/bin/env python3
"""Generate the Swift logic package sources from the plugin's Swift files.

Usage: extract.py <repo_root> <out_sources_dir> <variant>

The function bodies are copied byte-for-byte from ios/Classes; the script prints
the source line range and the sha256 of each copied block, and each generated
file holds the block between BEGIN/END markers so the copy can be re-hashed.

variant "new"     : the shipped functions.
variant "control" : negative control. isRegularFile is replaced by a stub that
                    accepts everything (the behaviour before FSI-103).
variant "nowiring": negative control. The isRegularFile guard is deleted from
                    removeOwnedFiles (the wiring), so the wiring tests must fail.
variant "noreal"  : negative control. The real-directory guard is deleted, so a
                    symlinked plugin root would redirect deletes.
variant "noleaf"  : negative control. Any thumbnail leaf name is accepted.
variant "noprotect": negative control. The protection option is removed from the
                    staged writes before the source pins are computed.
variant "nocancel": negative control. The cancel cleanup call is removed before
                    the source pins are computed.
variant "weakhost": negative control. The bundle id is encoded with .urlQueryAllowed.
variant "nostagedcleanup": negative control. removeStagedItems does nothing.
variant "rawstrip": negative control. file:// identifiers are converted by
                    textual stripping (no percent-decoding).
variant "noscope" : negative control. The ownership guard is deleted from
                    removeOwnedFiles, so files outside the plugin layout would
                    be removed and the scope tests must fail.
"""
import hashlib, os, re, sys

root, out, variant = sys.argv[1:4]
plugin = "ios/Classes/SwiftFlutterSharingIntentPlugin.swift"
controller = "ios/Classes/FSIShareViewController.swift"


def block(path, start_prefix):
    lines = open(os.path.join(root, path), encoding="utf-8").read().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith(start_prefix))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return start + 1, end + 1, "\n".join(lines[start:end + 1]) + "\n"


def line(path, prefix):
    text = open(os.path.join(root, path), encoding="utf-8").read().split("\n")
    return next(l for l in text if l.startswith(prefix))


def report(name, path, first, last, text):
    print(f"{name}: {path} lines {first}-{last} sha256={hashlib.sha256(text.encode()).hexdigest()}")


os.makedirs(out, exist_ok=True)

a, b, guard = block(plugin, "    static func isStrictlyInsideContainer(")
report("isStrictlyInsideContainer", plugin, a, b, guard)
a, b, regular = block(plugin, "    static func isRegularFile(")
report("isRegularFile", plugin, a, b, regular)
a, b, owned = block(plugin, "    static func isPluginOwnedPath(")
report("isPluginOwnedPath", plugin, a, b, owned)
a, b, relative = block(plugin, "    static func relativeComponents(")
report("relativeComponents", plugin, a, b, relative)
a, b, emptydir = block(plugin, "    static func removeEmptyShareDirectory(")
report("removeEmptyShareDirectory", plugin, a, b, emptydir)
a, b, leaf = block(plugin, "    static func isThumbnailLeaf(")
report("isThumbnailLeaf", plugin, a, b, leaf)
a, b, realdirs = block(plugin, "    static func hasRealOwnedDirectories(")
report("hasRealOwnedDirectories", plugin, a, b, realdirs)
a, b, filepath = block(plugin, "    static func filePath(fromFileIdentifier")
report("filePath", plugin, a, b, filepath)
a, b, remover = block(plugin, "    static func removeOwnedFiles(")
report("removeOwnedFiles", plugin, a, b, remover)
constants = "".join(line(plugin, prefix) + "\n" for prefix in ("    static let kShareRootName", "    static let kThumbnailRootName"))

# Wiring pin: the plugin's cleanupFiles must delegate to the extracted function.
assert "Self.removeOwnedFiles(paths: paths, containerURL: groupUrl)" in open(os.path.join(root, plugin), encoding="utf-8").read(), \
    "cleanupFiles no longer calls removeOwnedFiles"

if variant == "control":
    regular = "    static func isRegularFile(atPath path: String) -> Bool {\n        return true\n    }\n"
elif variant == "nowiring":
    # Delete the isRegularFile guard from removeOwnedFiles.
    stripped = re.sub(r"            guard Self\.isRegularFile\(atPath: standardized\) else \{\n.*?\n            \}\n", "", remover, count=1, flags=re.S)
    assert stripped != remover, "isRegularFile guard not found"
    remover = stripped
elif variant == "noreal":
    # Delete the real-directory guard (symlinked plugin roots) from removeOwnedFiles.
    stripped = re.sub(r"            guard Self\.hasRealOwnedDirectories\(path: standardized, containerURL: containerURL\) else \{\n.*?\n            \}\n", "", remover, count=1, flags=re.S)
    assert stripped != remover, "real-directory guard not found"
    remover = stripped
elif variant == "noleaf":
    # Accept any thumbnail leaf name instead of <UUID>.jpg.
    leaf = "    static func isThumbnailLeaf(_ name: String) -> Bool {\n        return true\n    }\n"
elif variant == "rawstrip":
    # Old behaviour: strip the scheme textually instead of decoding the URL.
    stripped = filepath.replace('URL(string: identifier)?.path', 'identifier.replacingOccurrences(of: "file://", with: "")')
    assert stripped != filepath, "URL(string:) conversion not found"
    filepath = stripped
elif variant == "noscope":
    # Delete the ownership guard from removeOwnedFiles.
    stripped = re.sub(r"            guard Self\.isPluginOwnedPath\(path: p, containerURL: containerURL\) else \{\n.*?\n            \}\n", "", remover, count=1, flags=re.S)
    assert stripped != remover, "ownership guard not found"
    remover = stripped
with open(os.path.join(out, "ContainerGuard.swift"), "w") as f:
    f.write("import Foundation\n\npublic enum ContainerGuard {\n" + constants + "// BEGIN VERBATIM\n"
            + guard + regular + leaf + realdirs + owned + relative + emptydir + filepath + "    @discardableResult\n" + remover + "// END VERBATIM\n}\n")

# Share-extension helpers (static functions of the controller class).
a, b, schemehost = block(controller, "    static func schemeSafeHost(")
report("schemeSafeHost", controller, a, b, schemehost)
a, b, removestaged = block(controller, "    static func removeStagedItems(")
report("removeStagedItems", controller, a, b, removestaged)
if variant == "weakhost":
    # Old behaviour: .urlQueryAllowed leaves ':' and '/' unencoded.
    stripped = schemehost.replace("withAllowedCharacters: allowed)", "withAllowedCharacters: .urlQueryAllowed)")
    assert stripped != schemehost, "charset use not found"
    schemehost = stripped
elif variant == "nostagedcleanup":
    removestaged = "    static func removeStagedItems(_ urls: [URL]) {\n    }\n"
with open(os.path.join(out, "ExtensionLogic.swift"), "w") as f:
    f.write("import Foundation\n\npublic enum ExtensionLogic {\n// BEGIN VERBATIM\n" + schemehost + removestaged + "// END VERBATIM\n}\n")


def func_text(text, start_prefix):
    lines = text.split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith(start_prefix))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return "\n".join(lines[start:end + 1])


def code_lines(text):
    return [l for l in text.split("\n") if not l.strip().startswith("//")]


# Source pins: facts about the controller that unit tests cannot reach because
# it needs UIKit. Each is computed from the shipped source; the controls feed a
# mutated copy of the source through the same scan.
source = open(os.path.join(root, controller), encoding="utf-8").read()
if variant == "noprotect":
    mutated = source.replace(".completeFileProtection", ".atomic")
    assert mutated != source, "protection option not found"
    source = mutated
elif variant == "nocancel":
    block_text = func_text(source, "    open override func didSelectCancel(")
    mutated = source.replace(block_text, block_text.replace("cleanupStagedFiles()", "// removed"))
    assert mutated != source, "cancel cleanup not found"
    source = mutated

code = "\n".join(code_lines(source))
writes = [l for l in code_lines(source) if ".write(to:" in l]
copy_file = func_text(source, "    func copyFile(")
cancel = func_text(source, "    open override func didSelectCancel(")
dismiss = func_text(source, "    private func dismissWithError(")
destination = func_text(source, "    func newShareDestination(")
thumbnail = func_text(source, "    private func getSharedMediaFile(")
redirect = func_text(source, "    private func redirectToHostApp(")
logger = func_text(source, "    private func log(")
pins = {
    "everyDataWriteIsProtected": len(writes) >= 3 and all("completeFileProtection" in l for l in writes),
    "copiedFilesAreProtected": "copyItem" in copy_file and "protect(dstURL)" in copy_file
        and copy_file.index("copyItem") < copy_file.index("protect(dstURL)"),
    "cancelCleansBeforeSuper": "cleanupStagedFiles()" in cancel and "super.didSelectCancel()" in cancel
        and cancel.index("cleanupStagedFiles()") < cancel.index("super.didSelectCancel()"),
    "errorPathCleans": "cleanupStagedFiles()" in dismiss,
    "directoriesAreTracked": "stagedURLs.append(directory)" in destination,
    "thumbnailsAreTracked": "stagedURLs.append(thumbnailPath)" in thumbnail,
    "toStringIsPrivateAndDebugOnly": "#if DEBUG\n    private func toString()" in source,
    "redirectFailsClosed": "schemeSafeHost(hostAppBundleIdentifier)" in redirect and "completeAndExit(); return" in redirect
        and "\\(hostAppBundleIdentifier)" not in redirect,
    "loggingIsCompiledOutOfReleaseBuilds": "#if DEBUG" in logger,
}
for name, value in pins.items():
    print(f"pin {name} = {value}")
with open(os.path.join(out, "SourcePins.swift"), "w") as f:
    f.write("public enum SourcePins {\n" + "".join(f"    static let {n} = {'true' if v else 'false'}\n" for n, v in pins.items()) + "}\n")

a, b, sanitizer = block(controller, "    private func sanitizedComponent(")
report("sanitizedComponent", controller, a, b, sanitizer)
with open(os.path.join(out, "Sanitizer.swift"), "w") as f:
    f.write("import Foundation\n\nstruct Sanitizer {\n// BEGIN VERBATIM\n" + sanitizer + "// END VERBATIM\n}\n\n"
            "extension Sanitizer {\n    /// Test entry point: `private` members are visible to extensions in the same file.\n"
            "    func sanitize(_ raw: String) -> String { sanitizedComponent(raw) }\n}\n")
