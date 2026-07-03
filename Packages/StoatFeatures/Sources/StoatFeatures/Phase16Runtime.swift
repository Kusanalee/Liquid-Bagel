import CryptoKit
import Foundation
import StoatAPI
import StoatModels
import StoatUI

#if canImport(AppKit)
import AppKit
#endif

public enum RemoteAttachmentLoadPurpose: Hashable, Sendable {
    case preview
    case original
}

public enum ImageResourceKind: Hashable, Sendable {
    case attachmentPreview
    case attachmentOriginal
    case userAvatar
    case serverIcon
    case serverBanner
    case profileBackground
    case customEmoji
}

public struct ImageCacheKey: Hashable, Sendable, CustomStringConvertible {
    public var id: String
    public var kind: ImageResourceKind

    public init(id: String, kind: ImageResourceKind) {
        self.id = id
        self.kind = kind
    }

    public var description: String {
        "\(kind)-\(AttachmentDisplayFormatting.shortID(id))"
    }
}

public struct ImageResourceRequest: Hashable, Sendable {
    public var id: String
    public var url: URL
    public var kind: ImageResourceKind
    public var maxBytes: Int
    public var filename: String?

    public init(id: String, url: URL, kind: ImageResourceKind, maxBytes: Int, filename: String? = nil) {
        self.id = id
        self.url = url
        self.kind = kind
        self.maxBytes = maxBytes
        self.filename = filename
    }

    public var cacheKey: ImageCacheKey {
        ImageCacheKey(id: id, kind: kind)
    }
}

public struct ImageResourceResult: Hashable, Sendable {
    public var request: ImageResourceRequest
    public var contentType: String?
    public var data: Data
    public var fromCache: Bool

    public init(request: ImageResourceRequest, contentType: String? = nil, data: Data, fromCache: Bool = false) {
        self.request = request
        self.contentType = AttachmentDisplayFormatting.safeContentType(contentType)
        self.data = data
        self.fromCache = fromCache
    }
}

public protocol ImageResourceLoading: Sendable {
    func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult
}

public struct ImageMemoryCacheSnapshot: Hashable, Sendable {
    public var count: Int
    public var byteCount: Int
}

public actor ImageMemoryCache {
    private struct Entry: Sendable {
        var data: Data
        var lastAccess: UInt64
    }

    private var entries: [ImageCacheKey: Entry] = [:]
    private var currentBytes = 0
    private var clock: UInt64 = 0
    private let maxEntries: Int
    private let maxBytes: Int

    public init(maxEntries: Int = 512, maxBytes: Int = 32 * 1024 * 1024) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
    }

    public func imageData(for key: ImageCacheKey) -> Data? {
        guard var entry = entries[key] else { return nil }
        clock += 1
        entry.lastAccess = clock
        entries[key] = entry
        return entry.data
    }

    public func store(_ data: Data, for key: ImageCacheKey) {
        guard data.count <= maxBytes else { return }
        if let existing = entries[key] {
            currentBytes -= existing.data.count
        }
        clock += 1
        entries[key] = Entry(data: data, lastAccess: clock)
        currentBytes += data.count
        evictIfNeeded()
    }

    public func removeAll() {
        entries.removeAll()
        currentBytes = 0
    }

    public func remove(_ key: ImageCacheKey) {
        guard let existing = entries.removeValue(forKey: key) else { return }
        currentBytes -= existing.data.count
    }

    public func snapshot() -> ImageMemoryCacheSnapshot {
        ImageMemoryCacheSnapshot(count: entries.count, byteCount: currentBytes)
    }

    private func evictIfNeeded() {
        while entries.count > maxEntries || currentBytes > maxBytes {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { return }
            entries.removeValue(forKey: oldest.key)
            currentBytes -= oldest.value.data.count
        }
    }
}

public protocol ImageDiskCaching: Sendable {
    func data(for key: ImageCacheKey) async -> Data?
    func store(_ data: Data, for key: ImageCacheKey) async
    func removeAll() async
}

public struct NoopImageDiskCache: ImageDiskCaching {
    public init() {}

    public func data(for key: ImageCacheKey) async -> Data? { nil }
    public func store(_ data: Data, for key: ImageCacheKey) async {}
    public func removeAll() async {}
}

