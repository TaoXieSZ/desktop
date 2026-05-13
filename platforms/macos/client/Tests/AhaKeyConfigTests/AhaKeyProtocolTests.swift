import XCTest
@testable import AhaKeyConfig

final class AhaKeyProtocolTests: XCTestCase {
    func testSetKeyMappingFrameLayout() {
        let frame = AhaKeyCommand.setKeyMapping(
            mode: 1,
            keyIndex: 2,
            hidCodes: [HIDUsage.leftGUI, HIDUsage.enter]
        )

        XCTAssertEqual(
            Array(frame),
            [
                0xAA, 0xBB,
                AhaKeyCommand.cmdUpdateCustomKey,
                AhaKeyCommand.subShortcut,
                0x01,
                0x02,
                HIDUsage.leftGUI,
                HIDUsage.enter,
                0xCC, 0xDD,
            ]
        )
    }

    func testDescriptionFrameSanitizesToAsciiAndMaxLength() {
        let frame = AhaKeyCommand.setKeyDescription(
            mode: 0,
            keyIndex: 1,
            text: "Accept✅-01234567890123456789"
        )

        let payload = Array(frame.dropFirst(6).dropLast(2))
        XCTAssertEqual(String(bytes: payload, encoding: .utf8), "Accept-0123456789012")
    }

    func testParsePictureStateResponse() throws {
        let payload = Data([
            0x02,
            0x34, 0x12,
            0x08, 0x00,
            0x64, 0x00,
            0x4A, 0x00,
        ])

        let state = try XCTUnwrap(AhaKeyResponseParser.parsePictureStateResponse(payload))
        XCTAssertEqual(state.mode, 2)
        XCTAssertEqual(state.startIndex, 0x1234)
        XCTAssertEqual(state.picLength, 8)
        XCTAssertEqual(state.frameInterval, 100)
        XCTAssertEqual(state.allModeMaxPic, 74)
    }
}
