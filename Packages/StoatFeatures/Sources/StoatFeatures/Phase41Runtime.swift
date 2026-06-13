import Foundation
import StoatAPI
import StoatModels
import UniformTypeIdentifiers

public enum ProfileEditFieldCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case displayName
    case profileContent
    case avatar
    case profileBackground
}

public enum ProfileEditRouteCategory: String, Codable, Hashable, Sendable {
    case none
    case currentUserPatch
}

public enum ProfileEditUploadTagCategory: String, Codable, Hashable, Sendable {
    case none
    case avatars
    case backgrounds
    case multiple
}

public enum ProfileEditResultCategory: String, Codable, Hashable, Sendable {
    case idle
    case skipped
    case pending
    case succeeded
    case failed
}

public enum ProfileEditReturnedDataShape: String, Codable, Hashable, Sendable {
    case none
    case fullUser
    case partialUser
    case empty
    case decodeFailed
}

public enum ProfileEditSafeErrorCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case unauthenticated
    case forbidden
    case validation
    case uploadRejected
    case fileTooLarge
    case unsupportedFileType
    case rateLimited
    case network
    case server
    case decode
    case unknown

    public static func categorize(_ error: any Error) -> Self {
        if let validation = error as? ProfileEditValidationError {
            switch validation {
            case .fileTooLarge:
                return .fileTooLarge
            case .unsupportedFileType:
                return .unsupportedFileType
            case .invalidDisplayName, .profileContentTooLong, .missingCurrentUser, .missingClient, .unreadableFile:
                return .validation
            }
        }
        if let apiError = error as? StoatAPIError {
            switch apiError {
            case .missingAuthentication, .unauthorized:
                return .unauthenticated
            case .forbidden:
                return .forbidden
            case .rateLimited:
                return .rateLimited
            case .serverError:
                return .server
            case .decodingFailed:
                return .decode
            case .transport:
                return .network
            case let .unknown(statusCode, _):
                switch statusCode {
                case 400, 422:
                    return .validation
                case 401:
                    return .unauthenticated
                case 403:
                    return .forbidden
                case 413:
                    return .fileTooLarge
                case 415:
                    return .unsupportedFileType
                case 429:
                    return .rateLimited
                case 500...599:
                    return .server
                default:
                    return .unknown
                }
            case .invalidURL, .invalidEnvironment, .notFound, .unimplementedEndpoint:
                return .unknown
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network
        }
        return .unknown
    }

    public static func uploadCategory(_ error: any Error) -> Self {
        let category = categorize(error)
        switch category {
        case .validation, .unknown:
            return .uploadRejected
        default:
            return category
        }
    }

    public var userFacingMessage: String {
        switch self {
        case .unauthenticated:
            return "Reconnect before saving profile changes."
        case .forbidden:
            return "This account cannot make that profile change."
        case .validation:
            return "Check the highlighted profile fields and try again."
        case .uploadRejected:
            return "Stoat rejected the selected image before profile changes were saved."
        case .fileTooLarge:
            return "The selected image is too large for this profile field."
        case .unsupportedFileType:
            return "Choose a supported image file."
        case .rateLimited:
            return "Stoat rate-limited this profile change. Try again shortly."
        case .network:
            return "Network trouble prevented saving profile changes."
        case .server:
            return "Stoat could not save the profile change right now."
        case .decode:
            return "Stoat returned a profile response Liquid Bagel could not read."
        case .unknown:
            return "Profile changes could not be saved."
        }
    }
}

public enum ProfileEditValidationError: Error, Hashable, Sendable {
    case invalidDisplayName
    case profileContentTooLong
    case missingCurrentUser
    case missingClient
    case unreadableFile
    case fileTooLarge(maxBytes: Int)
    case unsupportedFileType
}

extension ProfileEditValidationError: LocalizedError {
    public var errorDescription: String? {
        ProfileEditSafeErrorCategory.categorize(self).userFacingMessage
    }
}

public enum ProfileEditMediaKind: String, Codable, Hashable, Sendable, CaseIterable {
    case avatar
    case background

    public var uploadTag: UploadTag {
        switch self {
        case .avatar:
            return .avatars
        case .background:
            return .backgrounds
        }
    }

    public var uploadTagCategory: ProfileEditUploadTagCategory {
        switch self {
        case .avatar:
            return .avatars
        case .background:
            return .backgrounds
        }
    }

    public var fieldCategory: ProfileEditFieldCategory {
        switch self {
        case .avatar:
            return .avatar
        case .background:
            return .profileBackground
        }
    }
}