public actor FileImageDiskCache: ImageDiskCaching {
    private let directory: URL
    private let maxBytes: Int
    private var isPrepared = false
    /// Running total of bytes on disk, seeded lazily by one directory scan and maintained
    /// incrementally thereafter so `store` doesn't have to re-enumerate the whole cache
    /// directory (with a `resourceValues` stat per file) on every single call.
    private var totalBytes: Int?

    public init(directory: URL? = nil, maxBytes: Int = 256 * 1024 * 1024) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("LiquidBagel/ImageCache", isDirectory: true)
        }
        self.maxBytes = max(1, maxBytes)
    }

    public func data(for key: ImageCacheKey) async -> Data? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public func store(_ data: Data, for key: ImageCacheKey) async {
        guard data.count <= maxBytes else { return }
        prepareIfNeeded()
        seedByteCountIfNeeded()
        let url = fileURL(for: key)
        let previousSize = existingFileSize(at: url)
        try? data.write(to: url, options: .atomic)
        totalBytes = (totalBytes ?? 0) - previousSize + data.count
        evictIfNeeded()
    }

    public func removeAll() async {
        try? FileManager.default.removeItem(at: directory)
        isPrepared = false
        totalBytes = 0
    }

    /// Current known cache size in bytes, for diagnostics/tests. Triggers the lazy seed scan
    /// if it hasn't run yet.
    public func byteCount() async -> Int {
        seedByteCountIfNeeded()
        return totalBytes ?? 0
    }

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        isPrepared = true
    }

    private func fileURL(for key: ImageCacheKey) -> URL {
        let digest = SHA256.hash(data: Data("\(key.kind)|\(key.id)".utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(name).img", isDirectory: false)
    }

    private func existingFileSize(at url: URL) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int
        else { return 0 }
        return size
    }

    private func seedByteCountIfNeeded() {
        guard totalBytes == nil else { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            totalBytes = 0
            return
        }
        totalBytes = urls.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + size
        }
    }

    private func evictIfNeeded() {
        guard let currentTotal = totalBytes, currentTotal > maxBytes else { return }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, size: Int, modified: Date)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        entries.sort { $0.modified < $1.modified }
        var runningTotal = currentTotal
        let evictionTarget = Int(Double(maxBytes) * 0.8)
        for entry in entries {
            guard runningTotal > evictionTarget else { break }
            try? FileManager.default.removeItem(at: entry.url)
            runningTotal -= entry.size
        }
        totalBytes = runningTotal
    }
}

public actor MockImageResourceLoader: ImageResourceLoading {
    public private(set) var calls: [ImageResourceRequest] = []
    private var result: Result<Data, any Error & Sendable>

    public init(result: Result<Data, any Error & Sendable> = .success(Data())) {
        self.result = result
    }

    public func setResult(_ result: Result<Data, any Error & Sendable>) {
        self.result = result
    }

    public func callCount() -> Int {
        calls.count
    }

    public func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult {
        calls.append(request)
        switch result {
        case let .success(data):
            return ImageResourceResult(request: request, contentType: "image/png", data: data)
        case let .failure(error):
            throw error
        }
    }
}

public struct LiveImageResourceLoader: ImageResourceLoading {
    public var cache: ImageMemoryCache
    public var diskCache: any ImageDiskCaching
    private let session: URLSession

    public init(cache: ImageMemoryCache, diskCache: any ImageDiskCaching = NoopImageDiskCache(), session: URLSession = .shared) {
        self.cache = cache
        self.diskCache = diskCache
        self.session = session
    }

