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

    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: kAppChannel,binaryMessenger:registrar.messenger())

        registrar.addMethodCallDelegate(instance, channel: channel)

        let chargingChannelMedia = FlutterEventChannel(name: kEventsChannelMedia, binaryMessenger: registrar.messenger())
        chargingChannelMedia.setStreamHandler(instance)


        registrar.addApplicationDelegate(instance)
        // registrar.addMethodCallDelegate(instance, channel: channel)
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
            cleanupFiles(paths: paths)
            result(nil)

        default:
            result(FlutterMethodNotImplemented);
        }
    }

    /// Resolves the App Group container URL using the same precedence as
    /// the share extension: the `AppGroupId` Info.plist key if set, otherwise
    /// the conventional `group.<host-bundle-id>` identifier.
    private func appGroupContainerURL() -> URL? {
        let custom = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        let appGroupId = custom ?? "group.\(Bundle.main.bundleIdentifier ?? "")"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    /// Deletes shared-file copies from the App Group container after the host
    /// app has processed them (FSI-31). Best-effort: per-file errors are logged
    /// and swallowed; the method never throws back to Dart. Only file paths
    /// that are inside the configured App Group container are accepted —
    /// refuses to delete outside the container as a defensive check.
    private func cleanupFiles(paths: [String]) {
        guard let groupUrl = self.appGroupContainerURL() else {
            NSLog("[FSI] cleanup: no App Group container URL available")
            return
        }
        let containerPath = groupUrl.path
        let fm = FileManager.default
        for p in paths {
            // SECURITY: only delete under our App Group container (FSI-31).
            // Defends against a caller passing paths outside the container,
            // which could otherwise trick the plugin into deleting arbitrary
            // files the host app has read access to.
            guard p.hasPrefix(containerPath) else {
                NSLog("[FSI] cleanup: refusing to delete outside container: \(p)")
                continue
            }
            do {
                try fm.removeItem(atPath: p)
            } catch {
                NSLog("[FSI] cleanup failed for \(p): \(error.localizedDescription)")
            }
        }
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
               let sharedArray: [SharingFile]
               do {
                   sharedArray = try decode(data: json)
               } catch {
                   // FSI-61: surface decode failures (e.g. tampered / corrupted
                   // App Group UserDefaults) to Dart instead of silently
                   // returning an empty list, which is indistinguishable from
                   // "no shares received" and hides lateral-movement tampering.
                   NSLog("[FSI] decode failed: \(error.localizedDescription)")
                   let err = FlutterError(
                       code: "DECODE_FAILED",
                       message: "Failed to decode shared payload",
                       details: error.localizedDescription
                   )
                   eventSinkMedia?(err)
                   return true
               }
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
            completion(identifier.replacingOccurrences(of: "file://", with: ""))
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


