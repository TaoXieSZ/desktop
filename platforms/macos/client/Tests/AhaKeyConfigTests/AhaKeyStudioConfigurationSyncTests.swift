import XCTest
@testable import AhaKeyConfig

final class AhaKeyStudioConfigurationSyncTests: XCTestCase {
    func testDirtyCountAndPartsTrackKeyAndOLEDChanges() {
        let baseline = AhaKeyStudioDraft.default
        var current = baseline
        var mode0 = current.draft(for: .mode0)
        var approve = mode0.key(for: .approve)
        approve.description = "Ship"
        mode0.updateKey(approve)
        mode0.oled.statusLine = "Changed"
        current.updateMode(mode0)

        XCTAssertEqual(
            AhaKeyStudioConfigurationSync.dirtyCount(current: current, baseline: baseline),
            2
        )
        XCTAssertTrue(
            AhaKeyStudioConfigurationSync.isDirty(
                .key2,
                in: .mode0,
                current: current,
                baseline: baseline
            )
        )
        XCTAssertEqual(
            AhaKeyStudioConfigurationSync.dirtyParts(
                in: .mode0,
                current: current,
                baseline: baseline
            ),
            [.key2, .oledDisplay]
        )
    }

    func testCursorRejectSelfHealClearsMacroOnlyForDefaultShortcut() {
        var draft = AhaKeyStudioDraft.default
        var mode1 = draft.draft(for: .mode1)
        var reject = mode1.key(for: .reject)
        reject.macro = [
            MacroStep(action: .downKey, param: HIDUsage.backspace),
            MacroStep(action: .upKey, param: HIDUsage.backspace),
        ]
        mode1.updateKey(reject)
        draft.updateMode(mode1)

        let healed = AhaKeyStudioConfigurationSync.applyingCursorRejectMacroSelfHeal(to: draft)
        XCTAssertTrue(healed.draft(for: .mode1).key(for: .reject).macro.isEmpty)
    }

    func testCommandsClearOppositeLayerBeforeWritingShortcutOrMacro() {
        let draft = AhaKeyStudioDraft.default
        let commands = AhaKeyStudioConfigurationSync.commands(for: [.mode0], in: draft)

        XCTAssertEqual(commands.count, 12)
        XCTAssertTrue(commands[0].label.contains("清除 Mode 0 语音键 宏层"))
        XCTAssertEqual(Array(commands[0].data.prefix(6)), [0xAA, 0xBB, 0x73, 0x74, 0x00, 0x00])

        let rejectMacroCommand = commands.first { $0.label.contains("写入 Mode 0 取消键 宏") }
        XCTAssertNotNil(rejectMacroCommand)
        XCTAssertEqual(Array(rejectMacroCommand!.data.prefix(6)), [0xAA, 0xBB, 0x73, 0x74, 0x00, 0x02])
        XCTAssertGreaterThan(rejectMacroCommand!.data.count, 8)
    }
}