    public func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult {
        if let cached = await cache.imageData(for: request.cacheKey) {
            return ImageResourceResult(request: request, contentType: nil, data: cached, fromCache: true)
        }
        if let persisted = await diskCache.data(for: request.cacheKey), persisted.count <= request.maxBytes {
            await cache.store(persisted, for: request.cacheKey)
            return ImageResourceResult(request: request, contentType: nil, data: persisted, fromCache: true)
        }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("LiquidBagel/0.1 macOS", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw AttachmentActionError.unavailable("Image could not be loaded.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AttachmentActionError.unavailable(Self.safeStatusMessage(http.statusCode))
            }
            guard data.count <= request.maxBytes else {
                throw AttachmentActionError.tooLargeForPreview(maxBytes: request.maxBytes)
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")
            try Self.validateImageContentType(contentType)
            await cache.store(data, for: request.cacheKey)
            await diskCache.store(data, for: request.cacheKey)
            return ImageResourceResult(request: request, contentType: contentType, data: data)
        } catch let error as AttachmentActionError {
            throw error
        } catch {
            throw AttachmentActionError.unavailable("Image could not be loaded.")
        }
    }

    private static func validateImageContentType(_ contentType: String?) throws {
        let lowered = (contentType ?? "").lowercased()
        if lowered.contains("text/html") || lowered.contains("application/xhtml") || !lowered.hasPrefix("image/") {
            throw AttachmentActionError.unavailable("Image request did not return an image.")
        }
    }

    private static func safeStatusMessage(_ code: Int) -> String {
        switch code {
        case 403:
            "Image is not available."
        case 404:
            "Image was not found."
        case 413:
            "Image is too large."
        case 429:
            "Image service is rate limited."
        case 500..<600:
            "Image service is unavailable."
        default:
            "Image could not be loaded."
        }
    }
}

public struct RemoteAttachmentData: Hashable, Sendable {
    public var fileID: FileID?
    public var filename: String
    public var contentType: String?
    public var byteCount: Int?
    public var data: Data

    public init(fileID: FileID? = nil, filename: String, contentType: String? = nil, byteCount: Int? = nil, data: Data) {
        self.fileID = fileID
        self.filename = AttachmentDisplayFormatting.safeFilename(filename)
        self.contentType = AttachmentDisplayFormatting.safeContentType(contentType)
        self.byteCount = byteCount
        self.data = data
    }
}

public enum AttachmentActionError: Error, Equatable, Sendable, LocalizedError {
    case unavailable(String)
    case tooLargeForPreview(maxBytes: Int)
    case cancelled
    case unsafeToOpen

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            message
        case let .tooLargeForPreview(maxBytes):
            "Preview is limited to \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)). Download instead."
        case .cancelled:
            "Cancelled"
        case .unsafeToOpen:
            "This file type cannot be opened from Liquid Bagel."
        }
    }
}

public protocol RemoteAttachmentLoading: Sendable {
    func load(_ item: AttachmentDisplayItem, purpose: RemoteAttachmentLoadPurpose) async throws -> RemoteAttachmentData
}

public protocol AttachmentURLResolving: Sendable {
    func remoteURL(for file: File, environment: StoatAPIEnvironment, purpose: RemoteAttachmentLoadPurpose) -> URL?
    func remoteURL(for item: AttachmentDisplayItem, environment: StoatAPIEnvironment, purpose: RemoteAttachmentLoadPurpose) -> URL?
}

public struct DefaultAttachmentURLResolver: AttachmentURLResolving {
    public init() {}

    public func remoteURL(for file: File, environment: StoatAPIEnvironment, purpose: RemoteAttachmentLoadPurpose) -> URL? {
        let tag = file.tag.isEmpty ? "attachments" : file.tag
        let filename = purpose == .preview ? nil : "original"
        guard let baseURL = environment.mediaBaseURL else { return nil }
        return try? LiveRemoteAttachmentLoader.mediaURL(baseURL: baseURL, tag: tag, fileID: file.id, filename: filename)
    }

    public func remoteURL(for item: AttachmentDisplayItem, environment: StoatAPIEnvironment, purpose: RemoteAttachmentLoadPurpose) -> URL? {
        guard case let .remote(fileID, tag, url) = item.source else { return nil }
        if let url, purpose == .preview {
            return url
        }
        let filename = purpose == .preview ? nil : "original"
        guard let baseURL = environment.mediaBaseURL else { return nil }
        return try? LiveRemoteAttachmentLoader.mediaURL(baseURL: baseURL, tag: tag, fileID: fileID, filename: filename)
    }
}

