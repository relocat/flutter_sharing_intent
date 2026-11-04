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
Source-pin controls (a mutated copy of the controller feeds the pin scan):
  noprotect, nocancel, noabortcheck, nowrap, noabortorder, nodirprotect, nonreg,
  softprotect, noroot, latedefaults, multiwrite, nouiqueue, unsafeaccess, noemptyclean,
  nofinish, nodrop, noskipfinished, noselfclean, noclearmedia, postalwaysvalid,
  unlockedflag, syncabort, doublecomplete, nopostcheck, nodefaultsguard, noprecondition.
Helper controls: rootany (any error counts as a missing root), destok (the post-copy
  check accepts everything), followlinks (removeStagedItems follows links), rootok and copyok
  (the guards accept everything).
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
a, b, usableroot = block(controller, "    static func isUsableRoot(")
report("isUsableRoot", controller, a, b, usableroot)
a, b, copyable = block(controller, "    static func isCopyableRegularFile(")
report("isCopyableRegularFile", controller, a, b, copyable)
a, b, ondisk = block(controller, "    static func isRegularFileOnDisk(")
report("isRegularFileOnDisk", controller, a, b, ondisk)
if variant == "weakhost":
    # Old behaviour: .urlQueryAllowed leaves ':' and '/' unencoded.
    stripped = schemehost.replace("withAllowedCharacters: allowed)", "withAllowedCharacters: .urlQueryAllowed)")
    assert stripped != schemehost, "charset use not found"
    schemehost = stripped
elif variant == "nostagedcleanup":
    removestaged = "    static func removeStagedItems(_ urls: [URL]) {\n    }\n"
elif variant == "followlinks":
    # Resolve links before deleting: a link inside a staged directory would
    # take its target's content with it.
    removestaged = (
        "    static func removeStagedItems(_ urls: [URL]) {\n"
        "        for url in urls {\n"
        "            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []\n"
        "            for child in children {\n"
        "                let target = child.resolvingSymlinksInPath()\n"
        "                if (try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)) != nil {\n"
        "                    for inner in (try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: inner) }\n"
        "                }\n"
        "            }\n"
        "            try? FileManager.default.removeItem(at: url)\n"
        "        }\n"
        "    }\n")
elif variant == "rootok":
    usableroot = "    static func isUsableRoot(_ url: URL) -> Bool {\n        return true\n    }\n"
elif variant == "rootany":
    stripped = usableroot.replace("return isCocoaMissing || isPosixMissing", "return true")
    assert stripped != usableroot, "missing-file check not found"
    usableroot = stripped
elif variant == "destok":
    ondisk = "    static func isRegularFileOnDisk(_ url: URL) -> Bool {\n        return true\n    }\n"
elif variant == "copyok":
    copyable = "    static func isCopyableRegularFile(_ url: URL) -> Bool {\n        return true\n    }\n"
with open(os.path.join(out, "ExtensionLogic.swift"), "w") as f:
    f.write("import Foundation\n\npublic enum ExtensionLogic {\n// BEGIN VERBATIM\n" + schemehost + removestaged + usableroot + copyable + ondisk + "// END VERBATIM\n}\n")


def func_text(text, start_prefix):
    lines = text.split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith(start_prefix))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return "\n".join(lines[start:end + 1])


def ordered(text, *parts):
    """True if every part occurs in text and the first occurrences are in the given order."""
    if not all(part in text for part in parts):
        return False
    positions = [text.index(part) for part in parts]
    return positions == sorted(positions) and len(set(positions)) == len(positions)


def code_lines(text):
    return [l for l in text.split("\n") if not l.strip().startswith("//")]


def calls(text, api):
    """Return the full text of every `api(...)` call, across lines, with balanced parentheses."""
    found = []
    for m in re.finditer(re.escape(api) + r"\(", text):
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        found.append(text[m.start():i + 1])
    return found


