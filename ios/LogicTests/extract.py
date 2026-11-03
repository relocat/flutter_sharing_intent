#!/usr/bin/env python3
"""Generate the Swift logic package sources from the plugin's Swift files.

Usage: extract.py <repo_root> <out_sources_dir> <variant>

The function bodies are copied byte-for-byte from ios/Classes; the script prints
the source line range and the sha256 of each copied block, and each generated
file holds the block between BEGIN/END markers so the copy can be re-hashed.

variant "new"     : the shipped functions.
variant "control" : negative control. isRegularFile is replaced by a stub that
                    accepts everything (the behaviour before FSI-103), so the
                    regular-file tests must fail.
"""
import hashlib, os, sys

root, out, variant = sys.argv[1:4]
plugin = "ios/Classes/SwiftFlutterSharingIntentPlugin.swift"
controller = "ios/Classes/FSIShareViewController.swift"


def block(path, start_prefix):
    lines = open(os.path.join(root, path), encoding="utf-8").read().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith(start_prefix))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return start + 1, end + 1, "\n".join(lines[start:end + 1]) + "\n"


def report(name, path, first, last, text):
    print(f"{name}: {path} lines {first}-{last} sha256={hashlib.sha256(text.encode()).hexdigest()}")


os.makedirs(out, exist_ok=True)

a, b, guard = block(plugin, "    static func isStrictlyInsideContainer(")
report("isStrictlyInsideContainer", plugin, a, b, guard)
a, b, regular = block(plugin, "    static func isRegularFile(")
report("isRegularFile", plugin, a, b, regular)
if variant == "control":
    regular = "    static func isRegularFile(atPath path: String) -> Bool {\n        return true\n    }\n"
with open(os.path.join(out, "ContainerGuard.swift"), "w") as f:
    f.write("import Foundation\n\npublic enum ContainerGuard {\n// BEGIN VERBATIM\n" + guard + regular + "// END VERBATIM\n}\n")

a, b, sanitizer = block(controller, "    private func sanitizedComponent(")
report("sanitizedComponent", controller, a, b, sanitizer)
with open(os.path.join(out, "Sanitizer.swift"), "w") as f:
    f.write("import Foundation\n\nstruct Sanitizer {\n// BEGIN VERBATIM\n" + sanitizer + "// END VERBATIM\n}\n\n"
            "extension Sanitizer {\n    /// Test entry point: `private` members are visible to extensions in the same file.\n"
            "    func sanitize(_ raw: String) -> String { sanitizedComponent(raw) }\n}\n")
