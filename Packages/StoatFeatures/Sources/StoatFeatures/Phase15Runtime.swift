import Foundation
import StoatAPI
import StoatModels
import UniformTypeIdentifiers

public enum ComposerAttachmentSource: Hashable, Sendable {
    case fileURL(URL)
    case inMemory(Data)
}

public enum AttachmentUploadLimits {
    public static let maxFileBytes = 20 * 1024 * 1024
}

public enum ComposerAttachmentUploadStatus: Hashable, Sendable {
    case queued
    case reading
    case uploading
    case uploaded(FileID)
    case failed(String)

    public var uploadedFileID: FileID? {
        if case let .uploaded(id) = self { return id }
        return nil
    }

    public var isWorking: Bool {
        switch self {
        case .reading, .uploading:
            return true
        case .queued, .uploaded, .failed:
            return false
        }
    }
}

public enum ComposerAttachmentKind: Hashable, Sendable {
    case image
    case pdf
    case text
    case file
}

public struct ComposerAttachmentDraft: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var source: ComposerAttachmentSource
    public var filename: String
    public var mimeType: String
    public var byteCount: Int
    public var kind: ComposerAttachmentKind
    public var previewData: Data?
    public var status: ComposerAttachmentUploadStatus

    public init(
        id: UUID = UUID(),
        source: ComposerAttachmentSource,
        filename: String,
        mimeType: String,
        byteCount: Int,
        kind: ComposerAttachmentKind = .file,
        previewData: Data? = nil,
        status: ComposerAttachmentUploadStatus = .queued
    ) {
        self.id = id
        self.source = source
        self.filename = Self.sanitizedFilename(filename)
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.kind = kind
        self.previewData = previewData
        self.status = status
    }

    public var uploadedFileID: FileID? {
        status.uploadedFileID
    }

    public var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    public static func sanitizedFilename(_ filename: String) -> String {
        let last = URL(fileURLWithPath: filename).lastPathComponent
        let controlSet = CharacterSet.controlCharacters
        let scalars = last.unicodeScalars.filter { !controlSet.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}

public struct AttachmentDropReviewItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var draft: ComposerAttachmentDraft?
    public var filename: String
    public var subtitle: String
    public var systemImage: String
    public var warning: String?

    public init(draft: ComposerAttachmentDraft) {
        self.id = draft.id
        self.draft = draft
        self.filename = draft.filename
        self.subtitle = draft.displaySize
        self.systemImage = Self.systemImage(for: draft.kind)
        self.warning = nil
    }

    public init(url: URL, error: Error) {
        self.id = UUID()
        self.draft = nil
        self.filename = ComposerAttachmentDraft.sanitizedFilename(url.lastPathComponent)
        self.subtitle = "Not attachable"
        self.systemImage = "exclamationmark.triangle"
        self.warning = error.userFacingMessage
    }

    public init(filename: String, error: Error) {
        self.id = UUID()
        self.draft = nil
        self.filename = ComposerAttachmentDraft.sanitizedFilename(filename)
        self.subtitle = "Not attachable"
        self.systemImage = "exclamationmark.triangle"
        self.warning = error.userFacingMessage
    }

    public var canAttach: Bool {
        draft != nil
    }

    private static func systemImage(for kind: ComposerAttachmentKind) -> String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .file: "doc"
        }
    }
}

public struct AttachmentDropReview: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var channelID: ChannelID?
    public var channelName: String?
    public var items: [AttachmentDropReviewItem]
    public var blockedReason: String?

    public init(
        id: UUID = UUID(),
        channelID: ChannelID?,
        channelName: String?,
        items: [AttachmentDropReviewItem],
        blockedReason: String? = nil
    ) {
        self.id = id
        self.channelID = channelID
        self.channelName = channelName
        self.items = items
        self.blockedReason = blockedReason
    }

    public var attachableItems: [AttachmentDropReviewItem] {
        items.filter(\.canAttach)
    }

    public var canAddToMessage: Bool {
        blockedReason == nil && channelID != nil && !attachableItems.isEmpty
    }
}

public enum AttachmentValidationError: Error, Equatable, Sendable, LocalizedError {
    case tooManyAttachments(Int)
    case unsupportedType
    case tooLarge(maxBytes: Int)
    case unreadable
    case directory
    case executable

    public var errorDescription: String? {
        switch self {
        case let .tooManyAttachments(limit):
            return "Attach up to \(limit) files per message."
        case .unsupportedType:
            return "This file type is not supported for attachments yet."
        case .tooLarge:
            return "File too large. Liquid Bagel currently supports files up to 20 MB."
        case .unreadable:
            return "Attachment could not be read."
        case .directory:
            return "Folders and packages cannot be attached."
        case .executable:
            return "Executable files cannot be attached."
        }
    }
}