# Source pins: facts about the controller that unit tests cannot reach because
# it needs UIKit. Each is computed from the shipped source; the controls feed a
# mutated copy of the source through the same scan.
source = open(os.path.join(root, controller), encoding="utf-8").read()
source_mutations = {
    "noprotect": [(".completeFileProtection", ".atomic")],
    "nocancel": [("        abortAndCleanup()\n        super.didSelectCancel()", "        super.didSelectCancel()")],
    "noabortcheck": [("            if self.isAbortedNow {\n                self.cleanupStagedFiles()\n                return", "            if false {\n                self.cleanupStagedFiles()\n                return")],
    "nowrap": [("self.stageOnStateQueue { self.handleImageItem(data: data, index: index, total: attachments.count) }",
                "self.handleImageItem(data: data, index: index, total: attachments.count)")],
    "noabortorder": [("        let isFirstAbort = markAborted()\n", "        var isFirstAbort = true\n"),
                     ("        _ = done.wait(timeout: .now() + Self.kCancelCleanupWaitSeconds)\n        return isFirstAbort",
                      "        _ = done.wait(timeout: .now() + Self.kCancelCleanupWaitSeconds)\n        isFirstAbort = markAborted()\n        return isFirstAbort")],
    "nodirprotect": [("                attributes: [.protectionKey: FileProtectionType.complete])\n        } catch {\n            log(\"newShareDestination error",
                      "                attributes: nil)\n        } catch {\n            log(\"newShareDestination error")],
    "nonreg": [("guard Self.isCopyableRegularFile(srcURL) else {", "guard true else {")],
    "softprotect": [("try protect(dstURL)", "try? protect(dstURL)")],
    "noroot": [("guard Self.isUsableRoot(root) else {", "guard true else {")],
    "latedefaults": [("        guard let url = redirectURL() else {", "        let early = UserDefaults(suiteName: appGroupId)\n        guard let url = redirectURL() else {")],
    "multiwrite": [("try d.write(to: dst, options: .completeFileProtection)", "try d.write(\n                    to: dst,\n                    options: [])")],
    "unsafeaccess": [("        abortAndCleanup()\n        super.didSelectCancel()", "        stagedURLs.removeAll()\n        abortAndCleanup()\n        super.didSelectCancel()")],
    "noemptyclean": [("                self.log(\"No shared media → stopping.\")\n                self.cleanupStagedFiles()", "                self.log(\"No shared media → stopping.\")")],
    "nofinish": [("            isFinished = true\n            guard !isAbortedNow", "            guard !isAbortedNow")],
    "nodrop": [("            guard !isAbortedNow else { return .drop }\n", "")],
    "noskipfinished": [("if isAbortedNow || isFinished { return }", "if isAbortedNow { return }")],
    "noselfclean": [("            if isAbortedNow {\n                Self.removeStagedItems(Array(", "            if false {\n                Self.removeStagedItems(Array(")],
    "noclearmedia": [("            self.sharedMedia.removeAll()\n", "")],
    "postalwaysvalid": [("        return hasSettledLoads", "        return true")],
    "unlockedflag": [("        abortAndCleanup()\n        super.didSelectCancel()", "        abortedFlag = true\n        abortAndCleanup()\n        super.didSelectCancel()")],
    "syncabort": [("        stateQueue.async {\n            Self.removeStagedItems(self.stagedURLs)", "        stateQueue.sync {\n            Self.removeStagedItems(self.stagedURLs)")],
    "doublecomplete": [("            self.completeRequestOnce()\n        }\n    }", "            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)\n        }\n    }")],
    "nopostcheck": [("guard Self.isRegularFileOnDisk(dstURL) else {", "guard true else {")],
    "nodefaultsguard": [("        guard let ud = UserDefaults(suiteName: appGroupId) else {\n            cleanupStagedFiles()\n            completeAndExit()\n            return\n        }\n", "        let ud = UserDefaults(suiteName: appGroupId)!\n")],
    "noprecondition": [("    func newShareDestination(named name: String) -> URL? {\n        dispatchPrecondition(condition: .onQueue(stateQueue))\n", "    func newShareDestination(named name: String) -> URL? {\n")],
    "nouiqueue": [("        DispatchQueue.main.async {\n            let alert", "        do {\n            let alert")],
}
if variant in source_mutations:
    mutated = source
    for old, new in source_mutations[variant]:
        assert old in mutated, f"mutation target not found for {variant}: {old[:50]!r}"
        mutated = mutated.replace(old, new, 1)
    source = mutated

copy_file = func_text(source, "    func copyFile(")
cancel = func_text(source, "    open override func didSelectCancel(")
dismiss = func_text(source, "    private func dismissWithError(")
abort = func_text(source, "    private func abortAndCleanup(")
destination = func_text(source, "    func newShareDestination(")
thumbnail = func_text(source, "    private func getSharedMediaFile(")
thumb_path = func_text(source, "    private func newThumbnailPath(")
save = func_text(source, "    private func saveAndRedirect(")
redirect_url = func_text(source, "    private func redirectURL(")
logger = func_text(source, "    private func log(")
process = source[source.index("    private func processAttachments("):source.index("    /// Runs one load handler on the state queue.")]
notify = process[process.index("group.notify"):]
body = "\n".join(code_lines(source))

