import Foundation

public enum AhaKeyProfileValidationError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case emptyProfileId
    case invalidProfileId(String)
    case emptyProfileName
    case invalidMode(Int)
    case duplicateMode(Int)
    case invalidKeyIndex(Int)
    case duplicateKey(mode: Int, keyIndex: Int)
    case emptyKeyLabel(mode: Int, keyIndex: Int)
    case invalidHIDCode(Int)
    case tooManyHIDCodes(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "unsupported schema version \(version)"
        case .emptyProfileId:
            return "profile id is required"
        case .invalidProfileId(let id):
            return "profile id must contain only letters, numbers, underscore, or hyphen: \(id)"
        case .emptyProfileName:
            return "profile name is required"
        case .invalidMode(let mode):
            return "mode must be 0...2: \(mode)"
        case .duplicateMode(let mode):
            return "duplicate mode \(mode)"
        case .invalidKeyIndex(let keyIndex):
            return "key index must be 0...3: \(keyIndex)"
        case .duplicateKey(let mode, let keyIndex):
            return "duplicate key \(keyIndex) in mode \(mode)"
        case .emptyKeyLabel(let mode, let keyIndex):
            return "label is required for mode \(mode) key \(keyIndex)"
        case .invalidHIDCode(let code):
            return "hid code must be 0...255: \(code)"
        case .tooManyHIDCodes(let count):
            return "hid code count exceeds firmware limit: \(count)"
        }
    }
}

public enum AhaKeyProfileValidator {
    public static func validate(_ profile: AhaKeyProfile) throws {
        guard profile.schemaVersion == ahaKeyCurrentProfileSchemaVersion else {
            throw AhaKeyProfileValidationError.unsupportedSchemaVersion(profile.schemaVersion)
        }
        guard !profile.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AhaKeyProfileValidationError.emptyProfileId
        }
        try validateProfileId(profile.id)
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AhaKeyProfileValidationError.emptyProfileName
        }

        var seenModes = Set<Int>()
        for mode in profile.modes {
            try validateMode(mode.id)
            guard seenModes.insert(mode.id).inserted else {
                throw AhaKeyProfileValidationError.duplicateMode(mode.id)
            }
            var seenKeys = Set<Int>()
            for key in mode.keys {
                try validateKeyIndex(key.index)
                guard seenKeys.insert(key.index).inserted else {
                    throw AhaKeyProfileValidationError.duplicateKey(mode: mode.id, keyIndex: key.index)
                }
                guard !key.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AhaKeyProfileValidationError.emptyKeyLabel(mode: mode.id, keyIndex: key.index)
                }
                switch key.action {
                case .shortcut(let action):
                    try validateHIDCodes(action.hidCodes)
                case .relay:
                    break
                }
            }
        }
    }

    public static func validateMode(_ mode: Int) throws {
        guard (0...2).contains(mode) else {
            throw AhaKeyProfileValidationError.invalidMode(mode)
        }
    }

    public static func validateProfileId(_ id: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AhaKeyProfileValidationError.emptyProfileId
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AhaKeyProfileValidationError.invalidProfileId(id)
        }
    }

    public static func validateKeyIndex(_ keyIndex: Int) throws {
        guard (0...3).contains(keyIndex) else {
            throw AhaKeyProfileValidationError.invalidKeyIndex(keyIndex)
        }
    }

    public static func validateHIDCodes(_ hidCodes: [UInt8]) throws {
        guard hidCodes.count <= 98 else {
            throw AhaKeyProfileValidationError.tooManyHIDCodes(hidCodes.count)
        }
    }

    public static func validateHIDCode(_ code: Int) throws {
        guard (0...255).contains(code) else {
            throw AhaKeyProfileValidationError.invalidHIDCode(code)
        }
    }
}
