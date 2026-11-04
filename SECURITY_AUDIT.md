# flutter_sharing_intent — Security Audit (Relocat fork)

**Audit date started:** 2026-04-21
**Auditor:** Relocat maintainers
**Scope:** everything under this repository except `example/` and `build/`.
**Methodology:** STRIDE-lite per-entry-point + remediation-commit review + dependency & license audit.
**Status:** Closed 2026-04-21 — 5 findings fixed (FSI-90..94; FSI-95 was fixed later, see the addendum below), 5 residual risks accepted (R-SI-03 was fixed later, see the addendum below), 3 low-severity dependency items deferred with rationale. FSI-96..99 were fixed on 2026-10-13 and FSI-100..107 on 2026-11-03/04; see the addenda below.

Task labels C1-C4 in the revision history are the audit's own work phases:
C1 scaffold, C2 entry-point enumeration, C3 fixes, C4 dependency and licence review.

## Upstream & Fork

- **Upstream:** https://github.com/TSPL-Bhagat/flutter_sharing_intent
- **Upstream license:** Apache-2.0
- **Fork purpose:** Relocat vendors this plugin because Relocat needs these fixes before a pub.dev release contains them, and several iOS/Android issues affect Relocat directly. Divergence rationale lives in the fork notice at the top of `README.md`.
- **Earlier fork fixes** (made before this audit):
  - FSI-11 — Android: removed unused UI dependencies (appcompat, material, constraintlayout).
  - FSI-21 — Android: reject non-`content://` URIs in share intents.
  - FSI-23 — Android: prune stale thumbnail cache entries.
  - FSI-24 — Android: intent handling moved off main thread.
  - FSI-31 — Android/iOS/Dart: cleanup API for App Group files.
  - FSI-61 — iOS: surface decode errors instead of swallowing.
  - FSI-72 — iOS: PHAsset resolution off main thread.
  - FSI-81 — iOS: UIScene lifecycle bridging.

## Summary Table

Updated as findings are filed. Severity: Critical / High / Medium / Low / Info.

| Finding ID | Severity | Title | Status | Fix commit |
|---|---|---|---|---|
| FSI-90 | High | Android: no size cap on ContentResolver stream (DoS) | Fixed | `c51b102` |
| FSI-91 | High | Android: path traversal via _display_name (Tampering) | Fixed | `da04541` |
| FSI-92 | High | iOS: no size cap on raw Data payload in handleFileItem (DoS) | Fixed | `c0d7d5b` |
| FSI-93 | High | iOS: path traversal via url.lastPathComponent (Tampering) | Fixed | `abc695e` |
| FSI-94 | Medium | Dart: out-of-range SharedMediaType index crashes isolate (DoS) | Fixed | `ea0c3fd` |

## Entry Points

Enumerated 2026-04-21.
Scope excludes `example/` and `build/`. Line numbers captured at commit
`6762c74`; may drift if the files are modified.

### Android native (plugin layer)

| File | Line(s) | Symbol | Trust boundary |
|---|---|---|---|
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 77–82 | `setupCallbackChannels` / `MethodChannel("flutter_sharing_intent")` | **in-app** — registers the method channel endpoint that Dart calls. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 80–82 | `setupCallbackChannels` / `EventChannel(EVENTS_CHANNEL_MEDIA)` | **in-app** — registers the event channel that streams share payloads to Dart. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 90–111 | `onMethodCall` — switch on `call.method` (`getInitialSharing`, `reset`, `cleanup`) | **in-app** — handles Dart-originated MethodChannel calls; no untrusted data read here. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 341–344 | `onNewIntent(intent: Intent)` | **untrusted** — entry point for warm-start shares; receives an `Intent` delivered by Android from an external (third-party) app. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 346–350 | `onAttachedToActivity` → `handleIntent(binding.activity.intent, true)` | **untrusted** — cold-start entry point; reads the launch `Intent` which came from an external app. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 136 | `handleIntent` — `intent.getFlags()` | **untrusted** — reads flag bits from external-app-supplied `Intent`. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 138–147 | `handleIntent` — `intent.type`, `intent.action` | **untrusted** — reads MIME type and action string from external-app-supplied `Intent`. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 185–188 | `computeSharingPayload` — `intent.dataString` (ACTION_VIEW) | **untrusted** — URL string from external-app-supplied `Intent`; no length or scheme validation. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 186–188 | `computeSharingPayload` — `intent.getStringExtra(SearchManager.QUERY)` (ACTION_WEB_SEARCH) | **untrusted** — free-form search query string from external app; no length cap. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 199 | `getSharingUris` — `intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)` | **untrusted** — URI supplied by external app; scheme filtering enforced downstream in `MyFileDirectory`. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 216 | `getSharingUris` — `intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)` | **untrusted** — list of URIs from external app; no count cap before iterating. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 240 | `getSharingText` — `intent.getStringExtra(Intent.EXTRA_TEXT)` | **untrusted** — arbitrary text from external app; no length cap. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 251 | `getSharingText` — `intent.getStringArrayListExtra(Intent.EXTRA_TEXT)` | **untrusted** — list of text strings from external app; no count or total-size cap. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/FlutterSharingIntentPlugin.kt` | 365–379 | `onListen(arguments, events)` — `EventChannel.StreamHandler` | **in-app** — Dart subscribes to the sharing event stream; `arguments` value compared against literal `"sharing"`. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` | — | `getAbsolutePath(context, uri)` | **untrusted** — the URI and its path segments come from the external app; scheme is validated (see FSI-21, FSI-100). |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` | — | `getDataColumn` — `contentResolver.query(uri, ...)` | **untrusted** — queries a provider chosen by the external app; the returned display name is provider-supplied (see FSI-91). |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` | — | `getDataColumn` — `contentResolver.openInputStream(uri)` | **untrusted** — reads a provider-controlled stream into the app cache (see FSI-90). |

