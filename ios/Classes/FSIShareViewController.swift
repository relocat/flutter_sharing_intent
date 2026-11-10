// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
// FSIShareViewController.swift
// Merged, optimized controller: uses RSI architecture with all FSI features preserved
// Uses model name `SharingFile` (same fields as SharedMediaFile) where `value` = path

import AVFoundation
import MobileCoreServices
import Social
import UIKit
import UniformTypeIdentifiers

public let kSchemePrefix = "SharingMedia"
public let kUserDefaultsKey = "SharingKey"
public let kUserDefaultsMessageKey = "SharingMessageKey"
public let kAppGroupIdKey = "AppGroupId"
public let kAppChannel = "flutter_sharing_intent"

// extension UIViewController {
//     func showToast(_ message: String, duration: Double = 2.0) {
//         let toastLabel = UILabel()
//         toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
//         toastLabel.textColor = UIColor.white
//         toastLabel.textAlignment = .center
//         toastLabel.font = UIFont.systemFont(ofSize: 14)
//         toastLabel.text = message
//         toastLabel.alpha = 0.0
//         toastLabel.numberOfLines = 0
//         toastLabel.layer.cornerRadius = 10
//         toastLabel.clipsToBounds = true
//
//         let maxWidthPercentage: CGFloat = 0.8
//         let maxMessageSize = CGSize(
//             width: self.view.bounds.size.width * maxWidthPercentage,
//             height: self.view.bounds.size.height * maxWidthPercentage
//         )
//
//         var expectedSize = toastLabel.sizeThatFits(maxMessageSize)
//         expectedSize.width += 24
//         expectedSize.height += 16
//
//         toastLabel.frame = CGRect(
//             x: (self.view.frame.size.width - expectedSize.width) / 2,
//             y: self.view.frame.size.height - expectedSize.height - 50,
//             width: expectedSize.width,
//             height: expectedSize.height
//         )
//
//         self.view.addSubview(toastLabel)
//
//         UIView.animate(withDuration: 0.5, animations: {
//             toastLabel.alpha = 1.0
//         }) { _ in
//             UIView.animate(withDuration: 0.5, delay: duration, options: .curveEaseOut, animations: {
//                 toastLabel.alpha = 0.0
//             }) { _ in
//                 toastLabel.removeFromSuperview()
//             }
//         }
//     }
// }

// @objc(FSIShareViewController)
@available(swift, introduced: 5.0)
open class FSIShareViewController: SLComposeServiceViewController {
    // MARK: - Config
    private(set) var hostAppBundleIdentifier: String = ""
    private(set) var appGroupId: String = ""
    
    // Results. `sharedMedia`, `stagedURLs` and `isFinished` are touched from the
    // main queue and from NSItemProvider callback queues, so ALL access goes
    // through `stateQueue`. The abort and completion flags are different: they
    // sit behind a small lock, so Cancel never waits for a copy that is running.
    private var sharedMedia: [SharingFile] = []
    private let stateQueue = DispatchQueue(label: "flutter_sharing_intent.share-state")
    
    // Debug
    private let debugLogs = false

    /// Everything this invocation wrote into the App Group container: per-share
    /// directories and thumbnails. On cancel or error all of it is deleted so no
    /// partially staged plaintext is left behind; on success it is kept, because
    /// the host app reads the files and deletes them afterwards.
    private var stagedURLs: [URL] = []

    /// Set (on `stateQueue`) when delivery was decided. Together with the abort
    /// flag it makes delivery ONE atomic decision: a share is handed to the host
    /// app at most once, and never after a cancel or error.
    private var isFinished = false

    /// Flags behind `flagLock`: the share was cancelled or failed (a load that
    /// finishes later stages nothing, and nothing is delivered), and the
    /// extension request was already completed (it is completed at most once).
    private let flagLock = NSLock()
    private var abortedFlag = false
    private var completedFlag = false

    /// Main-queue only: true once every load finished (or failed). Post is not
    /// valid before that, so a Post can only deliver a complete, settled set.
    private var hasSettledLoads = false

