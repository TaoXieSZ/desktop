import Foundation

public struct AhaKeyCommandIntent: Codable, Equatable, Sendable {
    public var step: String
    public var label: String
    public var hex: String
    public var hardwareMutating: Bool

    public init(step: String, label: String, hex: String, hardwareMutating: Bool) {
        self.step = step
        self.label = label
        self.hex = hex
        self.hardwareMutating = hardwareMutating
    }
}

public enum AhaKeyCommandPlanner {
    public static func shortcutPlan(mode: Int, keyIndex: Int, hidCodes: [UInt8], label: String?) throws -> [AhaKeyCommandIntent] {
        try AhaKeyProfileValidator.validateMode(mode)
        try AhaKeyProfileValidator.validateKeyIndex(keyIndex)
        try AhaKeyProfileValidator.validateHIDCodes(hidCodes)

        let modeByte = UInt8(mode)
        let keyByte = UInt8(keyIndex)
        var intents: [AhaKeyCommandIntent] = [
            AhaKeyCommandIntent(step: "clear-macro-layer", label: "Clear Mode\(mode) Key\(keyIndex + 1) macro layer", hex: AhaKeyPacket.setKeyMacro(mode: modeByte, keyIndex: keyByte, macroData: []).hexString, hardwareMutating: true),
            AhaKeyCommandIntent(step: "write-shortcut", label: "Write Mode\(mode) Key\(keyIndex + 1) shortcut", hex: AhaKeyPacket.setKeyMapping(mode: modeByte, keyIndex: keyByte, hidCodes: hidCodes).hexString, hardwareMutating: true),
        ]

        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intents.append(AhaKeyCommandIntent(step: "write-description", label: "Write Mode\(mode) Key\(keyIndex + 1) description", hex: AhaKeyPacket.setKeyDescription(mode: modeByte, keyIndex: keyByte, text: label).hexString, hardwareMutating: true))
        }
        intents.append(AhaKeyCommandIntent(step: "save-config", label: "Save config to device", hex: AhaKeyPacket.saveConfig().hexString, hardwareMutating: true))
        return intents
    }

    public static func applyProfilePlan(_ profile: AhaKeyProfile) throws -> [AhaKeyCommandIntent] {
        try AhaKeyProfileValidator.validate(profile)
        var intents: [AhaKeyCommandIntent] = [
            AhaKeyCommandIntent(step: "validate-profile", label: "Validate profile \(profile.id)", hex: "", hardwareMutating: false)
        ]

        for mode in profile.modes.sorted(by: { $0.id < $1.id }) {
            for key in mode.keys.sorted(by: { $0.index < $1.index }) {
                switch key.action {
                case .shortcut(let shortcut):
                    intents.append(contentsOf: try shortcutPlan(mode: mode.id, keyIndex: key.index, hidCodes: shortcut.hidCodes, label: key.label))
                case .relay(let relay):
                    intents.append(AhaKeyCommandIntent(step: "configure-relay", label: "Configure Mode\(mode.id) Key\(key.index + 1) relay \(relay.kind.rawValue)", hex: "", hardwareMutating: false))
                }
            }
        }
        return intents
    }
}

enum AhaKeyPacket {
    static let header: [UInt8] = [0xAA, 0xBB]
    static let trailer: [UInt8] = [0xCC, 0xDD]
    static let cmdSaveConfig: UInt8 = 0x04
    static let cmdUpdateCustomKey: UInt8 = 0x73
    static let subShortcut: UInt8 = 0x73
    static let subMacro: UInt8 = 0x74
    static let subDescription: UInt8 = 0x75

    static func saveConfig() -> Data {
        Data(header + [cmdSaveConfig] + trailer)
    }

    static func setKeyMapping(mode: UInt8, keyIndex: UInt8, hidCodes: [UInt8]) -> Data {
        Data(header + [cmdUpdateCustomKey, subShortcut, mode, keyIndex] + hidCodes + trailer)
    }

    static func setKeyMacro(mode: UInt8, keyIndex: UInt8, macroData: [UInt8]) -> Data {
        Data(header + [cmdUpdateCustomKey, subMacro, mode, keyIndex] + macroData + trailer)
    }

    static func setKeyDescription(mode: UInt8, keyIndex: UInt8, text: String) -> Data {
        Data(header + [cmdUpdateCustomKey, subDescription, mode, keyIndex] + Array(text.sanitizedASCII(maxLength: 20).utf8) + trailer)
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension String {
    func sanitizedASCII(maxLength: Int) -> String {
        var result = String()
        result.reserveCapacity(min(maxLength, count))
        for scalar in unicodeScalars where scalar.isASCII {
            guard result.utf8.count < maxLength else { break }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
