import Foundation
import StoatAPI
import StoatModels
import StoatUI

/// Null objects for services that only exist once a live session is established.
///
/// These replace the `Mock*` defaults that `MainShellViewModel.init` used to construct. Those
/// mocks reported success, so a pre-connect attachment could appear to upload. Failing closed with
/// safe copy is the honest behavior, and it follows the existing `UnavailableMessageActionHandler`
/// / `NoopChannelAckSender` convention already used for live-mode null objects.

public struct RuntimeServiceUnavailableError: LocalizedError {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var errorDescription: String? { reason }
}

public actor UnavailableAttachmentUploadHandler: AttachmentUploadHandling {
    public init() {}

    public func upload(_ attachment: ComposerAttachmentDraft) async throws -> UploadedFile {
        throw RuntimeServiceUnavailableError(reason: "Reconnect before attaching files.")
    }
}

public actor UnavailableRemoteAttachmentLoader: RemoteAttachmentLoading {
    public init() {}

    public func load(_ item: AttachmentDisplayItem, purpose: RemoteAttachmentLoadPurpose) async throws -> RemoteAttachmentData {
        throw RuntimeServiceUnavailableError(reason: "Reconnect to load attachments.")
    }
}

public actor UnavailableImageResourceLoader: ImageResourceLoading {
    public init() {}

    public func loadImage(_ request: ImageResourceRequest) async throws -> ImageResourceResult {
        throw RuntimeServiceUnavailableError(reason: "Reconnect to load images.")
    }
}