public struct ProfileEditMediaDraft: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ProfileEditMediaKind
    public var data: Data
    public var filename: String
    public var mimeType: String
    public var byteCount: Int
    public var previewData: Data?

    public init(id: UUID = UUID(), kind: ProfileEditMediaKind, data: Data, filename: String, mimeType: String, previewData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.data = data
        self.filename = ProfileEditMediaValidationPolicy.sanitizedFilename(filename, fallback: kind == .avatar ? "avatar.png" : "background.png")
        self.mimeType = mimeType
        self.byteCount = data.count
        self.previewData = previewData ?? data
    }
}

public enum ProfileEditMediaChange: Hashable, Sendable {
    case unchanged
    case remove
    case upload(ProfileEditMediaDraft)

    public var stagedPreviewData: Data? {
        if case let .upload(draft) = self { return draft.previewData }
        return nil
    }
}

public struct ProfileEditMediaValidationPolicy: Hashable, Sendable {
    public static let avatarMaxBytes = 4 * 1024 * 1024
    public static let backgroundMaxBytes = 6 * 1024 * 1024

    public init() {}

    public func draft(for url: URL, kind: ProfileEditMediaKind) throws -> ProfileEditMediaDraft {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        if values.isDirectory == true {
            throw ProfileEditValidationError.unsupportedFileType
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let filename = Self.sanitizedFilename(url.lastPathComponent, fallback: kind == .avatar ? "avatar.png" : "background.png")
        let contentType = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let mimeType = contentType?.preferredMIMEType ?? mimeTypeFromExtension(url.pathExtension) ?? "application/octet-stream"
        return try draft(data: data, filename: filename, mimeType: mimeType, contentType: contentType, kind: kind)
    }

    public func draft(data: Data, filename: String, mimeType: String, kind: ProfileEditMediaKind) throws -> ProfileEditMediaDraft {
        let contentType = UTType(mimeType: mimeType) ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
        return try draft(data: data, filename: filename, mimeType: mimeType, contentType: contentType, kind: kind)
    }

    private func draft(data: Data, filename: String, mimeType: String, contentType: UTType?, kind: ProfileEditMediaKind) throws -> ProfileEditMediaDraft {
        let limit = maxBytes(for: kind)
        guard data.count <= limit else {
            throw ProfileEditValidationError.fileTooLarge(maxBytes: limit)
        }
        guard isSupportedImage(contentType: contentType, mimeType: mimeType) else {
            throw ProfileEditValidationError.unsupportedFileType
        }
        return ProfileEditMediaDraft(kind: kind, data: data, filename: filename, mimeType: mimeType)
    }

    public func maxBytes(for kind: ProfileEditMediaKind) -> Int {
        switch kind {
        case .avatar:
            return Self.avatarMaxBytes
        case .background:
            return Self.backgroundMaxBytes
        }
    }

    public static func sanitizedFilename(_ value: String, fallback: String) -> String {
        let lastComponent = URL(fileURLWithPath: value).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        let cleaned = String(lastComponent.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private func isSupportedImage(contentType: UTType?, mimeType: String) -> Bool {
        if let contentType, contentType.conforms(to: .image) {
            return true
        }
        return mimeType.lowercased().hasPrefix("image/")
    }

    private func mimeTypeFromExtension(_ pathExtension: String) -> String? {
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)?.preferredMIMEType
    }
}

public struct ProfileEditDraftState: Hashable, Sendable {
    public var userID: UserID?
    public var originalDisplayName: String
    public var displayName: String
    public var originalProfileContent: String
    public var profileContent: String
    public var originalAvatarFileID: FileID?
    public var originalBackgroundFileID: FileID?
    public var avatarChange: ProfileEditMediaChange
    public var backgroundChange: ProfileEditMediaChange
    public var isSaving: Bool
    public var safeErrorMessage: String?
    public var saveStatusMessage: String?

    public init() {
        self.userID = nil
        self.originalDisplayName = ""
        self.displayName = ""
        self.originalProfileContent = ""
        self.profileContent = ""
        self.originalAvatarFileID = nil
        self.originalBackgroundFileID = nil
        self.avatarChange = .unchanged
        self.backgroundChange = .unchanged
        self.isSaving = false
        self.safeErrorMessage = nil
        self.saveStatusMessage = nil
    }

    public init(user: User, profile: UserProfile?) {
        self.userID = user.id
        self.originalDisplayName = user.displayName ?? ""
        self.displayName = user.displayName ?? ""
        self.originalProfileContent = profile?.content ?? ""
        self.profileContent = profile?.content ?? ""
        self.originalAvatarFileID = user.avatar?.id
        self.originalBackgroundFileID = profile?.background?.id
        self.avatarChange = .unchanged
        self.backgroundChange = .unchanged
        self.isSaving = false
        self.safeErrorMessage = nil
        self.saveStatusMessage = nil
    }

    public var isDirty: Bool {
        normalizedDisplayName(displayName) != normalizedDisplayName(originalDisplayName) ||
            normalizedProfileContent(profileContent) != normalizedProfileContent(originalProfileContent) ||
            avatarChange != .unchanged ||
            backgroundChange != .unchanged
    }

    public var canSave: Bool {
        isDirty && !isSaving
    }

    public var editedFieldCategories: Set<ProfileEditFieldCategory> {
        var fields: Set<ProfileEditFieldCategory> = []
        if normalizedDisplayName(displayName) != normalizedDisplayName(originalDisplayName) {
            fields.insert(.displayName)
        }
        if normalizedProfileContent(profileContent) != normalizedProfileContent(originalProfileContent) {
            fields.insert(.profileContent)
        }
        if avatarChange != .unchanged {
            fields.insert(.avatar)
        }
        if backgroundChange != .unchanged {
            fields.insert(.profileBackground)
        }
        return fields
    }

    private func normalizedDisplayName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedProfileContent(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value
    }
}

public struct ProfileEditDiagnostics: Hashable, Sendable {
    public var lastAction: String
    public var routeCategory: ProfileEditRouteCategory
    public var editedFieldCategories: Set<ProfileEditFieldCategory>
    public var uploadTagCategory: ProfileEditUploadTagCategory
    public var uploadResultCategory: ProfileEditResultCategory
    public var mutationResultCategory: ProfileEditResultCategory
    public var durationMilliseconds: Int?
    public var cacheInvalidationCount: Int
    public var safeErrorCategory: ProfileEditSafeErrorCategory?
    public var returnedDataShape: ProfileEditReturnedDataShape

    public init(
        lastAction: String = "idle",
        routeCategory: ProfileEditRouteCategory = .none,
        editedFieldCategories: Set<ProfileEditFieldCategory> = [],
        uploadTagCategory: ProfileEditUploadTagCategory = .none,
        uploadResultCategory: ProfileEditResultCategory = .idle,
        mutationResultCategory: ProfileEditResultCategory = .idle,
        durationMilliseconds: Int? = nil,
        cacheInvalidationCount: Int = 0,
        safeErrorCategory: ProfileEditSafeErrorCategory? = nil,
        returnedDataShape: ProfileEditReturnedDataShape = .none
    ) {
        self.lastAction = lastAction
        self.routeCategory = routeCategory
        self.editedFieldCategories = editedFieldCategories
        self.uploadTagCategory = uploadTagCategory
        self.uploadResultCategory = uploadResultCategory
        self.mutationResultCategory = mutationResultCategory
        self.durationMilliseconds = durationMilliseconds
        self.cacheInvalidationCount = cacheInvalidationCount
        self.safeErrorCategory = safeErrorCategory
        self.returnedDataShape = returnedDataShape
    }
}

public enum ProfileEditDiagnosticsFormatter {
    public static func redactedText(_ diagnostics: ProfileEditDiagnostics) -> String {
        let fields = diagnostics.editedFieldCategories.map(\.rawValue).sorted().joined(separator: ", ")
        let text = """
        Profile edit diagnostics
        last action: \(diagnostics.lastAction)
        route category: \(diagnostics.routeCategory.rawValue)
        edited fields: \(fields.isEmpty ? "-" : fields)
        upload tag category: \(diagnostics.uploadTagCategory.rawValue)
        upload result category: \(diagnostics.uploadResultCategory.rawValue)
        mutation result category: \(diagnostics.mutationResultCategory.rawValue)
        duration ms: \(diagnostics.durationMilliseconds.map(String.init) ?? "-")
        cache invalidation count: \(diagnostics.cacheInvalidationCount)
        safe error category: \(diagnostics.safeErrorCategory?.rawValue ?? "-")
        returned data shape: \(diagnostics.returnedDataShape.rawValue)
        """
        return redactSensitiveText(text)
    }

    public static func redactSensitiveText(_ value: String) -> String {
        var output = value
        let patterns = [
            #"\{[^\n]*\}"#,
            #"https?://[^\s,;)"]+"#,
            #"file://[^\s,;)"]+"#,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(x-session-token|authorization|token|session|session_id|sessionID|password|mfa|ticket|response)\b\s*[:=]\s*["']?[^"',;\s]+"#,
            #"(?i)\b(password|mfa|ticket|response)\b\s+[^,;\n]+"#,
            #"(/Users|/tmp|/var|/private|/Volumes)(/[^\s,;)"]+)+"#,
            #"\b[A-Za-z0-9_-]{20,}\b"#
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        output = AttachmentDiagnosticsFormatter.redact(output)
        output = Phase6UIHelpers.safeDiagnostics(output)
        output = Phase17MessageActions.redactedDiagnosticText(output)
        return output
    }
}