### iOS native (plugin layer)

| File | Line(s) | Symbol | Trust boundary |
|---|---|---|---|
| `ios/Classes/FSIShareViewController.swift` | 122–219 | `processAttachments` — `extensionContext?.inputItems` | **untrusted** — reads `NSExtensionItem` attachments delivered by the host OS from the sharing source app; this is the primary ingestion point for all shared media. |
| `ios/Classes/FSIShareViewController.swift` | 134–207 | `processAttachments` — `provider.loadItem(forTypeIdentifier:...)` (image / movie / file / url / text / data / item) | **untrusted** — loads raw attachment data (URL, UIImage, Data, String) supplied by the source app's share extension for each type identifier; no size cap before `loadItem` is dispatched. |
| `ios/Classes/FSIShareViewController.swift` | 84–99 | `didSelectPost` — `self.contentText` | **untrusted** — text entered by the user in the share sheet compose field (SLComposeServiceViewController); treated as-is, no length cap. |
| `ios/Classes/FSIShareViewController.swift` | — | `handleImageItem` — copies URL, UIImage, or raw Data to App Group container | **untrusted** — attachment payload (see FSI-92). |
| `ios/Classes/FSIShareViewController.swift` | — | `handleVideoItem` — copies video URL to App Group container | **untrusted** — source URL from the attachment (see FSI-93). |
| `ios/Classes/FSIShareViewController.swift` | — | `handleFileItem` — copies file URL or raw Data to App Group container | **untrusted** — file URL or raw `Data` from the attachment (see FSI-92, FSI-93). |
| `ios/Classes/FSIShareViewController.swift` | — | `getFileName(from:type:)` — `url.lastPathComponent` | **untrusted** — file name derived from the source URL (see FSI-93). |
| `ios/Classes/FSIShareViewController.swift` | 315–325 | `saveAndRedirect` — `UserDefaults(suiteName: appGroupId).set(data, forKey: kUserDefaultsKey)` | **in-app** (main→extension) — writes JSON-encoded `[SharingFile]` into the App Group shared UserDefaults; read by the main app. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 207–227 | `application(_:didFinishLaunchingWithOptions:)` — `launchOptions[.url]` and `launchOptions[.userActivityDictionary]` | **in-app** (OS→main app) — receives the redirect URL or NSUserActivity that the share extension sent via `redirectToHostApp`; scheme prefix validated by `hasSameSchemePrefix`. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 234–239 | `application(_:open:url:options:)` — `open url: URL` | **in-app** (OS→main app) — warm-start URL open callback; scheme prefix validated before `handleUrl`. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 247–254 | `application(_:continue:restorationHandler:)` — `userActivity.webpageURL` | **in-app** (OS→main app) — NSUserActivity continuation; scheme prefix validated before `handleUrl`. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 81–98 | `handleSceneURLContexts(_:)` (static) — `UIOpenURLContext` set | **in-app** (OS scene→main app) — FSI-81 scene-delegate forwarder; scheme prefix validated per context before `handleUrl`. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 111–117 | `handleSceneUserActivity(_:)` (static) — `NSUserActivity.webpageURL` | **in-app** (OS scene→main app) — FSI-81 scene-delegate forwarder; scheme prefix validated before `handleUrl`. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 257–294 | `handleUrl(url:setInitialData:)` — `UserDefaults(suiteName:).object(forKey: kUserDefaultsKey)` | **in-app** (extension→main, via App Group) — reads the JSON blob written by `FSIShareViewController`; decoded via `JSONDecoder`; decode errors surfaced to Dart (FSI-61). |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 123–153 | `handle(_:result:)` — `FlutterMethodCall` dispatch (`getInitialSharing`, `reset`, `getPlatformVersion`, `cleanup`) | **in-app** — Dart-originated MethodChannel call; `cleanup` receives a `paths: [String]` list from Dart and deletes files; container-prefix guard present at line 181. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 441–448 | `onListen(withArguments:eventSink:)` — `FlutterEventSink` registration | **in-app** — Dart subscribes to share event stream; argument validated against literals `"sharing"` / `"text"`. |
| `ios/Classes/SwiftFlutterSharingIntentPlugin.swift` | 473–495 | `getAbsolutePathAsync(for:completion:)` — PHAsset lookup + `requestContentEditingInput` | **in-app** — resolves a local-identifier string (from the App Group blob) into an iCloud-resident asset path; `isNetworkAccessAllowed = true` means a network fetch may be triggered for iCloud assets. |

### Dart (plugin API + channel glue)