    /// Longest time Cancel waits for the cleanup of staged files. A copy that
    /// is still running is not waited for: it removes its own files when it
    /// notices the abort.
    private static let kCancelCleanupWaitSeconds = 2.0

    // MARK: - Security constants

    /// Plugin-level cap for raw Data payloads delivered by share extensions (FSI-92).
    /// Mirrors the Android plugin cap (16 MiB). Prevents an untrusted source app from
    /// exhausting the App Group container storage via an unbounded Data blob.
    private static let kMaxRawDataBytes = 16 * 1024 * 1024

    /// App Group container directory that holds one sub-directory per shared
    /// item, `<container>/flutter_sharing_intent/<UUID>/<name>` (FSI-105).
    /// Must match `SwiftFlutterSharingIntentPlugin.kShareRootName`: the plugin
    /// deletes only files of this shape.
    static let kShareRootName = "flutter_sharing_intent"

    /// App Group container directory for generated video thumbnails,
    /// `<container>/flutter_sharing_intent_thumbnails/<UUID>.jpg` (FSI-105).
    static let kThumbnailRootName = "flutter_sharing_intent_thumbnails"
    
    // MARK: - Lifecycle
    open override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
    }
    
    open override func didSelectCancel() {
        // Claim the completion FIRST. A lost claim means the share was already
        // delivered or already cleaned up after an error, so Cancel must not
        // delete anything.
        guard claimCompletion() else { return }
        // The base class does not clean up: mark the share aborted, so loads
        // still in flight stage nothing, then remove what is staged.
        abortAndCleanup()
        super.didSelectCancel()
    }

    open override func isContentValid() -> Bool {
        // Post is only allowed once all loads settled; see `hasSettledLoads`.
        return hasSettledLoads
    }
    
    open override func didSelectPost() {
        // Defense in depth beyond the UIKit gate in `isContentValid`: a Post
        // before every load settled does nothing.
        guard hasSettledLoads else { return }
        let isEmpty = stateQueue.sync(execute: { self.sharedMedia.isEmpty })
        if isEmpty {
            // Nothing was staged: no media means nothing to hand over.
            cleanupStagedFiles()
            self.completeAndExit()
        } else {
            self.saveAndRedirect()
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Process attachments automatically on appear like original FSI
        processAttachments()
    }
    
    // MARK: - Load Ids
    private func loadIds() {
        let shareExtId = Bundle.main.bundleIdentifier ?? ""
        if let idx = shareExtId.lastIndex(of: ".") {
            hostAppBundleIdentifier = String(shareExtId[..<idx])
        } else {
            hostAppBundleIdentifier = shareExtId
        }
        let custom = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        if custom == nil {
            // The derived group id stops matching the entitlement when the
            // bundle id changes (for example under enterprise re-signing); the
            // container URL is then nil and shares would be dropped silently.
            // Declare the id explicitly with the Info.plist key to avoid that.
            #if DEBUG
            print("[FSIShareVC] WARNING: Info.plist '\(kAppGroupIdKey)' missing; using derived app-group id")
            #endif
        }
        appGroupId = custom ?? "group.\(hostAppBundleIdentifier)"
        log("loaded host bundle id")
    }
    
    // MARK: - Attachment processing (clean RSI style, preserve FSI features)
    //
    // Residual: this layer cannot reject a share that comes from the host app
    // itself. Items arrive as local file URLs with no source-provider authority,
    // so the check has to happen in the host app's Dart layer.
    private func processAttachments() {
        guard let content = extensionContext?.inputItems.first as? NSExtensionItem else {
            completeAndExit()
            return
        }
        
        guard let attachments = content.attachments, !attachments.isEmpty else {
            completeAndExit()
            return
        }
        
        // Use DispatchGroup to wait for async loads
        let group = DispatchGroup()
        for (index, provider) in attachments.enumerated() {
            group.enter()
            // Try all SharedMediaType options similar to RSI but preserve explicit FSI order
            if provider.isImage {
                provider.loadItem(forTypeIdentifier: UType.image, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleImageItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
            
            if provider.isMovie {
                provider.loadItem(forTypeIdentifier: UType.movie, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleVideoItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
            
            if provider.isFile {
                provider.loadItem(forTypeIdentifier: UType.fileURL, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleFileItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
            
            if provider.isURL {
                provider.loadItem(forTypeIdentifier: UType.url, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleUrlItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
            
            if provider.isText {
                let id = provider.hasItemConformingToTypeIdentifier(UType.plainText)
                ? UType.plainText
                : UType.text
                provider.loadItem(forTypeIdentifier: id, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleTextItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
            
            if provider.isData {
                provider.loadItem(forTypeIdentifier: UType.data, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleFileItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
            
            if provider.isItem {
                provider.loadItem(forTypeIdentifier: UType.item, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.stageOnStateQueue { self.handleFileItem(data: data, index: index, total: attachments.count) }
                }
                continue
            }
                    
            log("Unknown provider type: \(provider.registeredTypeIdentifiers)")

            // Unknown type: just leave
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.hasSettledLoads = true
            self.validateContent()
            // A cancelled or failed share is never delivered.
            if self.isAbortedNow {
                self.cleanupStagedFiles()
                return
            }
            // if we have media -> media, else fallback to complete
            if !self.stateQueue.sync(execute: { self.sharedMedia.isEmpty }) {
                self.saveAndRedirect()
            } else {
                self.log("No shared media → stopping.")
                self.cleanupStagedFiles()
                self.completeAndExit()
            }
        }
    }

    /// Runs one load handler on the state queue. Handlers stage files and append
    /// to the shared lists, so they are serialised with delivery; a handler that
    /// starts after an abort, or after delivery, does nothing. If the share was
    /// aborted while the handler was copying, everything the handler staged is
    /// removed again before it returns.
    private func stageOnStateQueue(_ handler: () -> Void) {
        stateQueue.sync {
            if isAbortedNow || isFinished { return }
            let stagedBefore = stagedURLs.count
            let mediaBefore = sharedMedia.count
            handler()
            if isAbortedNow {
                Self.removeStagedItems(Array(stagedURLs[stagedBefore...]))
                stagedURLs.removeSubrange(stagedBefore...)
                sharedMedia.removeSubrange(mediaBefore...)
            }
        }
    }

    // MARK: - Individual handlers (preserve FSI behavior)
    private func handleTextItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let s = data as? String {
            sharedMedia.append(SharingFile(value: s, thumbnail: nil, duration: nil, type: .text))
        } else if let url = data as? URL {
            sharedMedia.append(SharingFile(value: url.absoluteString, thumbnail: nil, duration: nil, type: .url))
        }
        
    }
    
    private func handleUrlItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let url = data as? URL {
            sharedMedia.append(SharingFile(value: url.absoluteString, thumbnail: nil, duration: nil, type: .url))
        } else if let s = data as? String {
            sharedMedia.append(SharingFile(value: s, thumbnail: nil, duration: nil, type: .text))
        }
        
    }
    
    private func handleImageItem(data: NSSecureCoding?, index: Int, total: Int) {
        // data can be URL, UIImage, or Data
        if let url = data as? URL {
            let filename = getFileName(from: url, type: .image)
            if let dst = newShareDestination(named: filename) {
                if copyFile(at: url, to: dst) {
                    sharedMedia.append(SharingFile(value: dst.absoluteString, mimeType: url.mimeType(), thumbnail: nil, duration: nil, type: .image))
                }
            }
        } else if let img = data as? UIImage {
            if let saved = writeTempImage(img) {
                sharedMedia.append(saved)
            }
        } else if let raw = data as? Data, let img = UIImage(data: raw) {
            if let saved = writeTempImage(img) {
                sharedMedia.append(saved)
            }
        }
        
    }
    
    private func handleVideoItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let url = data as? URL {
            let filename = getFileName(from: url, type: .video)
            if let dst = newShareDestination(named: filename) {
                if copyFile(at: url, to: dst) {
                    if let m = getSharedMediaFile(forVideo: dst) {
                        sharedMedia.append(m)
                    }
                }
            }
        }
        
    }
    
    private func handleFileItem(data: NSSecureCoding?, index: Int, total: Int) {
        if let url = data as? URL {
            let filename = getFileName(from: url, type: .file)
            if let dst = newShareDestination(named: filename) {
                if copyFile(at: url, to: dst) {
                    sharedMedia.append(SharingFile(value: dst.absoluteString, mimeType: url.mimeType(), thumbnail: nil, duration: nil, type: .file))
                }
            }
        }
        else if let raw = data as? Data {
            // SECURITY (FSI-92): Reject oversized raw Data payloads to prevent
            // App Group container storage exhaustion by an untrusted source app.
            guard raw.count <= Self.kMaxRawDataBytes else {
                self.log("oversize Data payload rejected (\(raw.count) bytes > \(Self.kMaxRawDataBytes) limit)")
                return
            }
            let filename = "File_\(UUID().uuidString)"
            if let dst = newShareDestination(named: filename) {
                do {
                    try raw.write(to: dst, options: .completeFileProtection)
                    sharedMedia.append(SharingFile(value: dst.absoluteString, mimeType: "application/octet-stream", thumbnail: nil, duration: nil, type: .file))
                } catch {
                    removeShareDirectory(of: dst)
                }
            }
        }
        
        
    }
    
    // MARK: - Helpers: write temp image
    private func writeTempImage(_ image: UIImage) -> SharingFile? {
        let tempName = "TempImage_\(UUID().uuidString).png"
        guard let dst = newShareDestination(named: tempName) else { return nil }
        do {
            if let d = image.pngData() {
                try d.write(to: dst, options: .completeFileProtection)
                return SharingFile(value: dst.absoluteString, mimeType: "image/png", thumbnail: nil, duration: nil, type: .image)
            }
        } catch {
            log("writeTempImage error: \(error)")
        }
        removeShareDirectory(of: dst)
        return nil
    }
    
    
    /// What the single delivery decision produced.
    private enum Delivery {
        case deliver([SharingFile])
        case drop
        case alreadyDelivered
    }

    /// The ONE place where delivery is decided, atomically on the state queue:
    /// a share that was aborted is dropped, a share that was already delivered
    /// is left alone, and otherwise the share is marked finished and its media
    /// returned.
    private func decideDelivery() -> Delivery {
        return stateQueue.sync { () -> Delivery in
            if isFinished { return .alreadyDelivered }
            isFinished = true
            guard !isAbortedNow else { return .drop }
            return .deliver(sharedMedia)
        }
    }

    private func saveAndRedirect() {
        let media: [SharingFile]
        switch decideDelivery() {
        case .alreadyDelivered:
            return
        case .drop:
            cleanupStagedFiles()
            completeAndExit()
            return
        case .deliver(let delivered):
            media = delivered
        }
        // The redirect URL is computed BEFORE anything is written to the shared
        // defaults, so a failure leaves neither a payload nor staged files.
        guard let url = redirectURL() else {
            cleanupStagedFiles()
            completeAndExit()
            return
        }
        guard let ud = UserDefaults(suiteName: appGroupId) else {
            cleanupStagedFiles()
            completeAndExit()
            return
        }
        if !media.isEmpty {
            guard let data = try? JSONEncoder().encode(media) else {
                cleanupStagedFiles()
                completeAndExit()
                return
            }
            ud.set(data, forKey: kUserDefaultsKey)
        }
        ud.removeObject(forKey: kUserDefaultsMessageKey)
        ud.synchronize()
        redirectToHostApp(url)
    }

    /// The URL that opens the host app. The bundle id is embedded in a URL
    /// scheme, so it is encoded with a strict character set first. Returns nil
    /// if encoding is impossible; the raw id is never used, because it could
    /// inject separators.
    private func redirectURL() -> URL? {
        guard let safeHost = Self.schemeSafeHost(hostAppBundleIdentifier) else { return nil }
        return URL(string: "\(kSchemePrefix)-\(safeHost)://dataUrl=\(kUserDefaultsKey)")
    }

    private func redirectToHostApp(_ url: URL) {
        var responder: UIResponder? = self
        if #available(iOS 18.0, *) {
            while responder != nil {
                if let app = responder as? UIApplication { app.open(url, options: [:], completionHandler: nil) }
                responder = responder?.next
            }
        } else {
            let sel = sel_registerName("openURL:")
            while responder != nil {
                if responder?.responds(to: sel) ?? false { _ = responder?.perform(sel, with: url) }
                responder = responder?.next
            }
        }
        completeRequestOnce()
    }
    
    // MARK: - File / thumbnail / metadata helpers
    func getExtension(from url: URL, type: SharingFileType) -> String {
        let parts = url.lastPathComponent.components(separatedBy: ".")
        var ex: String? = nil
        if parts.count > 1 { ex = parts.last }
        if ex == nil {
            switch type {
            case .image: ex = "png"
            case .video: ex = "mp4"
            case .file: ex = "txt"
            case .text: ex = "txt"
            case .url: ex = "txt"
            }
        }
        return ex ?? "bin"
    }
    
    func getFileName(from url: URL, type: SharingFileType) -> String {
        // SECURITY (FSI-93): url.lastPathComponent is sender-controlled.
        // Sanitize before using as a destination filename in the App Group container.
        let raw = url.lastPathComponent
        if raw.isEmpty {
            return UUID().uuidString + "." + getExtension(from: url, type: type)
        }
        return sanitizedComponent(raw)
    }
    
    /// Creates a fresh per-share directory,
    /// `<container>/flutter_sharing_intent/<UUID>/`, and returns the URL of
    /// `name` inside it (FSI-105). Every shared item gets its own directory,
    /// so the host app's cleanup can remove exactly what the plugin wrote.
    func newShareDestination(named name: String) -> URL? {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard let container = containerURL() else { return nil }
        let root = container.appendingPathComponent(Self.kShareRootName, isDirectory: true)
        // A symbolic link in place of the plugin directory is refused: staging
        // through it would write outside the container.
        guard Self.isUsableRoot(root) else {
            log("newShareDestination: plugin directory is not a real directory")
            return nil
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            // Files created inside inherit the directory's protection class.
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
        } catch {
            log("newShareDestination error: \(error)")
            return nil
        }
        stagedURLs.append(directory)
        return directory.appendingPathComponent(name)
    }

    /// True only if `url` does not exist (it will be created) or is a real
    /// directory by `lstat`. A symbolic link, any other file type, and ANY error
    /// other than "no such file" (for example a permission error) give false.
    static func isUsableRoot(_ url: URL) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.type] as? FileAttributeType) == .typeDirectory
        } catch {
            let nsError = error as NSError
            let isCocoaMissing = nsError.domain == NSCocoaErrorDomain
                && (nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError)
            let isPosixMissing = nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
            return isCocoaMissing || isPosixMissing
        }
    }

    /// True only if what exists at `url` is a regular file according to `lstat`
    /// (not a symbolic link, directory or special file). Used after a copy to
    /// verify what was actually created.
    static func isRegularFileOnDisk(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return (attributes[.type] as? FileAttributeType) == .typeRegular
    }

    /// True only for a regular file that is not a symbolic link. Directories and
    /// links are never copied: the plugin's cleanup removes regular files only,
    /// so a copied directory or link would be left behind.
    static func isCopyableRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    /// Removes the per-share directory that `fileURL` was meant to live in
    /// after a failed write, so a failed share leaves nothing behind.
    private func removeShareDirectory(of fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    /// Raises the data-protection class of a staged App Group file to
    /// `.complete`, so the plaintext is unreadable while the device is locked
    /// (the extension runs with the screen on; the host app reads on
    /// foreground). Throws on failure: a file that cannot be protected is not
    /// shared.
    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path)
    }

    func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        guard Self.isCopyableRegularFile(srcURL) else {
            log("copyFile: source is not a regular file")
            removeShareDirectory(of: dstURL)
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) { try FileManager.default.removeItem(at: dstURL) }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            // Re-check what was actually created (the source could have changed
            // after the first check): only a regular file may stay.
            guard Self.isRegularFileOnDisk(dstURL) else {
                removeShareDirectory(of: dstURL)
                return false
            }
            try protect(dstURL)
            return true
        } catch {
            log("copyFile error: \(error)")
            removeShareDirectory(of: dstURL)
            return false
        }
    }
    
    private func getSharedMediaFile(forVideo: URL) -> SharingFile? {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        let asset = AVAsset(url: forVideo)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        guard let thumbnailPath = newThumbnailPath() else {
            return SharingFile(value: forVideo.absoluteString, mimeType: forVideo.mimeType(), thumbnail: nil, duration: Int(duration), type: .video)
        }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 360, height: 360)
        
        // Use first second or zero
        let time = CMTime(seconds: min(1.0, CMTimeGetSeconds(asset.duration)), preferredTimescale: 600)
        do {
            let cg = try gen.copyCGImage(at: time, actualTime: nil)
            if let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) {
                // Protected like every staged file. The thumbnail is removed on
                // cancel or error; on success the host app only learns the path
                // through the payload, so it deletes it with `cleanup`.
                try data.write(to: thumbnailPath, options: [.atomic, .completeFileProtection])
                stagedURLs.append(thumbnailPath)
                return SharingFile(value: forVideo.absoluteString, mimeType: forVideo.mimeType(), thumbnail: thumbnailPath.absoluteString, duration: Int(duration), type: .video)
            }
        } catch {
            log("getSharedMediaFile thumbnail error: \(error)")
            // A failed write can leave a partial file: remove it (FSI-106).
            try? FileManager.default.removeItem(at: thumbnailPath)
        }
        
        // fallback
        return SharingFile(value: forVideo.absoluteString, mimeType: forVideo.mimeType(), thumbnail: nil, duration: Int(duration), type: .video)
    }
    
    /// Returns a fresh `<container>/flutter_sharing_intent_thumbnails/<UUID>.jpg`
    /// URL, creating the thumbnail root if needed (FSI-105). Returns nil when
    /// the root cannot be created; the video is then shared without a thumbnail.
    private func newThumbnailPath() -> URL? {
        guard let container = containerURL() else { return nil }
        let directory = container.appendingPathComponent(Self.kThumbnailRootName, isDirectory: true)
        guard Self.isUsableRoot(directory) else {
            log("newThumbnailPath: thumbnail directory is not a real directory")
            return nil
        }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
        } catch {
            log("newThumbnailPath error: \(error)")
            return nil
        }
        return directory.appendingPathComponent("\(UUID().uuidString).jpg")
    }

    /// Percent-encodes a bundle identifier for use inside a URL scheme, keeping
    /// only letters, digits, `.` and `-`. `.urlQueryAllowed` would leave `:` and
    /// `/` untouched, which could inject scheme or authority separators. Returns
    /// nil when the identifier cannot be encoded (for example a lone surrogate).
    static func schemeSafeHost(_ bundleIdentifier: String) -> String? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        return bundleIdentifier.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    private func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
    
    private func completeAndExit() {
        completeRequestOnce()
    }

    /// True once the share was cancelled or failed. Lock-protected, so it can
    /// be read from any queue without waiting for the state queue.
    private var isAbortedNow: Bool {
        flagLock.lock()
        defer { flagLock.unlock() }
        return abortedFlag
    }

    /// Marks the share aborted. Returns false if it already was.
    private func markAborted() -> Bool {
        flagLock.lock()
        defer { flagLock.unlock() }
        let isFirst = !abortedFlag
        abortedFlag = true
        return isFirst
    }

    /// Completes the extension request exactly once, whichever path gets here
    /// first (success, error alert, cancel).
    private func completeRequestOnce() {
        if claimCompletion() {
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// Claims the right to complete the request. Returns true for the first
    /// caller only.
    private func claimCompletion() -> Bool {
        flagLock.lock()
        defer { flagLock.unlock() }
        let isFirst = !completedFlag
        completedFlag = true
        return isFirst
    }
    
    /// Deletes everything this invocation staged. Used on cancel, error and
    /// when nothing is delivered; on success the host app needs the files.
    private func cleanupStagedFiles() {
        stateQueue.sync {
            Self.removeStagedItems(stagedURLs)
            stagedURLs.removeAll()
        }
    }

    /// Marks the share aborted, THEN deletes everything staged. The flag is set
    /// without touching the state queue, so Cancel never waits for a running
    /// copy; the deletion then runs on the state queue and Cancel waits for it
    /// only for a bounded time. A handler that is still copying notices the flag
    /// and removes its own files. Returns false if the share was already aborted.
    @discardableResult
    private func abortAndCleanup() -> Bool {
        let isFirstAbort = markAborted()
        let done = DispatchSemaphore(value: 0)
        stateQueue.async {
            Self.removeStagedItems(self.stagedURLs)
            self.stagedURLs.removeAll()
            self.sharedMedia.removeAll()
            done.signal()
        }
        _ = done.wait(timeout: .now() + Self.kCancelCleanupWaitSeconds)
        return isFirstAbort
    }

    /// Removes every staged item (per-share directories and thumbnails). An
    /// item that is already gone is skipped. The URLs are ones this invocation
    /// created, so the removal is recursive on purpose; symbolic links inside
    /// are removed as links and never followed.
    static func removeStagedItems(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func dismissWithError() {
        guard abortAndCleanup() else { return }
        log("[ERROR] Error loading data!")
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in self.dismiss(animated: true, completion: nil) })
            self.present(alert, animated: true, completion: nil)
            self.completeRequestOnce()
        }
    }
    
    // The UserDefaults(suiteName:) plist that carries the staged paths and MIME
    // types has the OS default protection class (readable after first unlock).
    // Instead of replacing this hand-off, the plugin deletes the keys the moment
    // it reads them (FSI-95), which shortens the on-disk window to the hand-off
    // itself, while the device is unlocked. The file contents are written with
    // complete file protection. Residual: the plist is briefly at the default
    // class during that window.
    private func saveToUserDefaults(data: [SharingFile]) {
        let ud = UserDefaults(suiteName: appGroupId)
        if let enc = try? JSONEncoder().encode(data) { ud?.set(enc, forKey: kUserDefaultsKey); ud?.synchronize() }
    }
    
    // MARK: - Logging
    // Compiled out of release builds entirely, not only gated by `debugLogs`.
    private func log(_ s: String) {
        #if DEBUG
        if debugLogs { print("[FSIShareVC] \(s)") }
        #endif
    }

    // MARK: - Path safety

    /// Sanitize a URL path component so it is safe to use as a filename in
    /// the App Group container (FSI-93).
    ///
    /// Rules applied in order:
    /// 1. Strip "/" path separators and control characters: NUL and the rest
    ///    of C0 (U+0000-U+001F), DEL (U+007F) and C1 (U+0080-U+009F).
    /// 2. Cap at 255 bytes in UTF-8 (POSIX NAME\_MAX), cutting only between
    ///    whole Characters (extended grapheme clusters).
    /// 3. Return "unnamed" for an empty or blank result, and for "." and "..".
    ///
    /// - Parameter raw: The raw string (typically `url.lastPathComponent`).
    /// - Returns: A safe, non-empty filename component.
    private func sanitizedComponent(_ raw: String) -> String {
        let maxBytes = 255 // POSIX NAME_MAX

        // Step 1: a Swift String can contain U+0000, so NUL is stripped
        // explicitly together with the other control characters. Filtering
        // works on whole Unicode scalars and never splits one.
        let keptScalars = raw.unicodeScalars.filter { scalar in
            let v = scalar.value
            if scalar == "/" { return false }
            if v <= 0x1F { return false }              // NUL and C0
            if v >= 0x7F && v <= 0x9F { return false } // DEL and C1
            return true
        }
        var stripped = ""
        stripped.unicodeScalars.append(contentsOf: keptScalars)

        // Step 2: keep whole Characters while they fit in maxBytes of UTF-8.
        // The result is a prefix of valid Characters, so it is valid UTF-8,
        // contains no U+FFFD and never separates a combining mark or an emoji
        // sequence from the rest of its Character. A single Character longer
        // than maxBytes yields an empty result, which step 3 replaces.
        var truncated = ""
        var usedBytes = 0
        for character in stripped {
            let size = character.utf8.count
            if usedBytes + size > maxBytes { break }
            truncated.append(character)
            usedBytes += size
        }

        // Step 3: reject empty, blank and dot-only special names.
        if truncated.trimmingCharacters(in: .whitespaces).isEmpty
            || truncated == "." || truncated == ".." {
            return "unnamed"
        }
        return truncated
    }

}