public struct AttachmentValidationPolicy: Sendable {
    public var maxAttachmentCount: Int
    public var maxFileBytes: Int
    public var allowedTypes: [UTType]

    public init(
        maxAttachmentCount: Int = 5,
        maxFileBytes: Int = AttachmentUploadLimits.maxFileBytes,
        allowedTypes: [UTType] = [
            .png, .jpeg, .gif, .heic, .webP, .pdf, .plainText, .utf8PlainText,
            .text, .rtf, .json, .commaSeparatedText, .init(filenameExtension: "md") ?? .plainText
        ]
    ) {
        self.maxAttachmentCount = maxAttachmentCount
        self.maxFileBytes = maxFileBytes
        self.allowedTypes = allowedTypes
    }

    public func draft(for url: URL, existingCount: Int) throws -> ComposerAttachmentDraft {
        guard existingCount < maxAttachmentCount else {
            throw AttachmentValidationError.tooManyAttachments(maxAttachmentCount)
        }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isExecutableKey, .fileSizeKey, .contentTypeKey])
        if values?.isDirectory == true || values?.isPackage == true {
            throw AttachmentValidationError.directory
        }
        if values?.isExecutable == true {
            throw AttachmentValidationError.executable
        }
        guard values?.isRegularFile == true else {
            throw AttachmentValidationError.unreadable
        }
        let byteCount = values?.fileSize ?? 0
        guard byteCount <= maxFileBytes else {
            throw AttachmentValidationError.tooLarge(maxBytes: maxFileBytes)
        }
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        guard isAllowed(type) else {
            throw AttachmentValidationError.unsupportedType
        }
        return ComposerAttachmentDraft(
            source: .fileURL(url),
            filename: url.lastPathComponent,
            mimeType: type.preferredMIMEType ?? "application/octet-stream",
            byteCount: byteCount,
            kind: kind(for: type),
            previewData: nil
        )
    }

    public func imageDraft(data: Data, filename: String = "Pasted Image.png", existingCount: Int) throws -> ComposerAttachmentDraft {
        guard existingCount < maxAttachmentCount else {
            throw AttachmentValidationError.tooManyAttachments(maxAttachmentCount)
        }
        guard data.count <= maxFileBytes else {
            throw AttachmentValidationError.tooLarge(maxBytes: maxFileBytes)
        }
        return ComposerAttachmentDraft(
            source: .inMemory(data),
            filename: filename,
            mimeType: "image/png",
            byteCount: data.count,
            kind: .image,
            previewData: data
        )
    }

    private func isAllowed(_ type: UTType) -> Bool {
        allowedTypes.contains { type.conforms(to: $0) }
    }

    private func kind(for type: UTType) -> ComposerAttachmentKind {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .text) { return .text }
        return .file
    }
}

public protocol AttachmentUploadHandling: Sendable {
    func upload(_ attachment: ComposerAttachmentDraft) async throws -> UploadedFile
}

public actor MockAttachmentUploadHandler: AttachmentUploadHandling {
    public private(set) var uploads: [ComposerAttachmentDraft] = []
    private var uploadError: (any Error & Sendable)?

    public init(uploadError: (any Error & Sendable)? = nil) {
        self.uploadError = uploadError
    }

    public func setUploadError(_ error: (any Error & Sendable)?) {
        uploadError = error
    }

    public func uploadCount() -> Int {
        uploads.count
    }

    public func upload(_ attachment: ComposerAttachmentDraft) async throws -> UploadedFile {
        if let uploadError {
            throw uploadError
        }
        uploads.append(attachment)
        return UploadedFile(id: FileID(rawValue: "mock-attachments-\(abs(attachment.filename.hashValue))"))
    }
}

public actor LiveAttachmentUploadHandler: AttachmentUploadHandling {
    private let apiClient: any StoatAPIClient

    public init(apiClient: any StoatAPIClient) {
        self.apiClient = apiClient
    }

    public func upload(_ attachment: ComposerAttachmentDraft) async throws -> UploadedFile {
        let data: Data
        switch attachment.source {
        case let .inMemory(memoryData):
            data = memoryData
        case let .fileURL(url):
            data = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return try Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
        }
        return try await apiClient.uploadFile(data: data, filename: attachment.filename, mimeType: attachment.mimeType, tag: .attachments)
    }
}

public extension File {
    init(attachmentDraft draft: ComposerAttachmentDraft, uploadedFileID: FileID) {
        self.init(
            id: uploadedFileID,
            tag: "attachments",
            filename: draft.filename,
            metadata: draft.kind == .image ? .image(width: 0, height: 0, thumbhash: nil, animated: nil) : .file,
            contentType: draft.mimeType,
            size: draft.byteCount
        )
    }
}
