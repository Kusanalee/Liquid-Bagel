import XCTest
@testable import StoatVoice

final class VoiceEngineTests: XCTestCase {
    func testVoiceParticipantIdentityMatchesID() {
        let participant = VoiceParticipant(identity: "01ABCDEF", name: "Test User")
        XCTAssertEqual(participant.id, "01ABCDEF")
    }

    func testVoiceAudioDeviceIdentifiable() {
        let device = VoiceAudioDevice(id: "device-1", name: "MacBook Pro Microphone", isDefault: true)
        XCTAssertEqual(device.id, "device-1")
        XCTAssertTrue(device.isDefault)
    }
}
