// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
import Flutter
import Photos
import UIKit

public class SwiftFlutterSharingIntentPlugin: NSObject, FlutterStreamHandler, FlutterPlugin {
    static let kMessagesChannel = "\(kAppChannel)/messages"
    static let kEventsChannelMedia = "\(kAppChannel)/events-sharing";
    
    private var initialSharing: [SharingFile]? = nil
    private var latestSharing: [SharingFile]? = nil
    
    
    private var eventSinkMedia: FlutterEventSink? = nil;
    // Singleton is required for calling functions directly from AppDelegate
    // - it is required if the developer is using also another library, which requires to call "application(_:open:options:)"
    // -> see Example app
    public static let instance = SwiftFlutterSharingIntentPlugin()

    // MARK: - UIScene bridging (FSI-81)
    //
    // On iOS 13+, apps that use the UIScene lifecycle (the Flutter default
    // since Flutter 3.41) receive external URL opens through
    // `UISceneDelegate` callbacks (`scene(_:willConnectTo:options:)`,
    // `scene(_:openURLContexts:)`, `scene(_:continue:)`) instead of the
    // `UIApplicationDelegate` callbacks this plugin registers for.
    //
    // Flutter 3.38 added a plugin scene hook (`registrar.addSceneDelegate`
    // with `FlutterSceneLifeCycleDelegate`). This plugin does not adopt it
    // yet, because that API does not exist in the older Flutter SDKs the
    // plugin still supports. Since 3.38, `FlutterSceneDelegate` passes scene
    // URL and user-activity events on to plugins that registered only
    // application-delegate callbacks, as this one does. For hosts where that
    // does not happen (a SceneDelegate that does not subclass
    // `FlutterSceneDelegate`, or an older Flutter SDK), we expose static
    // forwarders that the host app's `SceneDelegate` can call.
    //
    // The `sharedInstance` reference is populated during `register(with:)`
    // so the host app can reach the live plugin instance from its own
    // SceneDelegate. It is a plain strong reference to the existing
    // `static let instance` singleton; there is no retain cycle because
    // the plugin is already a process-lifetime object.
    //
    // If `sharedInstance` is nil (plugin not yet registered), the
    // forwarders are safe no-ops — the host SceneDelegate can be wired
    // unconditionally without crashing.
    //
    // See README.md (fork notice) for the SceneDelegate boilerplate hosts must
    // install.
    public static var sharedInstance: SwiftFlutterSharingIntentPlugin?


    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: kAppChannel,binaryMessenger:registrar.messenger())

        registrar.addMethodCallDelegate(instance, channel: channel)

        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)


        registrar.addApplicationDelegate(instance)
        // registrar.addMethodCallDelegate(instance, channel: channel)

        // FSI-81: expose the live plugin instance to host SceneDelegate
        // forwarding methods. See UIScene bridging section above.
        sharedInstance = instance

        // Bound how long leftovers of an interrupted share can live (FSI-107).
        instance.sweepStaleSharedFilesInBackground()
    }

    /// Host-side forwarder for `UISceneDelegate.scene(_:openURLContexts:)`
    /// and the `urlContexts` in `scene(_:willConnectTo:options:)`
    /// connection options (FSI-81).
    ///
    /// Host apps with scene-based lifecycles must call this method from
    /// their SceneDelegate so that share-extension redirect URLs reach the
    /// plugin on iOS 13+ when Flutter does not pass the scene events on
    /// itself (see the UIScene bridging section above). Without forwarding
    /// in that case, share intake through the scene path is silently broken.
    ///
    /// SECURITY: the URL is passed through the same `hasSameSchemePrefix`
    /// gate used by the AppDelegate path (enforced inside `handleUrl`'s
    /// callers on the AppDelegate side; here we gate before forwarding so
    /// that the scene path has equivalent prefix isolation).
    ///
    /// CONCURRENCY: must be called on the main thread (scene delegate
    /// callbacks are main-thread by contract). `handleUrl` may dispatch
    /// PHAsset resolution asynchronously; results are delivered to the
    /// event sink from the main queue (see `resolveSharedFiles`).
    ///
    /// Safe no-op when the plugin has not yet been registered.
    @objc public static func handleSceneURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
        guard let plugin = sharedInstance else { return }
        for context in urlContexts {
            let url = context.url
            if plugin.hasSameSchemePrefix(url: url) {
                // setInitialData: false matches AppDelegate's
                // `application(_:open:options:)` warm-start semantics. The
                // cold-start case (first scene connecting with a URL in
                // `connectionOptions.urlContexts`) is handled by the host
                // SceneDelegate calling this same method from
                // `scene(_:willConnectTo:options:)`; the plugin cannot
                // distinguish the two, and the effect on Dart-side intake
                // is equivalent because `getInitialSharing` clears both
                // caches after the first read.
                _ = plugin.handleUrl(url: url, setInitialData: false)
            }
        }
    }

    /// Host-side forwarder for `UISceneDelegate.scene(_:continue:)` and
    /// for `NSUserActivity` entries in `scene(_:willConnectTo:options:)`
    /// connection options (FSI-81).
    ///
    /// Mirrors the existing AppDelegate
    /// `application(_:continue:restorationHandler:)` semantics — passes
    /// `setInitialData: true` so cold-start universal-link activity is
    /// surfaced to Dart via `getInitialSharing`.
    ///
    /// Safe no-op when the plugin has not yet been registered or when the
    /// activity has no `webpageURL`.
    @objc public static func handleSceneUserActivity(_ userActivity: NSUserActivity) {
        guard let plugin = sharedInstance,
              let url = userActivity.webpageURL else { return }
        if plugin.hasSameSchemePrefix(url: url) {
            _ = plugin.handleUrl(url: url, setInitialData: true)
        }
    }

    //  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //    result("iOS " + UIDevice.current.systemVersion)
    //  }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        
        switch call.method {
        case "getInitialSharing":
            result(toJson(data: self.initialSharing));
            /// Clear cache data to send only once
            self.initialSharing = nil
            self.latestSharing = nil
            // FSI-95: the persisted App Group metadata plist is already cleared
            // by handleUrl the moment it lifts the payload into memory (the only
            // path that populates these caches), so there is nothing to clear
            // here. Clearing unconditionally here would risk wiping a concurrent
            // second share's metadata before its own handleUrl runs.

        case "reset":
            self.initialSharing = nil
            self.latestSharing = nil
            result(nil);

        case "getPlatformVersion" :
            result("iOS " + UIDevice.current.systemVersion);

        case "cleanup":
            guard let args = call.arguments as? [String: Any],
                  let paths = args["paths"] as? [String] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                    message: "cleanup requires paths: [String]", details: nil))
                return
            }
            result(cleanupFiles(paths: paths))

        default:
            result(FlutterMethodNotImplemented);
        }
    }

    /// Removes the App Group UserDefaults entries that carry share metadata
    /// (staged-file paths, MIME types, and the share message text), so the
    /// OS-default-protection-class plist does not linger on disk readable from
    /// a locked device after first unlock (FSI-95).
    ///
    /// Called from `handleUrl` once the host app has lifted a payload into
    /// memory. `consumed` is the exact payload blob that was just read: the
    /// keys are removed ONLY while the persisted blob still equals it, so a
    /// second share written by a concurrent extension run between our read and
    /// this clear is never wiped before its own `handleUrl` consumes it
    /// (cross-process compare-and-clear; the residual TOCTOU is sub-millisecond
    /// and iOS serialises share-sheet invocations). `synchronize()` forces the
    /// cross-process App Group plist flush so the removal is durable even if the
    /// host is killed immediately afterwards.
    private func clearPersistedShareMetadata(consumed: Data) {
        guard let ud = UserDefaults(suiteName: resolvedAppGroupId()) else { return }
        guard let current = ud.object(forKey: kUserDefaultsKey) as? Data,
              current == consumed else { return }
        ud.removeObject(forKey: kUserDefaultsKey)
        ud.removeObject(forKey: kUserDefaultsMessageKey)
        ud.synchronize()
    }

    /// Resolves the App Group identifier with the same precedence as the share
    /// extension: the `AppGroupId` Info.plist key if set, otherwise the
    /// conventional `group.<host-bundle-id>` identifier.
    private func resolvedAppGroupId() -> String {
        let custom = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        return custom ?? "group.\(Bundle.main.bundleIdentifier ?? "")"
    }

    /// Resolves the App Group container URL from `resolvedAppGroupId`.
    private func appGroupContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolvedAppGroupId())
    }

    /// Deletes shared-file copies after the host app has processed them
    /// (FSI-31). Best-effort: per-file errors are logged and swallowed; the
    /// method never throws back to Dart. The work is done by
    /// `removeOwnedFiles`, which is the unit the logic tests exercise.
    private func cleanupFiles(paths: [String]) -> Int {
        guard let groupUrl = self.appGroupContainerURL() else {
            NSLog("[FSI] cleanup: no App Group container URL available")
            return 0
        }
        return Self.removeOwnedFiles(paths: paths, containerURL: groupUrl)
    }

    /// Directory below the App Group container that holds one sub-directory
    /// per shared item (`<container>/flutter_sharing_intent/<UUID>/<name>`).
    /// Must match `FSIShareViewController.kShareRootName` (the share extension
    /// is a separate target and cannot link this file).
    static let kShareRootName = "flutter_sharing_intent"

    /// Directory below the App Group container that holds generated video
    /// thumbnails (`<container>/flutter_sharing_intent_thumbnails/<UUID>.jpg`).
    static let kThumbnailRootName = "flutter_sharing_intent_thumbnails"

    /// Removes each path that is a regular file owned by this plugin and
    /// strictly inside `containerURL` (FSI-31, FSI-103, FSI-105). Every other
    /// path is refused, so a caller cannot make the plugin delete a directory,
    /// a symbolic link, or any file it did not write. After a share file is
    /// removed, its now-empty per-share directory is removed too.
    @discardableResult
    static func removeOwnedFiles(paths: [String], containerURL: URL) -> Int {
        let fm = FileManager.default
        var removedCount = 0
        for p in paths {
            // SECURITY: only delete the plugin's own files below the App Group
            // container (FSI-31, FSI-105).
            guard Self.isPluginOwnedPath(path: p, containerURL: containerURL) else {
                // Path intentionally omitted from the release log: it carries
                // App Group container / share-filename metadata (zero-knowledge).
                #if DEBUG
                NSLog("[FSI] cleanup: refusing to delete a path the plugin does not own: \(p)")
                #else
                NSLog("[FSI] cleanup: refusing to delete a path the plugin does not own")
                #endif
                continue
            }
            // Work on the standardised path from here on, so the checks and the
            // delete name the same file.
            let standardized = URL(fileURLWithPath: p).standardizedFileURL.path
            // SECURITY (FSI-106): every owned directory on the way must be a
            // real directory, so a symlinked plugin root cannot redirect a delete.
            guard Self.hasRealOwnedDirectories(path: standardized, containerURL: containerURL) else {
                NSLog("[FSI] cleanup: refusing to delete below a non-directory")
                continue
            }
            // SECURITY (FSI-103): `removeItem` deletes directories recursively
            // and the plugin only ever writes regular files, so anything else
            // (a directory, a symlink, a missing path) is refused.
            guard Self.isRegularFile(atPath: standardized) else {
                NSLog("[FSI] cleanup: refusing to delete a non-regular item")
                continue
            }
            do {
                try fm.removeItem(atPath: standardized)
                removedCount += 1
                Self.removeEmptyShareDirectory(containing: standardized, containerURL: containerURL)
            } catch {
                #if DEBUG
                NSLog("[FSI] cleanup failed for \(p): \(error.localizedDescription)")
                #else
                NSLog("[FSI] cleanup failed for a container file")
                #endif
            }
        }
        return removedCount
    }

    /// Age after which an unreferenced share directory or thumbnail is removed
    /// by `sweepStaleFiles`. Far above any share's lifetime, because the share
    /// extension may be running while the sweep runs.
    static let kStaleFileMaxAgeSeconds: TimeInterval = 24 * 60 * 60

    /// Reads the pending payload and sweeps stale plugin files off the main
    /// thread. Files named in the pending payload are never swept.
    private func sweepStaleSharedFilesInBackground() {
        guard let container = appGroupContainerURL() else { return }
        var identifiers: [String] = []
        if let data = UserDefaults(suiteName: resolvedAppGroupId())?.data(forKey: kUserDefaultsKey),
           let files = try? decode(data: data) {
            for file in files {
                identifiers.append(file.value)
                if let thumbnail = file.thumbnail { identifiers.append(thumbnail) }
            }
        }
        let referenced = Self.referencedKeys(fromIdentifiers: identifiers)
        DispatchQueue.global(qos: .utility).async {
            _ = Self.sweepStaleFiles(containerURL: container, referencedKeys: referenced,
                                     now: Date(), maxAge: Self.kStaleFileMaxAgeSeconds)
        }
    }

    /// The keys of the plugin items named by stored file identifiers (`file://`
    /// URLs or plain paths): `<root>/<uuid>` for a path inside a share directory
    /// and `<root>/<uuid>.jpg` for a thumbnail, with the UUID lowercased. Only
    /// the components after the plugin root name are used, so a different
    /// container prefix (for example `/private/var` instead of `/var`) cannot
    /// make a referenced item look unreferenced. Identifiers that do not convert
    /// or do not have the plugin shape are skipped.
    static func referencedKeys(fromIdentifiers identifiers: [String]) -> Set<String> {
        var keys = Set<String>()
        for identifier in identifiers {
            guard let path = filePath(fromFileIdentifier: identifier) else { continue }
            let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
            for index in components.indices.dropLast() {
                let next = components[index + 1]
                if components[index] == kShareRootName, UUID(uuidString: next) != nil {
                    keys.insert(kShareRootName + "/" + next.lowercased())
                } else if components[index] == kThumbnailRootName, isThumbnailLeaf(next) {
                    keys.insert(kThumbnailRootName + "/" + next.lowercased())
                }
            }
        }
        return keys
    }

    /// Removes leftovers of interrupted shares and returns how many were
    /// removed (FSI-107). Only two kinds of entry below the plugin roots are
    /// candidates: a UUID-named directory under `flutter_sharing_intent` and a
    /// `<UUID>.jpg` regular file under `flutter_sharing_intent_thumbnails`. An
    /// entry is removed only if it is older than `maxAge` and neither it nor
    /// anything inside it is in `referencedKeys`. A root must be a real
    /// directory; a symbolic link (as a root or as an entry), any other name and
    /// anything outside the two roots is never touched or followed.
    @discardableResult
    static func sweepStaleFiles(containerURL: URL, referencedKeys: Set<String>, now: Date, maxAge: TimeInterval) -> Int {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-maxAge)
        let container = containerURL.standardizedFileURL
        var removedCount = 0
        for rootName in [kShareRootName, kThumbnailRootName] {
            let isShareRoot = rootName == kShareRootName
            let root = container.appendingPathComponent(rootName, isDirectory: true)
            guard let rootAttributes = try? fm.attributesOfItem(atPath: root.path),
                  (rootAttributes[.type] as? FileAttributeType) == .typeDirectory,
                  let names = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for name in names {
                guard isShareRoot ? UUID(uuidString: name) != nil : isThumbnailLeaf(name) else { continue }
                let child = root.appendingPathComponent(name, isDirectory: isShareRoot)
                guard let attributes = try? fm.attributesOfItem(atPath: child.path),
                      (attributes[.type] as? FileAttributeType) == (isShareRoot ? .typeDirectory : .typeRegular),
                      let modified = attributes[.modificationDate] as? Date, modified < cutoff else { continue }
                let key = rootName + "/" + name.lowercased()
                if referencedKeys.contains(key) { continue }
                if (try? fm.removeItem(at: child)) != nil { removedCount += 1 }
            }
        }
        return removedCount
    }

    /// Returns true only if `path` has the exact shape the share extension
    /// writes (FSI-105), strictly inside the container:
    /// `<container>/flutter_sharing_intent/<UUID>/<file>` or
    /// `<container>/flutter_sharing_intent_thumbnails/<file>`. Files at the
    /// container root, deeper paths and other directories are not owned.
    static func isPluginOwnedPath(path: String, containerURL: URL) -> Bool {
        guard let relative = relativeComponents(path: path, containerURL: containerURL) else { return false }
        switch relative.count {
        case 2:
            return relative[0] == kThumbnailRootName && isThumbnailLeaf(relative[1])
        case 3:
            return relative[0] == kShareRootName && UUID(uuidString: relative[1]) != nil
        default:
            return false
        }
    }

    /// True only for a thumbnail leaf name of the exact form `<UUID>.jpg`.
    static func isThumbnailLeaf(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    /// True only if every directory between the container and the file of an
    /// owned path (the plugin root and the per-share directory) is a real
    /// directory according to `lstat`, never a symbolic link (FSI-106).
    static func hasRealOwnedDirectories(path: String, containerURL: URL) -> Bool {
        guard let relative = relativeComponents(path: path, containerURL: containerURL),
              relative.count >= 2 else { return false }
        let fm = FileManager.default
        var directory = containerURL.standardizedFileURL
        for component in relative.dropLast() {
            directory = directory.appendingPathComponent(component, isDirectory: true)
            guard let attributes = try? fm.attributesOfItem(atPath: directory.path),
                  (attributes[.type] as? FileAttributeType) == .typeDirectory else { return false }
        }
        return true
    }

    /// The path components of `path` below the container, or nil when the path
    /// is not strictly inside it (see `isStrictlyInsideContainer`).
    static func relativeComponents(path: String, containerURL: URL) -> [String]? {
        guard isStrictlyInsideContainer(path: path, containerURL: containerURL) else { return nil }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return Array(candidate.dropFirst(containerURL.standardizedFileURL.pathComponents.count))
    }

    /// Removes the per-share directory that held the just-deleted share file,
    /// but only when it is an empty directory of the owned shape. Thumbnail
    /// files have no per-share directory, so nothing happens for them.
    static func removeEmptyShareDirectory(containing path: String, containerURL: URL) {
        guard isPluginOwnedPath(path: path, containerURL: containerURL),
              let relative = relativeComponents(path: path, containerURL: containerURL),
              relative.count == 3 else { return }
        // Non-recursive on purpose: rmdir fails on a directory that is not
        // empty, and the directory comes from the standardised URL (FSI-106).
        let directory = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
        _ = rmdir(directory)
    }

    /// Returns true only if `path` names an item strictly below `containerURL`
    /// (FSI-31 cleanup guard). The check is lexical and fails closed:
    ///
    /// 1. An empty or relative path is rejected, because it cannot be anchored
    ///    to the container.
    /// 2. A path with any `..` component is rejected outright. The kernel
    ///    resolves `..` after following symlinks, so a lexical clean-up of
    ///    `<container>/link/../x` could name a different file from the one
    ///    `removeItem` deletes. Paths this plugin hands to Dart never contain
    ///    `..`, so rejecting them costs nothing.
    /// 3. Both paths are standardised (`standardizedFileURL`: `.` segments,
    ///    repeated and trailing slashes removed) and compared by path
    ///    component, so a sibling such as `<container>-sibling/x` does not match.
    ///    The candidate must have more components than the container: the
    ///    container itself is never accepted.
    ///
    /// Symlinks are not resolved by this lexical check. `removeOwnedFiles`
    /// covers them separately: `hasRealOwnedDirectories` refuses a symlinked
    /// plugin directory and `isRegularFile` refuses a symlink as the last
    /// component, so a link can never redirect a delete.
    static func isStrictlyInsideContainer(path: String, containerURL: URL) -> Bool {
        guard !path.isEmpty, path.hasPrefix("/") else { return false }
        let rawComponents = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !rawComponents.contains("..") else { return false }

        let candidate = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let container = containerURL.standardizedFileURL.pathComponents
        guard !container.isEmpty, candidate.count > container.count else { return false }
        return Array(candidate.prefix(container.count)) == container
    }

    /// Returns true only if `path` names a regular file. The check does not
    /// follow symbolic links (`attributesOfItem` reports the link itself), so a
    /// symlink, a directory, a missing path and an empty path are all refused
    /// and `cleanupFiles` never deletes recursively (FSI-103).
    static func isRegularFile(atPath path: String) -> Bool {
        guard !path.isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType else { return false }
        return type == .typeRegular
    }

    // By Adding bundle id to prefix, we will ensure that the correct app will be openned
    public func hasSameSchemePrefix(url: URL?) -> Bool {
        if let url = url, let appDomain = Bundle.main.bundleIdentifier {
            return url.absoluteString.hasPrefix("\(kSchemePrefix)-\(appDomain)")
        }
        return false
    }
    
    // This is the function called on app startup with a shared link if the app had been closed already.
    // It is called as the launch process is finishing and the app is almost ready to run.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if the app is not able to.
    // If the URL does not include the module's prefix, we must return true since while our module cannot handle the link, other modules might be and returning false can prevent
    // them from getting the chance to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622921-application
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
            if (hasSameSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
            return true
        } else if let activityDictionary = launchOptions[UIApplication.LaunchOptionsKey.userActivityDictionary] as? [AnyHashable: Any] {
            // Handle multiple URLs shared in
            for key in activityDictionary.keys {
                if let userActivity = activityDictionary[key] as? NSUserActivity {
                    if let url = userActivity.webpageURL {
                        if (hasSameSchemePrefix(url: url)) {
                            return handleUrl(url: url, setInitialData: true)
                        }
                        return true
                    }
                }
            }
        }
        return true
    }
    
    // This is the function called on resuming the app from a shared link.
    // It handles requests to open a resource by a specified URL. Returning true means that it was handled successfully, false means the attempt to open the resource failed.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we return false to indicate our module's attempt to open the resource failed and others should be allowed to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if (hasSameSchemePrefix(url: url)) {
            return handleUrl(url: url, setInitialData: false)
        }
        return false
    }
    
    // This function is called by other modules like Firebase DeepLinks.
    // It tells the delegate that data for continuing an activity is available. Returning true means that our module handled the activity and that others do not have to. Returning false tells
    // iOS that our app did not handle the activity.
    // If the URL includes the module's ShareMedia prefix, then we process the URL and return true if we know how to handle that kind of URL or false if we are not able to.
    // If the URL does not include the module's prefix, then we must return false to indicate that this module did not handle the prefix and that other modules should try to.
    // Reference: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application
    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            if (hasSameSchemePrefix(url: url)) {
                return handleUrl(url: url, setInitialData: true)
            }
        }
        return false
    }
    
    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
           let appGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
           let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
           let userDefaults = UserDefaults(suiteName: appGroupId ?? defaultGroupId)

           let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
           if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
               // FSI-95: the App Group UserDefaults plist that carries share
               // metadata (staged-file paths, MIME types, message text) inherits
               // the OS-default CompleteUntilFirstUserAuthentication protection
               // class, so it stays readable from a locked device after first
               // unlock. The previous `reset`/`getInitialSharing` path cleared
               // only the in-memory caches, leaving this plist on disk until the
               // next share overwrote it. We have lifted the payload into the
               // `json` value, so the persisted copy must be removed (collapsing
               // the on-disk metadata window from "until the next share" to the
               // share-handoff interval, during which the device is necessarily
               // unlocked). The file contents are already written with
               // .completeFileProtection by the share extension.
               //
               // The clear is deferred to AFTER the decode attempt below (in both
               // the success and the decode-failure branch) so the persisted blob
               // is never removed before we have committed to consuming it; `json`
               // is an in-memory snapshot, so decode is unaffected by the clear.
               // `clearPersistedShareMetadata` compares against the exact blob we
               // read, so a concurrently-written second share is never wiped
               // before its own `handleUrl` consumes it.
               let sharedArray: [SharingFile]
               do {
                   sharedArray = try decode(data: json)
               } catch {
                   // FSI-61: surface decode failures (e.g. tampered / corrupted
                   // App Group UserDefaults) to Dart instead of silently
                   // returning an empty list, which is indistinguishable from
                   // "no shares received" and hides lateral-movement tampering.
                   NSLog("[FSI] decode failed: \(error.localizedDescription)")
                   // A deterministic decode failure means the blob is permanently
                   // un-decodable, so wipe it too rather than leave tampered
                   // plaintext lingering on disk (FSI-95).
                   clearPersistedShareMetadata(consumed: json)
                   let err = FlutterError(
                       code: "DECODE_FAILED",
                       message: "Failed to decode shared payload",
                       details: error.localizedDescription
                   )
                   eventSinkMedia?(err)
                   return true
               }
               clearPersistedShareMetadata(consumed: json)
               // CONCURRENCY (FSI-72): PHAsset resolution may take seconds on
               // iCloud downloads (isNetworkAccessAllowed = true). Resolving
               // asynchronously prevents main-thread stalls that can trigger
               // the iOS app watchdog (8–20s kill).
               resolveSharedFiles(sharedArray: sharedArray, message: message) { [weak self] resolved in
                   guard let self = self else { return }
                   self.latestSharing = resolved
                   if setInitialData {
                       self.initialSharing = resolved
                   }
                   self.eventSinkMedia?(self.toJson(data: resolved))
               }
           }
           return true
       }

    /// Resolves a decoded `[SharingFile]` payload into a list with absolute
    /// paths substituted for PHAsset local identifiers. Runs PHAsset
    /// resolution asynchronously and invokes `completion` on the main queue
    /// once every item has been resolved (or determined to be missing).
    ///
    /// CONCURRENCY (FSI-72): each PHAsset request may block on an iCloud
    /// download; we fan out with `DispatchGroup` so the main thread stays
    /// responsive. Result order is preserved via an index-keyed table —
    /// PHImageManager completions fire on an arbitrary queue, so the
    /// shared table is guarded by `NSLock`.
    private func resolveSharedFiles(
        sharedArray: [SharingFile],
        message: String?,
        completion: @escaping ([SharingFile]) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var resolvedByIndex: [Int: SharingFile] = [:]

        for (index, item) in sharedArray.enumerated() {
            group.enter()
            // Resolve the primary value (skip PHAsset lookup for text/url types).
            let resolveValue: (@escaping (String?) -> Void) -> Void = { cb in
                if item.type == .text || item.type == .url {
                    cb(item.value)
                } else {
                    self.getAbsolutePathAsync(for: item.value, completion: cb)
                }
            }

            resolveValue { resolvedValue in
                guard let value = resolvedValue else {
                    // Missing primary value — drop this item, preserving the
                    // historical `compactMap` behaviour.
                    group.leave()
                    return
                }
                self.getAbsolutePathAsync(for: item.thumbnail) { resolvedThumbnail in
                    let file = SharingFile(
                        value: value,
                        mimeType: item.mimeType,
                        thumbnail: resolvedThumbnail,
                        duration: item.duration,
                        type: item.type,
                        message: message
                    )
                    lock.lock()
                    resolvedByIndex[index] = file
                    lock.unlock()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            // Reassemble in the original order, dropping indexes where the
            // primary value failed to resolve.
            let ordered: [SharingFile] = (0..<sharedArray.count).compactMap { resolvedByIndex[$0] }
            completion(ordered)
        }
    }
    
//    private func handleUrl(url: URL?, setInitialData: Bool) -> Bool {
//        if let url = url {
//            let appGroupId = (Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String) ?? "group.\(Bundle.main.bundleIdentifier!)"
//            let userDefaults = UserDefaults(suiteName: appGroupId)
//            let message = userDefaults?.string(forKey: kUserDefaultsMessageKey)
//            if let json = userDefaults?.object(forKey: kUserDefaultsKey) as? Data {
//                print("SwiftFlutterSharingIntentPlugin : [handleUrl] \(json)")
//            }
//            if url.fragment == "media" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let json = userDefaults?.object(forKey: key) as? Data {
//                    let sharedArray = decode(data: json)
//                    
//                    let sharedMediaFiles: [SharingFile] = sharedArray.compactMap {
//                        guard let value = getAbsolutePath(for: $0.value) else {
//                            return nil
//                        }
//                        if ($0.type == .video && $0.thumbnail != nil) {
//                            let thumbnail = getAbsolutePath(for: $0.thumbnail!)
//                            return SharingFile.init(value: value, thumbnail: thumbnail, duration: $0.duration, type: $0.type)
//                        } else if ($0.type == .video && $0.thumbnail == nil) {
//                            return SharingFile.init(value: value, thumbnail: nil, duration: $0.duration, type: $0.type)
//                        }
//                        
//                        return SharingFile.init(value: value, thumbnail: nil, duration: $0.duration, type: $0.type)
//                    }
//                    latestSharing = sharedMediaFiles
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else if url.fragment == "file" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let json = userDefaults?.object(forKey: key) as? Data {
//                    let sharedArray = decode(data: json)
//                    let sharedMediaFiles: [SharingFile] = sharedArray.compactMap{
//                        guard getAbsolutePath(for: $0.value) != nil else {
//                            return nil
//                        }
//                        return SharingFile.init(value: $0.value,
//                                                thumbnail: nil, duration: nil,
//                                                type: $0.type)
//                    }
//                    latestSharing = sharedMediaFiles
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else if url.fragment == "url" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let sharedArray = userDefaults?.object(forKey: key) as? [String] {
//                    latestSharing = [SharingFile.init(value:  sharedArray.joined(separator: ","), thumbnail: nil, duration: nil, type:  SharingFileType.url)]
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else if url.fragment == "text" {
//                if let key = url.host?.components(separatedBy: "=").last,
//                   let sharedArray = userDefaults?.object(forKey: key) as? [String] {
//                    latestSharing = [SharingFile.init(value:  sharedArray.joined(separator: ","), thumbnail: nil, duration: nil, type: SharingFileType.text)]
//                    if(setInitialData) {
//                        initialSharing = latestSharing
//                    }
//                    eventSinkMedia?(toJson(data: latestSharing))
//                }
//            } else {
//                latestSharing = [SharingFile.init(value: url.absoluteString, thumbnail: nil, duration: nil, type: SharingFileType.text)]
//
//                if(setInitialData) {
//                    initialSharing = latestSharing
//                }
//                eventSinkMedia?(latestSharing)
//            }
//            return true
//        }
//        latestSharing = nil
//        return false
//    }
    
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if (arguments as! String? == "sharing" || arguments as! String? == "text" ) {
            eventSinkMedia = events;
        } else {
            return FlutterError.init(code: "NO_SUCH_ARGUMENT", message: "No such argument\(String(describing: arguments))", details: nil);
        }
        return nil;
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if (arguments as! String? == "sharing" || arguments as! String? == "text" ) {
            eventSinkMedia = nil;
        }  else {
            return FlutterError.init(code: "NO_SUCH_ARGUMENT", message: "No such argument as \(String(describing: arguments))", details: nil);
        }
        return nil;
    }
    
    /// Resolves a shared identifier to an absolute filesystem path,
    /// downloading iCloud-resident PHAssets as needed. Invokes `completion`
    /// with `nil` if the identifier is empty or the asset cannot be
    /// resolved.
    ///
    /// CONCURRENCY (FSI-72): replaces the previous synchronous
    /// `DispatchSemaphore`-blocked implementation, which could stall the
    /// main thread for tens of seconds on iCloud downloads and trigger the
    /// iOS app watchdog. `requestContentEditingInput` is inherently async;
    /// we now honour that shape instead of forcing it back to sync.
    ///
    /// The `completion` closure may fire on an arbitrary PHImageManager
    /// queue; callers are responsible for synchronising any shared state
    /// they mutate inside the callback.
    private func getAbsolutePathAsync(for identifier: String?, completion: @escaping (String?) -> Void) {
        guard let identifier else {
            completion(nil)
            return
        }

        if (identifier.starts(with: "file://") || identifier.starts(with: "/var/mobile/Media") || identifier.starts(with: "/private/var/mobile")) {
            completion(Self.filePath(fromFileIdentifier: identifier))
            return
        }
        guard let phAsset = PHAsset.fetchAssets(
                 withLocalIdentifiers: [identifier],
                 options: .none).firstObject else {
            completion(nil)
            return
        }

        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        phAsset.requestContentEditingInput(with: options) { (input, _) in
            completion(input?.fullSizeImageURL?.path)
        }
    }
    
    /// Converts a stored file identifier to a filesystem path. A `file://` URL
    /// is percent-decoded through `URL`, so a name with a space or non-ASCII
    /// characters maps to the file that was written; a malformed URL yields
    /// nil and the item is skipped (FSI-106). A plain path is returned as is.
    static func filePath(fromFileIdentifier identifier: String) -> String? {
        if identifier.hasPrefix("file://") { return URL(string: identifier)?.path }
        return identifier
    }

    /// Decodes the shared-file payload from the App Group UserDefaults blob.
    /// Throws on malformed / tampered input (FSI-61). The caller is responsible
    /// for surfacing the error to Dart via the event sink so the host app can
    /// distinguish "decode failed" from "no shares received".
    private func decode(data: Data) throws -> [SharingFile] {
        return try JSONDecoder().decode([SharingFile].self, from: data)
    }
    
    private func toJson(data: [SharingFile]?) -> String? {
        if data == nil {
            return nil
        }
        do {
            let encodedData = try JSONEncoder().encode(data)
            let json = String(data: encodedData, encoding: .utf8)!
            return json
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}