| File | Line(s) | Symbol | Trust boundary |
|---|---|---|---|
| `lib/flutter_sharing_intent.dart` | 17 | `EventChannel("flutter_sharing_intent/events-sharing")` | **in-app** — Dart-side event channel endpoint; receives JSON strings from native. |
| `lib/flutter_sharing_intent.dart` | 62–75 | `getMediaStream` — `_eChannelMedia.receiveBroadcastStream("sharing")` | **in-app** — subscribes to the native event stream; emitted string is passed to `jsonDecode` at line 69 without size or schema pre-validation. |
| `lib/flutter_sharing_intent.dart` | 69 | `jsonDecode(data)` in `getMediaStream` StreamTransformer | **in-app** — parses JSON produced by native layer; unconstrained decode of a string whose size is controlled by the share source via the intent/App Group pathway. |
| `lib/flutter_sharing_intent.dart` | 27–29 | `getInitialSharing()` — public API | **in-app** — delegates to platform channel; result decoded in `MethodChannelFlutterSharingIntent.getInitialSharing`. |
| `lib/flutter_sharing_intent.dart` | 46–47 | `cleanup(List<String> paths)` — public API | **in-app** — passes caller-supplied path list to native layer; native enforces container-prefix guard on iOS. |
| `lib/flutter_sharing_intent_method_channel.dart` | 13 | `MethodChannel('flutter_sharing_intent')` | **in-app** — Dart-side method channel; all calls go to the registered native handler. |
| `lib/flutter_sharing_intent_method_channel.dart` | 29–35 | `getInitialSharing()` — `methodChannel.invokeMethod('getInitialSharing')` + `jsonDecode(json)` | **in-app** — decodes the JSON string returned by native; no size or schema pre-validation before `jsonDecode`. |
| `lib/flutter_sharing_intent_method_channel.dart` | 38–41 | `cleanup(List<String> paths)` — `methodChannel.invokeMethod('cleanup', {'paths': paths})` | **in-app** — forwards Dart-supplied path list to native. |
| `lib/model/sharing_file.dart` | 32–40 | `SharedFile.fromJson(Map<String, dynamic> json)` | **in-app** — deserializes a map decoded from native JSON into a `SharedFile`; `json['type']` is used as a raw index into `SharedMediaType.values` at line 37 with no bounds check (out-of-range index throws `RangeError`). |

### Notes

