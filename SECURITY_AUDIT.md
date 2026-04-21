# flutter_sharing_intent — Security Audit (Relocat fork)

**Audit date started:** 2026-04-21
**Auditor:** Relocat maintainers
**Scope:** everything under this repository except `example/` and `build/`.
**Methodology:** STRIDE-lite per-entry-point + remediation-commit review + dependency & license audit.
**Status:** Draft — findings populated as the audit progresses.

Task labels C1-C4 in the revision history are the audit's own work phases:
C1 scaffold, C2 entry-point enumeration, C3 fixes, C4 dependency and licence review.

## Upstream & Fork

- **Upstream:** https://github.com/bhagat-techind/flutter_sharing_intent
- **Upstream license:** Apache-2.0
- **Fork purpose:** Relocat vendors this plugin because upstream release cadence is slow and several iOS/Android issues affect Relocat directly. Divergence rationale lives in `README.relocat.md`.
- **Earlier fork fixes** (made before this audit):
  - FSI-24 — Android: intent handling moved off main thread.
  - FSI-31 — Android/iOS/Dart: cleanup API for App Group files.
  - FSI-61 — iOS: surface decode errors instead of swallowing.
  - FSI-72 — iOS: PHAsset resolution off main thread.
  - FSI-81 — iOS: UIScene lifecycle bridging.

## Summary Table

Updated as findings are filed. Severity: Critical / High / Medium / Low / Info.

| Finding ID | Severity | Title | Status | Fix commit |
|---|---|---|---|---|
| FSI-90 | High | Android: no size cap on ContentResolver stream (DoS) | Fixed | TBD |

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
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` | 35–93 | `getAbsolutePath(context, uri)` | **untrusted** — full URI resolution path; scheme is validated (non-`content://` rejected at line 40), but the `docId` string parsed at lines 51–55 and the `id` from `DocumentsContract` at line 61–63 come directly from the URI supplied by the external app. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` | 105–160 | `getDataColumn` — `contentResolver.query(uri, ...)` | **untrusted** — issues a `ContentResolver.query` against an authority from the external app's URI; the `_display_name` returned by the provider is used directly as a filename for the cache-file at line 119. |
| `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` | 138–143 | `getDataColumn` — `contentResolver.openInputStream(uri)` | **untrusted** — opens a byte stream from a provider-controlled URI and copies to app cache; no size limit enforced. |

### iOS native (plugin layer)

| File | Line(s) | Symbol | Trust boundary |
|---|---|---|---|
| `ios/Classes/FSIShareViewController.swift` | 122–219 | `processAttachments` — `extensionContext?.inputItems` | **untrusted** — reads `NSExtensionItem` attachments delivered by the host OS from the sharing source app; this is the primary ingestion point for all shared media. |
| `ios/Classes/FSIShareViewController.swift` | 134–207 | `processAttachments` — `provider.loadItem(forTypeIdentifier:...)` (image / movie / file / url / text / data / item) | **untrusted** — loads raw attachment data (URL, UIImage, Data, String) supplied by the source app's share extension for each type identifier; no size cap before `loadItem` is dispatched. |
| `ios/Classes/FSIShareViewController.swift` | 84–99 | `didSelectPost` — `self.contentText` | **untrusted** — text entered by the user in the share sheet compose field (SLComposeServiceViewController); treated as-is, no length cap. |
| `ios/Classes/FSIShareViewController.swift` | 240–258 | `handleImageItem` — copies URL, UIImage, or raw Data to App Group container | **untrusted** — attachment payload; raw `Data` written verbatim to container at line 288–290 without size check. |
| `ios/Classes/FSIShareViewController.swift` | 261–273 | `handleVideoItem` — copies video URL to App Group container | **untrusted** — source URL from attachment; filename derived from `url.lastPathComponent` (attacker-controlled) at line 369. |
| `ios/Classes/FSIShareViewController.swift` | 275–294 | `handleFileItem` — copies file URL or raw Data to App Group container | **untrusted** — raw `Data` path writes an attacker-sized blob to the App Group container (line 287–290) with no size limit. |
| `ios/Classes/FSIShareViewController.swift` | 368–372 | `getFileName(from:type:)` — `url.lastPathComponent` | **untrusted** — filename derived from attacker-controlled URL; used directly as the destination filename in the App Group container. |
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

- Exported Android components declared in `android/src/main/AndroidManifest.xml`: none — the plugin manifest contains only commented-out example snippets. All `<activity>` and `<intent-filter>` entries are commented out. The host app's own manifest is responsible for declaring the exported activity with the intent filters; this plugin contributes no exported components directly. When the host app adds the recommended `android:exported="true"` activity (per plugin README), no `android:permission` guard is shown in the template — this is an in-scope concern for the Relocat mobile app manifest audit, not the plugin itself.
- iOS `NSExtension` activation rules are defined per-host-app, not in the plugin itself — the plugin provides `FSIShareViewController` which the host configures. The host's activation rule is audited separately as part of the Relocat mobile app review (out of scope here).
- Entry points that carry untrusted data (from a source app's `Intent` / `NSExtensionContext`) are flagged **untrusted** in the table; boundaries where both sides are controlled by the same app process or by the OS delivering a previously-validated redirect are flagged **in-app**.

## Findings

### FSI-90: Android — no size cap on ContentResolver.openInputStream (DoS)

**Severity:** High
**Affected file:** `android/src/main/kotlin/com/techind/flutter_sharing_intent/MyFileDirectory.kt` lines 138–143 (pre-fix)
**STRIDE category:** Tampering + Denial of Service
**Reproduction sketch:** A malicious source app advertises a `content://` URI whose backing provider streams an unbounded byte sequence. `getDataColumn` opened this stream and called `InputStream.copyTo(FileOutputStream)` with no size limit, writing the full provider output into `context.cacheDir`. An attacker can exhaust cacheDir storage, causing `FileOutputStream` failures that crash subsequent operations or fill the device partition.
**Impact:** Host app cacheDir storage exhaustion; denial-of-service for any feature relying on cache space; potential `OutOfMemoryError` for very large streams buffered in memory.
**Fix summary:** Introduced `MAX_STREAM_BYTES = 16 MiB` constant on `MyFileDirectory`. Replaced `copyTo` with a manual read loop that accumulates `totalWritten`; if the cap is exceeded the partial cache file is deleted and an `IOException` is thrown with a clear plugin-attributed message. `IOException` import added.
**Residual risk:** Host apps that legitimately need files > 16 MiB must provide their own override at the service layer (the host app enforces its own, larger limit). The plugin cap is intentionally conservative.

## Dependency & License Review

_(populated by Task C4)_

## Accepted Residual Risks

_(populated during C5 sign-off)_

## Related

- Upstream: https://github.com/bhagat-techind/flutter_sharing_intent
- Fork rationale & licensing: `README.relocat.md` and `LICENSE.relocat`

## Revision History

| Date | Change | Author |
|---|---|---|
| 2026-04-21 | Initial scaffold (C1). | Relocat maintainers |
| 2026-04-21 | Entry-point enumeration (C2). | Relocat maintainers |
| 2026-04-21 | FSI-90 fix: Android stream size cap (C3). | Relocat maintainers |
