import Foundation

typealias AhaKeyLabeledCommand = (data: Data, label: String)

enum AhaKeyStudioConfigurationSync {
    static func dirtyCount(current: AhaKeyStudioDraft, baseline: AhaKeyStudioDraft) -> Int {
        AhaKeyModeSlot.allCases.reduce(into: 0) { count, mode in
            let currentMode = current.draft(for: mode)
            let baselineMode = baseline.draft(for: mode)

            for role in AhaKeyKeyRole.allCases where currentMode.key(for: role) != baselineMode.key(for: role) {
                count += 1
            }
            if currentMode.oled != baselineMode.oled {
                count += 1
            }
        }
    }

    static func isDirty(
        _ part: AhaKeyStudioPart,
        in mode: AhaKeyModeSlot,
        current: AhaKeyStudioDraft,
        baseline: AhaKeyStudioDraft
    ) -> Bool {
        let currentMode = current.draft(for: mode)
        let baselineMode = baseline.draft(for: mode)

        switch part {
        case .key1, .key2, .key3, .key4:
            guard let role = part.keyRole else { return false }
            return currentMode.key(for: role) != baselineMode.key(for: role)
        case .oledDisplay:
            return currentMode.oled != baselineMode.oled
        case .lightBar, .toggleSwitch:
            return false
        }
    }

    static func dirtyParts(
        in mode: AhaKeyModeSlot,
        current: AhaKeyStudioDraft,
        baseline: AhaKeyStudioDraft
    ) -> Set<AhaKeyStudioPart> {
        Set(AhaKeyStudioPart.allCases.filter { part in
            isDirty(part, in: mode, current: current, baseline: baseline)
        })
    }

    /// Cursor 档「取消键」若仍为默认 backspace 却残留宏，同步会走 0x74 而非单键。
    static func applyingCursorRejectMacroSelfHeal(to draft: AhaKeyStudioDraft) -> AhaKeyStudioDraft {
        var next = draft
        var cursorMode = next.draft(for: .mode1)
        var reject = cursorMode.key(for: .reject)
        let defaultReject = AhaKeyModeDraft.default(for: .mode1).key(for: .reject)

        guard !reject.macro.isEmpty, reject.shortcut == defaultReject.shortcut else {
            return draft
        }

        reject.macro = []
        cursorMode.updateKey(reject)
        next.updateMode(cursorMode)
        return next
    }

    static func commands(
        for modes: [AhaKeyModeSlot],
        in draft: AhaKeyStudioDraft
    ) -> [AhaKeyLabeledCommand] {
        var commands: [AhaKeyLabeledCommand] = []

        for mode in modes {
            let modeDraft = draft.draft(for: mode)
            for role in AhaKeyKeyRole.allCases {
                let key = modeDraft.key(for: role)
                let keyIndex = UInt8(role.rawValue)
                let modeByte = UInt8(mode.rawValue)

                appendKeyCommands(
                    for: key,
                    mode: mode,
                    modeByte: modeByte,
                    keyIndex: keyIndex,
                    to: &commands
                )
            }
        }

        return commands
    }

    private static func appendKeyCommands(
        for key: AhaKeyKeyDraft,
        mode: AhaKeyModeSlot,
        modeByte: UInt8,
        keyIndex: UInt8,
        to commands: inout [AhaKeyLabeledCommand]
    ) {
        if key.usesMacro {
            commands.append((
                data: AhaKeyCommand.setKeyMapping(
                    mode: modeByte,
                    keyIndex: keyIndex,
                    hidCodes: []
                ),
                label: "清除 \(mode.title) \(key.title) 快捷键层（将写入宏）"
            ))
            commands.append((
                data: AhaKeyCommand.setKeyMacro(
                    mode: modeByte,
                    keyIndex: keyIndex,
                    macroData: key.macro.flattenedBytes
                ),
                label: "写入 \(mode.title) \(key.title) 宏: \(key.macro.displaySummary)"
            ))
        } else {
            commands.append((
                data: AhaKeyCommand.setKeyMacro(
                    mode: modeByte,
                    keyIndex: keyIndex,
                    macroData: []
                ),
                label: "清除 \(mode.title) \(key.title) 宏层（将写入快捷键）"
            ))

            if key.shortcut.hidCodes.isEmpty {
                commands.append((
                    data: AhaKeyCommand.setKeyMapping(
                        mode: modeByte,
                        keyIndex: keyIndex,
                        hidCodes: []
                    ),
                    label: "清除 \(mode.title) \(key.title) 快捷键"
                ))
            } else {
                commands.append((
                    data: AhaKeyCommand.setKeyMapping(
                        mode: modeByte,
                        keyIndex: keyIndex,
                        hidCodes: key.shortcut.hidCodes
                    ),
                    label: "写入 \(mode.title) \(key.title) 快捷键: \(key.shortcut.displayLabel)"
                ))
            }
        }

        let sanitizedDescription = key.description.sanitizedASCII(maxLength: 20)
        commands.append((
            data: AhaKeyCommand.setKeyDescription(
                mode: modeByte,
                keyIndex: keyIndex,
                text: key.description
            ),
            label: "写入 \(mode.title) \(key.title) 描述: \(sanitizedDescription.isEmpty ? "空白" : sanitizedDescription)"
        ))
    }
}