- Exported Android components declared in `android/src/main/AndroidManifest.xml`: none — the plugin manifest contains only commented-out example snippets. All `<activity>` and `<intent-filter>` entries are commented out. The host app's own manifest is responsible for declaring the exported activity with the intent filters; this plugin contributes no exported components directly. When the host app adds the recommended `android:exported="true"` activity (per plugin README), no `android:permission` guard is shown in the template — the host app is responsible for guarding that activity in its own manifest; this is outside the plugin's scope.
- iOS `NSExtension` activation rules are defined per-host-app, not in the plugin itself — the plugin provides `FSIShareViewController` which the host configures. The host app is responsible for its activation rule (out of scope here).
- Entry points that carry untrusted data (from a source app's `Intent` / `NSExtensionContext`) are flagged **untrusted** in the table; boundaries where both sides are controlled by the same app process or by the OS delivering a previously-validated redirect are flagged **in-app**.

## Findings

### FSI-90: Android — no size cap on ContentResolver.openInputStream (DoS)

**Severity:** High
**Affected file:** `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` lines 138–143 (pre-fix)
**STRIDE category:** Tampering + Denial of Service
**Description:** The size of a streamed file was not bounded by the plugin.
**Impact:** Cache storage exhaustion and denial of service.
**Fix summary:** Introduced `MAX_STREAM_BYTES = 16 MiB` constant on `MyFileDirectory`. Replaced `copyTo` with a manual read loop that accumulates `totalWritten`; if the cap is exceeded the partial cache file is deleted and an `IOException` is thrown with a clear plugin-attributed message. `IOException` import added.
**Residual risk:** 16 MiB is a hard plugin ceiling, not a default: a host app cannot raise it at runtime, and changing it means editing `MAX_STREAM_BYTES`. A host app can enforce a lower limit of its own, but not a higher one. The cap applies per file, and one oversized file aborts the whole share: the `IOException` leaves `getSharingUris`, the executor's `catch (Throwable)` logs it, and no item of that share reaches Dart.

### FSI-91: Android — path traversal via _display_name (Tampering)

**Severity:** High
**Affected file:** `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` lines 117–119 (pre-fix)
**STRIDE category:** Tampering
**Description:** A provider-supplied display name could influence the cache path.
**Impact:** Files could be written outside the intended cache location.
**Fix summary:** Added `sanitizeDisplayName(raw: String?): String` helper (marked `internal` for testability). The helper: (1) strips any path-prefix component before the last `/` or `\`; (2) rejects `.` and `..` as "unnamed"; (3) strips C0 control characters and NUL; (4) caps the result at 255 UTF-8 bytes; (5) falls back to "unnamed" for null/blank/empty inputs. `getDataColumn` now passes the raw cursor value through `sanitizeDisplayName` before constructing the `File` object.
**Update (2026-10-13, FSI-98):** the original step (4) decoded the first 255 bytes with `String(bytes, 0, 255, UTF_8)`, which can split a multi-byte character; the decoder then inserts U+FFFD, and the result can exceed 255 bytes (for example 256 or 257). Step (4) now steps back over UTF-8 continuation bytes and cuts on a code point boundary, so the result is at most 255 bytes and contains no U+FFFD.
**Residual risk:** Unicode homoglyphs in filenames are not normalized — this is acceptable as they do not affect filesystem path resolution on Android. The cut is on a code point boundary, not a grapheme-cluster boundary, so it can separate a combining mark or an emoji sequence from the rest of its character; the name stays valid and within the limit.

### FSI-92: iOS — no size cap on raw Data payload in handleFileItem (DoS)

**Severity:** High
**Affected file:** `ios/Classes/FSIShareViewController.swift` lines 284–291 (pre-fix)
**STRIDE category:** Denial of Service
**Description:** The size of a raw data payload was not bounded before it was written.
**Impact:** App Group container storage exhaustion.
**Fix summary:** Added `private static let kMaxRawDataBytes = 16 * 1024 * 1024` constant (16 MiB) to `FSIShareViewController`. In the `Data` branch of `handleFileItem`, added a `guard raw.count <= Self.kMaxRawDataBytes` check that returns early and logs a `print` diagnostic (consistent with the fork's existing `print`-based logging style) if the payload exceeds the cap.
**Residual risk:** The `Data` object is loaded into memory before the size check. For very large payloads the memory allocation itself could be a concern, but `NSItemProvider.loadItem` applies its own limits in practice; this guard prevents the disk write.

### FSI-93: iOS — path traversal via url.lastPathComponent (Tampering)

**Severity:** High
**Affected file:** `ios/Classes/FSIShareViewController.swift` lines 368–372 (pre-fix), specifically `getFileName(from:type:)` and all callers that pass the result to `containerURL()?.appendingPathComponent(...)`.
**STRIDE category:** Tampering
**Description:** A URL-derived file name could influence the destination path.
**Impact:** Files could be written outside the intended container directory.
**Fix summary:** Added `private func sanitizedComponent(_ raw: String) -> String` helper that: (1) returns "unnamed" for `.` and `..`; (2) strips `/` characters using `filter`; (3) caps at 255 UTF-8 bytes with proper Unicode scalar boundary truncation; (4) returns "unnamed" for blank/empty results. `getFileName(from:type:)` now passes `url.lastPathComponent` through `sanitizedComponent` before returning. All three call sites (`handleImageItem`, `handleVideoItem`, `handleFileItem`) inherit the fix via `getFileName`.
**Update (2026-10-13, FSI-97):** the helper now also strips NUL and the other C0 (U+0000–U+001F), DEL (U+007F) and C1 (U+0080–U+009F) control characters, truncates on a Character (grapheme-cluster) boundary instead of a Unicode scalar boundary, and checks for `.`, `..` and blank names after stripping. The earlier comment claimed NUL could not occur in a Swift `String`; that was wrong.
**Residual risk:** The thumbnail path in `getThumbnailPath(for:)` uses `Data(url.lastPathComponent.utf8).base64EncodedString()` — base64 encoding the raw component makes it safe already; no fix needed there.

### FSI-94: Dart — out-of-range SharedMediaType index crashes isolate (DoS)

**Severity:** Medium
**Affected file:** `lib/model/sharing_file.dart` line 37 (pre-fix)
**STRIDE category:** Denial of Service
**Description:** An out-of-range media-type value in the payload could make decoding fail.
**Impact:** Loss of the affected share.
**Fix summary:** Replaced direct indexing with a top-level `_typeFromJson(Object? raw)` helper. The helper checks `raw is int`, bounds-checks the index against `SharedMediaType.values.length`, and returns `SharedMediaType.FILE` as a conservative fallback for out-of-range integers. A non-integer, null or missing `type` falls back to index 0 (`SharedMediaType.TEXT`). Added `test/sharing_file_test.dart` covering valid indices, out-of-range positive and negative indices, non-integer type, null, and missing key.
**Residual risk:** The original fix hardened only `type`; the other fields of `SharedFile.fromJson` still threw a `TypeError` on a wrongly typed value (for example a non-int `duration` or a non-String `value`). This was fixed on 2026-10-13 (FSI-99, see the addendum): every field is now type-checked and a wrongly typed field is treated as absent. A payload that is not a JSON list of objects still makes decoding throw; the error reaches the app as described above.

## Dependency & License Review

Completed 2026-04-21 (after the C3 fixes).

### Dart

| Package | Declared | Locked | Pinned? | Notes |
|---|---|---|---|---|
| `plugin_platform_interface` | `^2.1.8` | `2.1.8` | No (`^`) | Floating minor; latest is 2.1.8 — current, but range allows future auto-upgrade. Low risk for a stable interface package. |
| `flutter` (SDK) | SDK | `0.0.0` | N/A | SDK dep; version governed by Flutter SDK itself. |
| `flutter_test` (dev) | SDK | `0.0.0` | N/A | SDK dep; dev only. |
| `flutter_lints` (dev) | `^6.0.0` | `6.0.0` | No (`^`) | Dev-only; floating minor. No security impact. |

**Dart SDK constraint:** `>=3.1.2 <4.0.0`

**Transitive deps (from pubspec.lock):** `async 2.13.1`, `collection 1.19.1`, `meta 1.17.0`, `path 1.9.1`, `vector_math 2.2.0` — all are well-maintained core Dart/Flutter packages. No known advisories as of 2026-04-21. Check the dependencies against the OSV / GitHub advisory databases on each release, for example by running `osv-scanner` on `pubspec.lock`.

**Finding DEP-01 (Low):** `plugin_platform_interface` declared with `^2.1.8` (caret — floating minor). Should be pinned to exact version for a vendored fork. No security advisory outstanding; purely a supply-chain hygiene concern.

### Android

- **Gradle wrapper:** not present in this plugin repository (plugin-only library; wrapper is supplied by host app build system). No `gradle-wrapper.properties` found.
- **Android Gradle Plugin (AGP):** `7.3.0` (declared in `buildscript.dependencies`)
- **Kotlin:** `2.1.20` (declared in `ext.kotlin_version`)
- **compileSdk:** `36`
- **minSdk:** `21`
- **targetSdk:** not set at plugin level (library plugin; host app sets targetSdk — correct pattern for Android library modules)
- **Repositories:** `google()` and `mavenCentral()` only. No `jcenter()`. PASS.
- **Runtime dependencies:** none (`dependencies {}` block is empty).

**Play Store floor:** targetSdk is host-app responsibility; plugin does not declare it. PASS for plugin scope.

**Finding DEP-02 (Low):** AGP `7.3.0` is significantly outdated (released September 2022; the current stable line is 9.x as of October 2026). While this is a library plugin (the host app's AGP ultimately governs the build), an outdated buildscript AGP can cause compatibility warnings and may not receive security patches for build-tooling vulnerabilities. Recommend bumping to the latest stable AGP.

### iOS

- **Deployment target:** `12.0` (`s.platform = :ios, '12.0'`)
- **Pod dependencies:** `Flutter` only (no third-party pods)
- **Podspec license:** `{ :file => '../LICENSE' }` — correctly references upstream Apache-2.0 LICENSE file. PASS.
- **Swift version:** `5.0`

**Finding DEP-03 (Low):** iOS deployment target `12.0`. iOS 12 reached end of security updates in 2023 and represents a negligible real-world install base (< 1%). Recommend raising to `13.0` minimum. iOS 13 is required by Flutter 3.22+ in practice; keeping `12.0` in the podspec is misleading.

### License

- **Upstream:** Apache-2.0 (as declared in `LICENSE`, confirmed full text present)
- **Fork license (`NOTICE`):** Apache-2.0 retained for fork modifications; `NOTICE` is a fork notice, not a separate license. It states that all modifications retain Apache-2.0 and lists the modified files.
- **Compatibility verdict:** Compatible. Apache-2.0 is compatible with inclusion in GPL-3.0 works (one-way, per the FSF's licence compatibility assessment), and the app that consumes this fork is licensed GPL-3.0-or-later. Apache-2.0 is not compatible with GPL-2.0-only, which does not apply here.
- **Divergence document (fork notice in `README.md`):** Documents fork purpose, base commit (`aa1672f`), the FSI fixes and the host integration pattern. PASS.

### SPDX headers

All 8 Relocat-modified source files (4 Dart, 2 Kotlin, 2 Swift) were missing `SPDX-License-Identifier` headers. The upstream base commit (`aa1672f`) did not include SPDX annotations; Relocat added modifications across 12 commits without inserting headers.

Fixed in commit `a80d489`: `// SPDX-License-Identifier: Apache-2.0` prepended to all 8 files.

Post-fix state of the current tree: every modified source file carries an `SPDX-License-Identifier: Apache-2.0` header and a "Modified by Relocat (2026); see NOTICE." line: the 8 files above, plus `android/build.gradle`, `test/flutter_sharing_intent_test.dart` and `test/sharing_file_test.dart`, which received them in a later commit. `pubspec.yaml` carries the modified-by comment and is listed in `NOTICE`. Files this fork did not modify (for example `ios/Classes/FlutterSharingIntentPlugin.h` and `.m`) are not annotated and fall under the repository `LICENSE`.

### Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| DEP-01 | Low | `plugin_platform_interface` declared with floating `^` range in pubspec.yaml | Open — cosmetic; pin on next dependency update cycle |
| DEP-02 | Low | Android Gradle Plugin pinned at `7.3.0` (September 2022; current stable line is 9.x) | Open — no active CVE; bump recommended |
| DEP-03 | Low | iOS podspec deployment target `12.0` (iOS 12 EOL; misleading for Flutter 3.22+) | Open — raise to `13.0` on next podspec update |
| SPDX-01 | Low | All 8 Relocat-modified source files missing SPDX-License-Identifier | Fixed — commit `a80d489` (the 8 files; three more modified files were annotated later) |

## Accepted Residual Risks

The following issues were identified during C2/C3 but are not fixed in this audit. Each has a documented justification for deferral or acceptance.

### R-SI-01: getParcelableArrayListExtra URI count cap (Android)

**File:** `FlutterSharingIntentPlugin.kt` line 216
**Risk:** The number of URIs in one share is not capped by the plugin; the host app enforces a batch cap.
**Justification for deferral:** Host apps should enforce a batch cap at their service layer. The plugin's 16 MiB per-file cap (FSI-90) limits per-file damage. Fixing this at the plugin layer requires duplicating a policy decision that belongs to the host app. Tracked as a host-app-level control, not a plugin fix.
**Owner:** host app service layer.

### R-SI-02: getStringArrayListExtra count/size cap (Android)

**File:** `FlutterSharingIntentPlugin.kt` line 251
**Risk:** Unbounded list of text strings from `EXTRA_TEXT`; no count or total-size cap before iterating.
**Justification for deferral:** Same argument as R-SI-01. Text shares are not file I/O; the primary risk is memory pressure, which is limited in practice by Android's IPC Binder transaction size limit (~1 MB). Host apps should enforce their own upper limits. Tracked as host-app-level control.
**Owner:** host app service layer.

### R-SI-03: Unguarded print() statements in FSIShareViewController (iOS)

**File:** `ios/Classes/FSIShareViewController.swift` (multiple lines)
**Risk:** `print()` calls in the share extension can leak diagnostic information to the system log, visible to any app with the `com.apple.syslog.read` entitlement or to a connected debugger.
**Status update:** Fixed in `b0d272b` (release builds no longer log file names or paths). The original deferral rationale follows.
**Justification for deferral:** No key material, credentials, or PII is printed — only filenames, byte counts, and error labels. The existing `log()` helper already gates on `debugLogs = false`. The bare `print` calls are residual from the upstream fork. Tracked as a fork hygiene follow-up.
**Owner:** fork hygiene follow-up.

### R-SI-04: Empty catch {} in handleFileItem Data branch (iOS)

**File:** `ios/Classes/FSIShareViewController.swift` around line 291 (pre-fix 290)
**Risk:** `try raw.write(to: dst)` failure is silently swallowed by `catch {}`. A write failure produces no diagnostic and the share silently drops the attachment.
**Justification for deferral:** Not a security vulnerability (the write failing is safe-fail). It is a reliability concern. Tracked as a fork hygiene follow-up.
**Owner:** fork hygiene follow-up.

### R-SI-05: Dead code writeTempFile(_:to:) (iOS)

**Status:** Resolved. The unused `writeTempFile` method was removed (FSI-107).

## Related

- Upstream: https://github.com/TSPL-Bhagat/flutter_sharing_intent
- Fork rationale & licensing: the fork notice in `README.md`, and `NOTICE`

## Revision History

| Date | Change | Author |
|---|---|---|
| 2026-04-21 | Initial scaffold (C1). | Relocat maintainers |
| 2026-04-21 | Entry-point enumeration (C2). | Relocat maintainers |
| 2026-04-21 | FSI-90 fix: Android stream size cap (C3). | Relocat maintainers |
| 2026-04-21 | FSI-91 fix: Android _display_name sanitization (C3). | Relocat maintainers |
| 2026-04-21 | FSI-92 fix: iOS raw Data size cap (C3). | Relocat maintainers |
| 2026-04-21 | FSI-93 fix: iOS filename sanitization (C3). | Relocat maintainers |
| 2026-04-21 | FSI-94 fix: Dart SharedMediaType bounds check (C3). | Relocat maintainers |
| 2026-04-21 | C3 close: residual risks + SHA backfill. | Relocat maintainers |
| 2026-04-21 | SPDX headers added to all 8 Relocat-modified source files (C4). | Relocat maintainers |
| 2026-04-21 | Dependency & license review complete (C4). | Relocat maintainers |
| 2026-04-21 | Addendum: R-SI-03 resolved (`b0d272b`). | Relocat maintainers |
| 2026-06-15 | Addendum: FSI-95 fixed, App Group share-metadata plist wipe (`f01fef4`). | Relocat maintainers |
| 2026-10-13 | Public wording, chronological addenda, complete list of earlier fork fixes. | Relocat maintainers |
| 2026-10-13 | Addendum: FSI-96..99 fixed (`7c09732`); FSI-90, FSI-94, R-SI-01/02 and DEP-02 wording corrected. | Relocat maintainers |
| 2026-11-03 | Addendum: FSI-100..103 fixed (content URIs always copied, no share content in logs, per-share directories, cleanup removes only regular files); wording corrections. | Relocat maintainers |
| 2026-11-04 | Addendum: FSI-104, FSI-105 fixed (failed copies leave nothing behind, links are never followed, cache roots are re-created, iOS files live in a plugin-owned subdirectory and cleanup is limited to it). | Relocat maintainers |
| 2026-11-04 | Addendum: FSI-106 fixed (API level, partial deletes, thumbnails, Android `cleanup`, log allowlist, iOS directory checks). | Relocat maintainers |
| 2026-11-04 | Addendum: FSI-107 fixed (share-extension file protection, staged-file cleanup on cancel and error, strict bundle-id encoding, release-build logging). | Relocat maintainers |

## Addendum (2026-04-21): R-SI-03 resolved

R-SI-03 (unguarded `print()` calls in `FSIShareViewController`) is fixed in `b0d272b`: release builds
no longer log file names or paths.

## Addendum (2026-06-15): FSI-95, App Group share-metadata plist wipe

| Finding ID | Severity | Title | Status | Fix commit |
|---|---|---|---|---|
| FSI-95 | Low | iOS: App Group share-metadata plist persisted after the app consumed it (information exposure at rest) | Fixed | `f01fef4` |

The iOS share extension stores share metadata in the App Group `UserDefaults`, which is backed by a
plist on disk. The plugin now wipes that plist as soon as the app reads it, so file names and paths
of shared items no longer linger at rest. Found in a later native review round (2026-06-10), fixed 2026-06-15. The same commit also gates the
path logging in `cleanupFiles` behind `#if DEBUG`.

## Addendum (2026-10-13): FSI-96..99, cleanup guard, name truncation, control characters, field types

An internal review before publication found the following. All four are fixed in `7c09732`.

| Finding ID | Severity | Title | Status | Fix commit |
|---|---|---|---|---|
| FSI-96 | Medium | iOS: `cleanup` container check was a string prefix, weaker than documented | Fixed | `7c09732` |
| FSI-97 | Low | iOS: `sanitizedComponent` kept NUL and other control characters, and could cut inside a Character | Fixed | `7c09732` |
| FSI-98 | Low | Android: `sanitizeDisplayName` truncation could split a character, insert U+FFFD and exceed 255 bytes | Fixed | `7c09732` |
| FSI-99 | Low | Dart: `SharedFile.fromJson` threw on wrongly typed fields other than `type` | Fixed | `7c09732` |

**FSI-96.** `cleanupFiles` checked the container with a string prefix, which was weaker than its comment
described. The caller is the host app's own Dart code, so the practical risk was low. The new
`isStrictlyInsideContainer` fails closed: it rejects empty and relative paths and any path with a `..`
component, standardises both paths (`standardizedFileURL`) and requires the candidate's path components to
start with the container's components and to be longer, so the container itself is also refused. `..` is
rejected rather than resolved because the kernel resolves it after following symlinks, so a lexical
clean-up could name a different file from the one `removeItem` deletes.

**FSI-97.** The comment claimed NUL cannot occur in a Swift `String`; it can. `sanitizedComponent` now
strips NUL, C0, DEL and C1 control characters, truncates by whole Characters within 255 UTF-8 bytes
(the result is valid UTF-8 and contains no U+FFFD) and checks for `.`, `..` and blank names after
stripping.

**FSI-98.** See the update under FSI-91.

**FSI-99.** See the residual-risk note under FSI-94. `test/sharing_file_test.dart` covers each field.

**Verification.**
- Swift: the logic of `isStrictlyInsideContainer` and `sanitizedComponent` is unit-tested on Linux
  (Swift 6.0.3, XCTest; 32 tests, all pass). The functions are copied byte-for-byte from the iOS
  sources into a scratch package, and the copies' SHA-256 hashes match the source lines. Run against
  the previous code, the same tests fail 18 of 32, including every `..`, sibling-prefix, NUL,
  control-character and Character-boundary case.
- Kotlin: `sanitizeDisplayName`, copied byte-for-byte, was compiled with kotlinc 2.1.20 and run on
  the JVM: 21 checks pass. The previous version fails 6 (results of 256 and 257 bytes containing
  U+FFFD).
- Dart: `flutter test` passes 16 of 16. The previous `sharing_file.dart` fails the 3 new negative
  tests.
- iOS compile and tests on macOS (GitHub-hosted macOS runner, 2026-10-13): the example app builds with `flutter build ios --simulator --no-codesign`, the plugin Swift sources and the README SceneDelegate sample type-check, and the 32 Swift logic tests pass (`swift test`).

## Addendum (2026-11-03): FSI-100..103, URI handling, logging, cache layout, iOS cleanup

An internal review before publication found the following. All four are fixed in this revision.

| Finding ID | Severity | Title | Status |
|---|---|---|---|
| FSI-100 | High | Android: some `content://` document URIs were resolved to a path derived from the URI instead of a cache copy | Fixed |
| FSI-101 | Medium | Android: share payloads, paths and file names were logged in release builds | Fixed |
| FSI-102 | Medium | Android: shared files were written straight into the root of the app cache directory under the sender-supplied name | Fixed |
| FSI-103 | Low | iOS: `cleanup` could remove directories recursively | Fixed |

**FSI-100.** Extends FSI-21. `getAbsolutePath` now accepts only `content://` URIs and always copies the
stream (16 MiB cap, FSI-90) into the plugin's cache; no path is ever derived from the URI. The
document-provider special cases that returned a path directly are removed, as is the fallback that
returned the URI's own path. A URI without an authority yields no result, and the provider-supplied
`_data` column is no longer returned. `android/jvm-tests/` holds the unit tests.

**FSI-101.** Log lines now carry counts and types only: no payload, path, URI, file name or exception
message. Exceptions are logged by class name. A test fails if a `Log` call interpolates share content.

**FSI-102.** Each shared item is written to its own directory,
`<cacheDir>/flutter_sharing_intent/<random UUID>/<sanitised name>`, so a share cannot overwrite another
cache file and nothing is written to the cache root. The sanitised display name stays the file name.
Video thumbnails go to a separate root, `<cacheDir>/flutter_sharing_intent_thumbnails/<random UUID>.png`.
The plugin prunes UUID-named share directories and thumbnails older than 7 days, and no longer scans the
cache root. Residual risk: the OS, not the plugin, reclaims a share directory before it is 7 days old.

**FSI-103.** `cleanupFiles` already required a path strictly inside the App Group container (FSI-96). It
now also requires a regular file (`isRegularFile`, which does not follow symbolic links) and refuses
directories, symbolic links and missing paths, so `removeItem` can no longer delete a directory tree.

**Not changed.** Item counts are not capped (R-SI-01, R-SI-02), and iOS copies made from file URLs are
uncapped: only raw `Data` is capped at 16 MiB.

**Verification.**
- Android: the real `MyFileDirectory.kt` is compiled with kotlinc against Java stand-ins for the
  `android.*` classes and run on the JVM (`android/jvm-tests/run.sh`). Each fix has a negative control
  that reintroduces the old behaviour and must fail its tests.
- Swift: `ios/LogicTests/` holds the Swift logic tests; the functions are copied byte-for-byte from
  the iOS sources. On a GitHub-hosted macOS runner (2026-11-03) the example app builds, the plugin Swift sources type-check, and the 36 logic tests pass; the negative control (regular-file check disabled) fails as expected.

## Addendum (2026-11-04): FSI-104, FSI-105, failed copies, cache roots, links, iOS file layout

| Finding ID | Severity | Title | Status |
|---|---|---|---|
| FSI-104 | Medium | Android: a failed or partial copy could leave data in the cache; recursive deletes and cache roots were not hardened | Fixed |
| FSI-105 | Medium | iOS: the share extension wrote into the container root and `cleanup` could delete any regular file in the container | Fixed |

**FSI-104.**
- A copy that fails for any reason (an unreadable provider, a read error part-way, an over-cap source, a missing stream) deletes its per-share directory before the failure propagates. For a multi-item share, every copy made for the intent is deleted if any item fails, so a dropped share leaves nothing in the cache.
- A bad thumbnail or duration (for example a malformed video) no longer drops the share: the item is delivered without it. Only I/O and runtime failures are absorbed.
- Both cache roots are re-created on every use, because the host may wipe them. A plain file found in place of a root is replaced by a directory; a symbolic link in its place makes the share fail closed.
- Recursive deletes (pruning, partial-copy cleanup) never follow symbolic links: a link is removed itself and its target is left alone.
- A `content://` URI with an empty authority is treated like one without an authority.
- Log statements are checked against an allowlist: only counts, sizes, exception class names and fixed tags may be interpolated, and no exception object is passed to the logger.

**FSI-105.** The share extension now writes
`<App Group container>/flutter_sharing_intent/<UUID>/<name>` (one directory per shared item) and
`<container>/flutter_sharing_intent_thumbnails/<UUID>.jpg`. `cleanup` deletes only regular files of
exactly that shape (FSI-31, FSI-103) and then removes an emptied per-share directory. Files at the
container root, including those written by earlier versions of the plugin, are no longer deletable
through `cleanup`; the host app removes such leftovers itself. The Swift logic tests cover the
`cleanup` wiring with the shipped function, and a negative control that removes a guard must fail.

**Verification.** Android: `android/jvm-tests/run.sh` (see the previous addendum), with negative
controls for each change and for the log allowlist. iOS: `ios/LogicTests/`.

## Addendum (2026-11-04): FSI-106, API level, partial deletes, thumbnails, Android cleanup, log allowlist

| Finding ID | Severity | Title | Status |
|---|---|---|---|
| FSI-106 | High | Android: the cache code used `java.nio.file` calls that need API 26, although the plugin supports API 21; plus follow-up hardening on both platforms | Fixed |

- **API level.** The plugin no longer uses `java.nio.file` or `File.toPath`. Links and entry types are
  read with `android.system.Os.lstat` (API 21), and deletes are a manual recursion that never
  descends into a link. A source check fails if those calls return. The JVM tests use a stand-in for
  `Os.lstat`; Android lint (`NewApi`) was run on the plugin for this change (0 findings).
- **Partial deletes.** `deleteShareCopies` and the recursive delete keep going after a failure; the
  first error is rethrown at the end with the others suppressed, and an undeletable child is not
  masked by a "directory not empty" error from its parent.
- **Thumbnails.** A thumbnail is written through one function that deletes the file when the encoder
  returns false or throws. When a multi-item share is dropped, the thumbnails already created for it
  are deleted with its copies.
- **Android `cleanup`.** It now deletes the plugin's own regular files, never following links:
  `<cache>/flutter_sharing_intent/<UUID>/<name>` (then the emptied directory, non-recursively) and
  `<cache>/flutter_sharing_intent_thumbnails/<UUID>.png`. Every other path is refused.
- **Log allowlist.** Each `Log` call must be two arguments: `TAG` or a string literal, and a single
  string literal whose interpolations are limited to the fixed tag, an exception class name, or a
  count. Concatenation, bare expressions, the exception-object form, a third argument, `wtf` and
  `println` with content all fail the check. The Intent type is no longer logged.
- **iOS.**
  - A thumbnail is owned only if its file name is `<UUID>.jpg`.
  - The plugin directories on the path must be real directories (checked with `lstat`); a symbolic
    link in their place is refused.
  - An emptied per-share directory is removed with a non-recursive `rmdir`, derived from the
    standardised path.
  - File URLs are converted to paths with `URL`, so names with spaces or non-ASCII characters
    resolve.
  - A failed thumbnail write leaves no file.
- **Follow-ups.**
  - A thumbnail is recorded for cleanup the moment it exists, so a later failure still deletes it.
  - A thumbnail counts as written only after the output stream closed successfully.
  - A failing cleanup never replaces the original error; it is attached as suppressed.
  - Independent delete failures in different subtrees are all recorded.
  - `cleanup` always replies and returns the number of files removed, on both platforms.
  - The descriptions of FSI-90..94 are descriptive only.
- **Example app.** `example/ios/Share Extension/FSIShareViewController.swift` is now a copy of the
  hardened `ios/Classes/FSIShareViewController.swift`, and the README setup step points there.

## Addendum (2026-11-04): FSI-107, share-extension hardening

| Finding ID | Severity | Title | Status |
|---|---|---|---|
| FSI-107 | Medium | iOS: staged files were not protected while the device is locked, were left behind on cancel or error, and the redirect URL embedded the bundle id with a permissive character set | Fixed |

- Every file the share extension stages is written with complete file protection (`.completeFileProtection`
  on data writes, and the class is raised on copied files), so it is unreadable while the device is locked.
- The extension tracks everything it staged in one invocation (per-share directories and thumbnails) and
  deletes it on cancel and on error. On success the files are kept, because the host app reads them and then
  calls `cleanup`. This is in addition to the immediate removal of a directory whose write failed.
- A video thumbnail is written to `<container>/flutter_sharing_intent_thumbnails/<UUID>.jpg`; the name is
  unique per thumbnail, and an existing file is never reused.
- The bundle id embedded in the redirect URL is percent-encoded with a strict character set (letters,
  digits, `.`, `-`); if it cannot be encoded the extension exits instead of using the raw id.
- A missing `AppGroupId` Info.plist key is logged, because a derived group id stops matching the
  entitlement when the bundle id changes. The derived fallback itself is unchanged.
- `toString` is private and compiled only in debug builds; the debug logger is compiled out of release builds
  and no longer logs the host or group identifiers.
- The unused `writeTempFile` method was removed (R-SI-05).
- Residuals: the extension cannot tell that a share comes from the host app itself, because items arrive as local
  file URLs; the host app's Dart layer performs that check. The metadata plist of the App Group `UserDefaults`
  keeps the OS default protection class; the plugin deletes it when read (FSI-95), which limits the window to the hand-off.
- Verification: the encoding helper and the staged-item removal are unit-tested; the other guarantees are pinned from
  the shipped source and each pin has a negative control.