public actor MockRemoteAttachmentLoader: RemoteAttachmentLoading {
    public private(set) var calls: [(String, RemoteAttachmentLoadPurpose)] = []
    private var result: Result<RemoteAttachmentData, any Error & Sendable>

    public init(result: Result<RemoteAttachmentData, any Error & Sendable> = .success(RemoteAttachmentData(filename: "mock.txt", contentType: "text/plain", byteCount: 4, data: Data("mock".utf8)))) {
        self.result = result
    }

    public func setResult(_ result: Result<RemoteAttachmentData, any Error & Sendable>) {
        self.result = result
    }

    public func callCount() -> Int {
        calls.count
    }

    public func load(_ item: AttachmentDisplayItem, purpose: RemoteAttachmentLoadPurpose) async throws -> RemoteAttachmentData {
        calls.append((item.id, purpose))
        switch result {
        case let .success(data):
            return RemoteAttachmentData(fileID: item.fileID ?? data.fileID, filename: item.displayName, contentType: item.contentType ?? data.contentType, byteCount: item.byteCount ?? data.byteCount, data: data.data)
        case let .failure(error):
            throw error
        }
    }
}

public struct LiveRemoteAttachmentLoader: RemoteAttachmentLoading {
    public var environment: StoatAPIEnvironment
    public var previewLimitBytes: Int
    public var urlResolver: any AttachmentURLResolving
    public var diskCache: any ImageDiskCaching
    private let session: URLSession

    public init(environment: StoatAPIEnvironment, previewLimitBytes: Int = 8 * 1024 * 1024, urlResolver: any AttachmentURLResolving = DefaultAttachmentURLResolver(), diskCache: any ImageDiskCaching = NoopImageDiskCache(), session: URLSession = .shared) {
        self.environment = environment
        self.previewLimitBytes = previewLimitBytes
        self.urlResolver = urlResolver
        self.diskCache = diskCache
        self.session = session
    }

