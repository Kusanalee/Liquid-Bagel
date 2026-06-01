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
    private let session: URLSession

    public init(environment: StoatAPIEnvironment, previewLimitBytes: Int = 8 * 1024 * 1024, session: URLSession = .shared) {
        self.environment = environment
        self.previewLimitBytes = previewLimitBytes
        self.session = session
    }

    public func load(_ item: AttachmentDisplayItem, purpose: RemoteAttachmentLoadPurpose) async throws -> RemoteAttachmentData {
        guard case let .remote(fileID, tag, _) = item.source else {
            throw AttachmentActionError.unavailable("Attachment is not remote.")
        }
        if purpose == .preview, let byteCount = item.byteCount, byteCount > previewLimitBytes {
            throw AttachmentActionError.tooLargeForPreview(maxBytes: previewLimitBytes)
        }
        guard let baseURL = environment.mediaBaseURL else {
            throw AttachmentActionError.unavailable("Remote media is not configured.")
        }
        let filename = purpose == .preview ? nil : "original"
        let url = try Self.mediaURL(baseURL: baseURL, tag: tag, fileID: fileID, filename: filename)
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
        let destination: URL? = await MainActor.run {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = AttachmentDisplayFormatting.safeFilename(suggestedFilename)
            panel.canCreateDirectories = true
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let destination else {
            throw AttachmentActionError.cancelled
        }
        try data.write(to: destination, options: [.atomic])
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
            previewState: draft.previewData == nil ? .notLoaded : .readyLocal
        )
    }
}
