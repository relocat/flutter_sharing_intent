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
    
    // Results
    private var sharedMedia: [SharingFile] = []
    
    // Debug
    private let debugLogs = false

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
    
    open override func isContentValid() -> Bool {
        return true
    }
    
    open override func didSelectPost() {
        if self.sharedMedia.isEmpty {
            if let text = self.contentText, !text.isEmpty {
                self.sharedMedia.append(
                    SharingFile(value: text, thumbnail: nil, duration: nil, type: .text)
                )
                self.saveAndRedirect(message: text)
                return
            }
            self.completeAndExit()
        } else {
            self.saveAndRedirect()
        }
        // If the UI Post is used, save and redirect using contentText
//        saveAndRedirect(message: contentText)
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
        appGroupId = custom ?? "group.\(hostAppBundleIdentifier)"
        log("loaded host=\(hostAppBundleIdentifier) group=\(appGroupId)")
    }
    
    // MARK: - Attachment processing (clean RSI style, preserve FSI features)
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
                    self.handleImageItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isMovie {
                provider.loadItem(forTypeIdentifier: UType.movie, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleVideoItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isFile {
                provider.loadItem(forTypeIdentifier: UType.fileURL, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleFileItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isURL {
                provider.loadItem(forTypeIdentifier: UType.url, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleUrlItem(data: data, index: index, total: attachments.count)
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
                    self.handleTextItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isData {
                provider.loadItem(forTypeIdentifier: UType.data, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleFileItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
            
            if provider.isItem {
                provider.loadItem(forTypeIdentifier: UType.item, options: nil) { [weak self] data, error in
                    defer { group.leave() }
                    guard let self = self, error == nil else { self?.dismissWithError(); return }
                    self.handleFileItem(data: data, index: index, total: attachments.count)
                }
                continue
            }
                    
            log("Unknown provider type: \(provider.registeredTypeIdentifiers)")

            // Unknown type: just leave
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // if we have media -> media, else fallback to complete
            if !self.sharedMedia.isEmpty {
                self.saveAndRedirect()
            } else {
                self.log("No shared media → stopping.")
                self.completeAndExit()
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
                    try raw.write(to: dst)
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
                try d.write(to: dst)
                return SharingFile(value: dst.absoluteString, mimeType: "image/png", thumbnail: nil, duration: nil, type: .image)
            }
        } catch {
            log("writeTempImage error: \(error)")
        }
        removeShareDirectory(of: dst)
        return nil
    }
    
    
    private func saveAndRedirect(message: String? = nil) {
        let ud = UserDefaults(suiteName: appGroupId)
        if !sharedMedia.isEmpty {
            if let data = try? JSONEncoder().encode(sharedMedia) {
                ud?.set(data, forKey: kUserDefaultsKey)
            }
        }
        ud?.set(message, forKey: kUserDefaultsMessageKey)
        ud?.synchronize()
        redirectToHostApp()
    }
    
    
    private func redirectToHostApp() {
        // kept for compatibility (RSI style)
        loadIds()
        //        let raw = "\(kSchemePrefix)-\(hostAppBundleIdentifier):share"
        let raw = "\(kSchemePrefix)-\(hostAppBundleIdentifier)://dataUrl=\(kUserDefaultsKey)"
        guard let url = URL(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw) else { completeAndExit(); return }
        
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
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
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
        guard let container = containerURL() else { return nil }
        let directory = container
            .appendingPathComponent(Self.kShareRootName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log("newShareDestination error: \(error)")
            return nil
        }
        return directory.appendingPathComponent(name)
    }

    /// Removes the per-share directory that `fileURL` was meant to live in
    /// after a failed write, so a failed share leaves nothing behind.
    private func removeShareDirectory(of fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) { try FileManager.default.removeItem(at: dstURL) }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch {
            log("copyFile error: \(error)")
            removeShareDirectory(of: dstURL)
            return false
        }
    }
    
    private func getSharedMediaFile(forVideo: URL) -> SharingFile? {
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
                try data.write(to: thumbnailPath, options: .atomic)
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
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log("newThumbnailPath error: \(error)")
            return nil
        }
        return directory.appendingPathComponent("\(UUID().uuidString).jpg")
    }
    
    private func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
    
    private func completeAndExit() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func dismissWithError() {
        log("[ERROR] Error loading data!")
        let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in self.dismiss(animated: true, completion: nil) })
        present(alert, animated: true, completion: nil)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) { try FileManager.default.removeItem(at: dstURL) }
            let pngData = image.pngData()
            try pngData?.write(to: dstURL)
            return true
        } catch (let error) {
            log("writeTempFile error: \(error)")
            return false
        }
    }
    
    private func saveToUserDefaults(data: [SharingFile]) {
        let ud = UserDefaults(suiteName: appGroupId)
        if let enc = try? JSONEncoder().encode(data) { ud?.set(enc, forKey: kUserDefaultsKey); ud?.synchronize() }
    }
    
    // MARK: - Logging
    private func log(_ s: String) { if debugLogs { print("[FSIShareVC] \(s)") } }

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
    // Body wrapped in #if DEBUG so production builds cannot leak
    // user-supplied filenames, MIME types, or thumbnail paths to the
    // system log via this helper. Preserves the API for development
    // use. Addresses R-SI-03 (see SECURITY_AUDIT.md).
    func toString() {
        #if DEBUG
        print("[SharingFile] \n\tvalue: \(self.value)\n\tthumbnail: \(self.thumbnail ?? "--" )\n\tduration: \(self.duration ?? 0)\n\ttype: \(self.type)\n\tmimeType: \(String(describing: self.mimeType))\n\tmessage: \(String(describing: self.message))")
        #endif
    }
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