    public func load(_ item: AttachmentDisplayItem, purpose: RemoteAttachmentLoadPurpose) async throws -> RemoteAttachmentData {
        guard case let .remote(fileID, _, _) = item.source else {
            throw AttachmentActionError.unavailable("Attachment is not remote.")
        }
        if purpose == .preview, let byteCount = item.byteCount, byteCount > previewLimitBytes {
            throw AttachmentActionError.tooLargeForPreview(maxBytes: previewLimitBytes)
        }
        let previewCacheKey = ImageCacheKey(id: item.id, kind: .attachmentPreview)
        if purpose == .preview, let persisted = await diskCache.data(for: previewCacheKey), persisted.count <= previewLimitBytes {
            return RemoteAttachmentData(fileID: fileID, filename: item.displayName, contentType: item.contentType, byteCount: persisted.count, data: persisted)
        }
        guard let url = urlResolver.remoteURL(for: item, environment: environment, purpose: purpose) else {
            throw AttachmentActionError.unavailable("Remote media is not configured.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("LiquidBagel/0.1 macOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AttachmentActionError.unavailable("Attachment could not be loaded.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AttachmentActionError.unavailable(Self.safeStatusMessage(http.statusCode))
            }
            if purpose == .preview, data.count > previewLimitBytes {
                throw AttachmentActionError.tooLargeForPreview(maxBytes: previewLimitBytes)
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? item.contentType
            if purpose == .preview {
                try Self.validatePreviewContentType(contentType, item: item)
                await diskCache.store(data, for: previewCacheKey)
            }
            return RemoteAttachmentData(fileID: fileID, filename: item.displayName, contentType: contentType, byteCount: data.count, data: data)
        } catch let error as AttachmentActionError {
            throw error
        } catch {
            throw AttachmentActionError.unavailable("Attachment could not be loaded.")
        }
    }

    public static func mediaURL(baseURL: URL, tag: String, fileID: FileID, filename: String?) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AttachmentActionError.unavailable("Remote media is not configured.")
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = [basePath, pathEscape(tag), pathEscape(fileID.rawValue), filename.map(pathEscape)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        components.percentEncodedPath = "/" + parts.joined(separator: "/")
        components.queryItems = nil
        guard let url = components.url else {
            throw AttachmentActionError.unavailable("Remote media is not configured.")
        }
        return url
    }

    private static func pathEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func safeStatusMessage(_ code: Int) -> String {
        switch code {
        case 403:
            "Attachment is not available."
        case 404:
            "Attachment was not found."
        case 413:
            "Attachment is too large."
        case 429:
            "Attachment service is rate limited."
        case 500..<600:
            "Attachment service is unavailable."
        default:
            "Attachment could not be loaded."
        }
    }

    private static func validatePreviewContentType(_ contentType: String?, item: AttachmentDisplayItem) throws {
        let lowered = (contentType ?? "").lowercased()
        if lowered.contains("text/html") || lowered.contains("application/xhtml") {
            throw AttachmentActionError.unavailable("Preview did not return an image.")
        }
        if item.kind == .image, !lowered.hasPrefix("image/") {
            throw AttachmentActionError.unavailable("Preview did not return an image.")
        }
    }
}

public protocol AttachmentSaving: Sendable {
    func save(data: Data, suggestedFilename: String) async throws
}

public protocol AttachmentOpening: Sendable {
    func open(_ localFile: URL) async throws
}

public struct AppKitAttachmentSaver: AttachmentSaving {
    public init() {}

    public func save(data: Data, suggestedFilename: String) async throws {
        #if canImport(AppKit)
        let destination: URL? = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = AttachmentDisplayFormatting.safeFilename(suggestedFilename)
                panel.canCreateDirectories = true
                panel.begin { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
        }
        guard let destination else {
            throw AttachmentActionError.cancelled
        }
        try await Task.detached(priority: .utility) {
            try data.write(to: destination, options: [.atomic])
        }.value
        #else
        throw AttachmentActionError.unavailable("Save As is unavailable on this platform.")
        #endif
    }
}

public struct AppKitAttachmentOpener: AttachmentOpening {
    public init() {}

    public func open(_ localFile: URL) async throws {
        guard !AttachmentSafety.isExecutableLike(localFile) else {
            throw AttachmentActionError.unsafeToOpen
        }
        #if canImport(AppKit)
        let opened = await MainActor.run {
            NSWorkspace.shared.open(localFile)
        }
        if !opened {
            throw AttachmentActionError.unavailable("Attachment could not be opened.")
        }
        #else
        throw AttachmentActionError.unavailable("Open externally is unavailable on this platform.")
        #endif
    }
}

public actor MockAttachmentSaver: AttachmentSaving {
    public private(set) var saves: [(String, Int)] = []
    public var error: (any Error & Sendable)?

    public init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    public func save(data: Data, suggestedFilename: String) async throws {
        if let error {
            throw error
        }
        saves.append((AttachmentDisplayFormatting.safeFilename(suggestedFilename), data.count))
    }

    public func saveCount() -> Int {
        saves.count
    }
}

public actor MockAttachmentOpener: AttachmentOpening {
    public private(set) var opened: [URL] = []
    public var error: (any Error & Sendable)?

    public init(error: (any Error & Sendable)? = nil) {
        self.error = error
    }

    public func open(_ localFile: URL) async throws {
        if let error {
            throw error
        }
        guard !AttachmentSafety.isExecutableLike(localFile) else {
            throw AttachmentActionError.unsafeToOpen
        }
        opened.append(localFile)
    }

    public func openCount() -> Int {
        opened.count
    }
}

public enum AttachmentSafety {
    public static func isExecutableLike(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let blocked = ["app", "command", "exec", "sh", "bash", "zsh", "fish", "bin", "dmg", "pkg", "scpt", "workflow", "terminal"]
        if blocked.contains(ext) { return true }
        if let values = try? url.resourceValues(forKeys: [.isExecutableKey]), values.isExecutable == true {
            return true
        }
        return false
    }

    public static func safeErrorMessage(_ error: Error) -> String {
        if let actionError = error as? AttachmentActionError {
            if actionError == .cancelled { return "Cancelled" }
            return AttachmentDiagnosticsFormatter.redact(actionError.localizedDescription)
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return AttachmentDiagnosticsFormatter.redact(description)
        }
        return "Attachment action failed."
    }
}

public struct AttachmentPreviewSheetItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var item: AttachmentDisplayItem
    public var data: Data?
    public var localFile: URL?
    public var debugFileID: String?
    public var statusMessage: String?

    public init(item: AttachmentDisplayItem, data: Data? = nil, localFile: URL? = nil, debugFileID: String? = nil, statusMessage: String? = nil) {
        self.id = item.id
        self.item = item
        self.data = data
        self.localFile = localFile
        self.debugFileID = debugFileID.map(AttachmentDisplayFormatting.shortID)
        self.statusMessage = statusMessage.map(AttachmentDiagnosticsFormatter.redact)
    }
}

public struct AttachmentDiagnostics: Hashable, Sendable {
    public var queuedDraftCount: Int
    public var uploadingCount: Int
    public var failedUploadCount: Int
    public var displayedAttachmentCount: Int
    public var loadedPreviewCount: Int
    public var failedPreviewCount: Int
    public var lastAttachmentAction: String?