# Everything that touches the shared lists must run on the state queue: either
# in a load handler (always entered through stageOnStateQueue) or in a function
# that wraps the access in stateQueue.sync / stateQueue.async.
queue_safe_functions = {
    "handleTextItem", "handleUrlItem", "handleImageItem", "handleVideoItem", "handleFileItem",
    "writeTempImage", "newShareDestination", "getSharedMediaFile",
    "stageOnStateQueue", "abortAndCleanup", "cleanupStagedFiles", "didSelectPost", "decideDelivery",
}
lock_only_functions = {"isAbortedNow", "markAborted", "completeRequestOnce"}


def accesses(names, allowed):
    pattern = re.compile(r"\b(" + "|".join(names) + r")\b")
    current_function = None
    found = []
    for line in source.split("\n"):
        m = re.match(r"\s*(?:@\w+\s+)?(?:private |open |static |override |public )*func (\w+)", line)
        if m:
            current_function = m.group(1)
        m = re.match(r"\s*(?:private |public )?var (\w+): \w+ \{\s*$", line)
        if m:
            current_function = m.group(1)
        stripped_line = line.strip()
        if stripped_line.startswith("//") or not pattern.search(line):
            continue
        if re.match(r"\s*private (?:var|let) ", line) or "/// " in line:
            continue
        # computed property bodies of isAbortedNow
        if current_function not in allowed and "stateQueue" not in line:
            found.append((current_function, stripped_line))
    return found


unsafe_access = accesses(["sharedMedia", "stagedURLs", "isFinished"], queue_safe_functions)
unlocked_flags = accesses(["abortedFlag", "completedFlag"], lock_only_functions | {"isAbortedNow"})