// MARK: - Extensions
extension URL {
    func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let ut = UTType(filenameExtension: self.pathExtension), let m = ut.preferredMIMEType { return m }
        } else {
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.pathExtension as NSString, nil)?.takeRetainedValue() {
                if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() { return mimetype as String }
            }
        }
        return "application/octet-stream"
    }
}

extension NSItemProvider {
    var isImage: Bool { return hasItemConformingToTypeIdentifier(UType.image) }
    var isMovie: Bool { return hasItemConformingToTypeIdentifier(UType.movie) }
    var isText: Bool {
        hasItemConformingToTypeIdentifier(UType.plainText) || hasItemConformingToTypeIdentifier(UType.text)
    }
    var isURL: Bool { return hasItemConformingToTypeIdentifier(UType.url) }
    var isFile: Bool { return hasItemConformingToTypeIdentifier(UType.fileURL) }
    var isData:Bool { return hasItemConformingToTypeIdentifier(UType.data) }
    var isItem: Bool { hasItemConformingToTypeIdentifier(UType.item) }

}

extension Array {
    subscript(safe index: UInt) -> Element? { return Int(index) < count ? self[Int(index)] : nil }
}


class SharingFile: Codable {
    var value: String
    var mimeType: String?
    var thumbnail: String?; // video thumbnail
    var duration: Int?; // video duration in milliseconds
    var type: SharingFileType;
    var message: String? // post message
    