    public init(
        queuedDraftCount: Int = 0,
        uploadingCount: Int = 0,
        failedUploadCount: Int = 0,
        displayedAttachmentCount: Int = 0,
        loadedPreviewCount: Int = 0,
        failedPreviewCount: Int = 0,
        lastAttachmentAction: String? = nil
    ) {
        self.queuedDraftCount = queuedDraftCount
        self.uploadingCount = uploadingCount
        self.failedUploadCount = failedUploadCount
        self.displayedAttachmentCount = displayedAttachmentCount
        self.loadedPreviewCount = loadedPreviewCount
        self.failedPreviewCount = failedPreviewCount
        self.lastAttachmentAction = lastAttachmentAction.map(AttachmentDiagnosticsFormatter.redact)
    }
}

public struct ImageResourceDiagnostics: Hashable, Sendable {
    public var loadedCount: Int
    public var failedCount: Int
    public var activeTaskCount: Int
    public var queuedTaskCount: Int
    public var cacheEntryCount: Int
    public var cacheByteCount: Int
    public var lastAction: String?
    public var activeCountByKind: [ImageResourceKind: Int]
    public var queuedCountByKind: [ImageResourceKind: Int]
    public var failedCountByKind: [ImageResourceKind: Int]
    public var mediaSafeModeEnabled: Bool

    public init(
        loadedCount: Int = 0,
        failedCount: Int = 0,
        activeTaskCount: Int = 0,
        queuedTaskCount: Int = 0,
        cacheEntryCount: Int = 0,
        cacheByteCount: Int = 0,
        lastAction: String? = nil,
        activeCountByKind: [ImageResourceKind: Int] = [:],
        queuedCountByKind: [ImageResourceKind: Int] = [:],
        failedCountByKind: [ImageResourceKind: Int] = [:],
        mediaSafeModeEnabled: Bool = false
    ) {
        self.loadedCount = loadedCount
        self.failedCount = failedCount
        self.activeTaskCount = activeTaskCount
        self.queuedTaskCount = queuedTaskCount
        self.cacheEntryCount = cacheEntryCount
        self.cacheByteCount = cacheByteCount
        self.lastAction = lastAction.map(AttachmentDiagnosticsFormatter.redact)
        self.activeCountByKind = activeCountByKind
        self.queuedCountByKind = queuedCountByKind
        self.failedCountByKind = failedCountByKind
        self.mediaSafeModeEnabled = mediaSafeModeEnabled
    }
}

public enum AttachmentDiagnosticsFormatter {
    public static func redact(_ value: String) -> String {
        var output = value
        let patterns = [
            "[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{24,}\\.[A-Za-z0-9_-]{12,}",
            "(?i)(session|bot|token)[=: ]+[A-Za-z0-9._-]+",
            "file://[^\\s,]+",
            "(/[A-Za-z0-9._ -]+){2,}"
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "<redacted>", options: .regularExpression)
        }
        return output
    }
}

extension AttachmentDisplayItem {
    init(attachmentDraft draft: ComposerAttachmentDraft) {
        let source: AttachmentDisplaySource = draft.uploadedFileID.map { .uploadedDraft(fileID: $0) } ?? .localDraft
        self.init(
            id: "draft-\(draft.id.uuidString)",
            fileID: draft.uploadedFileID,
            displayName: draft.filename,
            contentType: draft.mimeType,
            byteCount: draft.byteCount,
            kind: AttachmentDisplayFormatting.kind(contentType: draft.mimeType, filename: draft.filename),
            source: source,
            previewState: draft.previewData == nil ? .notLoaded : .readyLocal,
            previewData: draft.previewData
        )
    }
}