handler_calls = [l for l in code_lines(source) if re.search(r"self\.handle\w+Item\(", l)]
writes = calls(body, ".write")
decide = func_text(source, "    private func decideDelivery(")
stage = func_text(source, "    private func stageOnStateQueue(")
valid = func_text(source, "    open override func isContentValid(")
pins = {
    "everyDataWriteIsProtected": len(writes) >= 3 and all("completeFileProtection" in w for w in writes)
        and not re.search(r"\bcreateFile\(", body) and not re.search(r"\bmoveItem\(", body)
        and len(calls(body, "copyItem")) == 1,
    "copiedFilesAreProtected": "copyItem" in copy_file and "try protect(dstURL)" in copy_file
        and ordered(copy_file, "copyItem", "try protect(dstURL)"),
    "protectFailsClosed": "private func protect(_ url: URL) throws" in source and "try? protect" not in source
        and ordered(copy_file, "do {", "try protect(dstURL)", "catch"),
    "copyRejectsNonRegularSources": "guard Self.isCopyableRegularFile(srcURL)" in copy_file
        and ordered(copy_file, "isCopyableRegularFile", "copyItem"),
    "copyVerifiesTheCreatedFile": "guard Self.isRegularFileOnDisk(dstURL)" in copy_file
        and ordered(copy_file, "copyItem", "isRegularFileOnDisk", "try protect(dstURL)"),
    "directoriesAreCreatedProtected": all("protectionKey" in c for c in calls(destination + thumb_path, "createDirectory"))
        and len(calls(destination + thumb_path, "createDirectory")) == 2,
    "rootsAreCheckedBeforeStaging": "isUsableRoot(root)" in destination and "isUsableRoot(directory)" in thumb_path,
    "stagingRunsOnTheStateQueue": "dispatchPrecondition(condition: .onQueue(stateQueue))" in destination
        and "dispatchPrecondition(condition: .onQueue(stateQueue))" in thumbnail,
    "cancelAbortsBeforeSuper": "abortAndCleanup()" in cancel and "super.didSelectCancel()" in cancel
        and ordered(cancel, "abortAndCleanup()", "super.didSelectCancel()"),
    "errorPathAborts": "abortAndCleanup()" in dismiss,
    "errorUiRunsOnMain": "DispatchQueue.main.async" in dismiss and ordered(dismiss, "DispatchQueue.main.async", "present("),
    "abortFlagIsSetBeforeCleanup": "markAborted()" in abort and "stateQueue.async" in abort
        and ordered(abort, "markAborted()", "stateQueue.async"),
    "cancelDoesNotWaitOnTheStateQueue": "stateQueue.sync" not in abort and "stateQueue.async" in abort
        and "DispatchSemaphore" in abort and "kCancelCleanupWaitSeconds" in abort,
    "abortClearsSharedMedia": "sharedMedia.removeAll()" in abort,
    "abortFlagsAreLockProtected": not unlocked_flags,
    "notifyDropsAnAbortedShare": "isAbortedNow" in notify and "isAbortedNow" in notify.split("saveAndRedirect()")[0]
        and "return" in notify.split("saveAndRedirect()")[0],
    "handlersRunOnTheStateQueue": len(handler_calls) >= 7 and all("stageOnStateQueue" in l for l in handler_calls),
    "handlersSkipFinishedAndAbortedShares": "isAbortedNow || isFinished" in stage,
    "abortedHandlersRemoveWhatTheyStaged": "handler()" in stage and "removeStagedItems" in stage
        and ordered(stage, "handler()", "removeStagedItems") and stage.rindex("isAbortedNow") > stage.index("handler()"),
    "sharedStateIsOnlyAccessedOnTheQueue": not unsafe_access,
    "deliveryIsOneAtomicDecision": "stateQueue.sync" in decide and "isFinished = true" in decide
        and ordered(decide, "isFinished", "isAbortedNow") and "return .drop" in decide
        and ordered(save, "decideDelivery(", "redirectURL()") and "stateQueue.sync { sharedMedia }" not in save,
    "deliveryFindsFinishedFirst": "if isFinished { return .alreadyDelivered }" in decide,
    "deliveryDropsAnAbortedShare": "guard !isAbortedNow else { return .drop }" in decide,
    "deliveryMarksFinishedBeforeTheAbortCheck": ordered(decide, "isFinished = true", "guard !isAbortedNow"),
    "postWaitsForSettledLoads": "return hasSettledLoads" in valid and "hasSettledLoads = true" in notify and "validateContent()" in notify,
    "requestIsCompletedOnce": len(calls(body, "extensionContext?.completeRequest")) == 1,
    "directoriesAreTracked": "stagedURLs.append(directory)" in destination,
    "thumbnailsAreTracked": "stagedURLs.append(thumbnailPath)" in thumbnail,
    "redirectIsComputedBeforeDefaultsAreWritten": "redirectURL()" in save and "UserDefaults(" in save
        and ordered(save, "redirectURL()", "UserDefaults("),
    "redirectFailureCleansUp": bool(re.search(r"guard let url = redirectURL\(\) else \{[^}]*cleanupStagedFiles\(\)", save)),
    "defaultsFailuresCleanUp": bool(re.search(r"guard let ud = UserDefaults\(suiteName: appGroupId\) else \{[^}]*cleanupStagedFiles\(\)", save))
        and bool(re.search(r"guard let data = try\? JSONEncoder\(\)\.encode\(media\) else \{[^}]*cleanupStagedFiles\(\)", save)),
    "redirectFailsClosed": "schemeSafeHost(hostAppBundleIdentifier)" in redirect_url and "return nil" in redirect_url
        and "\\(hostAppBundleIdentifier)" not in redirect_url,
    "emptyResultCleansUp": notify.count("cleanupStagedFiles()") >= 2,
    "toStringIsPrivateAndDebugOnly": "#if DEBUG\n    private func toString()" in source,
    "loggingIsCompiledOutOfReleaseBuilds": "#if DEBUG" in logger,
}
for name, value in pins.items():
    print(f"pin {name} = {value}")
if unsafe_access:
    print("unsafe shared-state access:", unsafe_access)
with open(os.path.join(out, "SourcePins.swift"), "w") as f:
    f.write("public enum SourcePins {\n" + "".join(f"    static let {n} = {'true' if v else 'false'}\n" for n, v in pins.items()) + "}\n")

a, b, sanitizer = block(controller, "    private func sanitizedComponent(")
report("sanitizedComponent", controller, a, b, sanitizer)
with open(os.path.join(out, "Sanitizer.swift"), "w") as f:
    f.write("import Foundation\n\nstruct Sanitizer {\n// BEGIN VERBATIM\n" + sanitizer + "// END VERBATIM\n}\n\n"
            "extension Sanitizer {\n    /// Test entry point: `private` members are visible to extensions in the same file.\n"
            "    func sanitize(_ raw: String) -> String { sanitizedComponent(raw) }\n}\n")