    enum CodingKeys: String, CodingKey {
        case value
        case mimeType
        case thumbnail
        case duration
        case type
        case message
    }
    
    init(value: String, mimeType: String? = nil, thumbnail: String?, duration: Int?,
         type: SharingFileType, message: String?=nil) {
        self.value = value
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.duration = duration
        self.type = type
        self.message = message
    }
    
    // Debug method to print out SharedMediaFile details in the console.
    //
    // The whole declaration is DEBUG-only and private, so a release build cannot
    // leak file names, MIME types or thumbnail paths through it, even via a stray
    // caller (R-SI-03, see SECURITY_AUDIT.md).
    #if DEBUG
    private func toString() {
        print("[SharingFile] \n\tvalue: \(self.value)\n\tthumbnail: \(self.thumbnail ?? "--" )\n\tduration: \(self.duration ?? 0)\n\ttype: \(self.type)\n\tmimeType: \(String(describing: self.mimeType))\n\tmessage: \(String(describing: self.message))")
    }
    #endif
}


enum SharingFileType: Int, Codable {
    case text
    case url
    case image
    case video
    case file
}

// Unified UTType → works on iOS 11–18
enum UType {
    static var image: String {
        if #available(iOS 14.0, *) {
            return UTType.image.identifier
        } else {
            return kUTTypeImage as String   // old API
        }
    }
    
    static var movie: String {
        if #available(iOS 14.0, *) {
            return UTType.movie.identifier
        } else {
            return kUTTypeMovie as String
        }
    }
    
    
    static var url: String {
        if #available(iOS 14.0, *) {
            return UTType.url.identifier
        } else {
            return kUTTypeURL as String
        }
    }
    
    static var fileURL: String {
        if #available(iOS 14.0, *) {
            return UTType.fileURL.identifier
        } else {
            return kUTTypeFileURL as String
        }
    }
    
    static var text: String {
        if #available(iOS 14.0, *) {
            return UTType.text.identifier
        } else {
            return kUTTypeText as String
        }
    }
    
    static var plainText: String {
        if #available(iOS 14.0, *) {
            return UTType.plainText.identifier
        } else {
            return kUTTypePlainText as String
        }
    }
    
    static var data: String {
        if #available(iOS 14.0, *) {
            return UTType.data.identifier
        } else {
            return kUTTypeData as String
        }
    }
    
    static var item: String {
        if #available(iOS 14.0, *) {
            return UTType.item.identifier
        } else {
            return kUTTypeItem as String
        }
    }
}

