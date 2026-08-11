//  Phase 73 - live-only runtime.

import StoatModels
import StoatAPI
import StoatPersistence
import StoatRealtime
import StoatUI
import Observation
import SwiftUI
import XCTest
@testable import StoatFeatures

final class LiveOnlyRuntimeTests: XCTestCase {

    /// A live shell with no authenticated user must not invent one.
    ///
    /// `MainShellViewModel.init` used `TestShellData.currentUserID` as the fallback for the real
    /// current user. This passes today only because a real snapshot never contains the synthetic
    /// ULID `01HX…0001`, so the lookup misses. It is a regression guard for the removal, not a
    /// reproduction of a user-visible bug.
    @MainActor
    func testPhase73LiveShellWithoutSessionHasNoCurrentUser() {
        let model = MainShellViewModel(
            snapshot: RealtimeSnapshot(),
            runtimeMode: .liveManual,
            sessionState: .signedOut,
            currentUser: nil
        )

        XCTAssertNil(model.currentUserID, "a live shell without a session must not fabricate a user ID")
        XCTAssertNil(model.currentUser, "a live shell without a session must not fabricate a user")
    }

    /// The default construction path must not reach for a mock service.
    @MainActor
    func testPhase73DefaultShellConstructsNoMockServices() {
        let model = MainShellViewModel(snapshot: RealtimeSnapshot(), runtimeMode: .liveManual)

        for name in [
            String(describing: type(of: model.attachmentUploadHandler)),
            String(describing: type(of: model.remoteAttachmentLoader)),
            String(describing: type(of: model.imageResourceLoader)),
            String(describing: type(of: model.messageActionHandler))
        ] {
            XCTAssertFalse(name.hasPrefix("Mock"), "production default constructed a mock: \(name)")
            XCTAssertFalse(name.hasPrefix("Stub"), "production default constructed a stub: \(name)")
        }
    }
}
