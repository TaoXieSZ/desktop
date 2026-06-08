import Foundation

public let ahaKeyCurrentProfileSchemaVersion = 1

public struct AhaKeyProfile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var modes: [AhaKeyModeProfile]

    public init(schemaVersion: Int = ahaKeyCurrentProfileSchemaVersion, id: String, name: String, modes: [AhaKeyModeProfile]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.modes = modes
    }
}

public struct AhaKeyModeProfile: Codable, Equatable, Sendable {
    public var id: Int
    public var label: String
    public var keys: [AhaKeyPhysicalKeyProfile]

    public init(id: Int, label: String, keys: [AhaKeyPhysicalKeyProfile]) {
        self.id = id
        self.label = label
        self.keys = keys
    }
}

public struct AhaKeyPhysicalKeyProfile: Codable, Equatable, Sendable {
    public var index: Int
    public var label: String
    public var action: AhaKeyAction

    public init(index: Int, label: String, action: AhaKeyAction) {
        self.index = index
        self.label = label
        self.action = action
    }
}

public enum AhaKeyAction: Codable, Equatable, Sendable {
    case shortcut(AhaKeyShortcutAction)
    case relay(AhaKeyRelayAction)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ActionType: String, Codable {
        case shortcut
        case relay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .shortcut:
            self = .shortcut(try AhaKeyShortcutAction(from: decoder))
        case .relay:
            self = .relay(try AhaKeyRelayAction(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .shortcut(let value):
            try value.encode(to: encoder)
        case .relay(let value):
            try value.encode(to: encoder)
        }
    }
}

public struct AhaKeyShortcutAction: Codable, Equatable, Sendable {
    public let type = "shortcut"
    public var hidCodes: [UInt8]

    public init(hidCodes: [UInt8]) {
        self.hidCodes = hidCodes
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case hidCodes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hidCodes = try container.decode([UInt8].self, forKey: .hidCodes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(hidCodes, forKey: .hidCodes)
    }
}

public struct AhaKeyRelayAction: Codable, Equatable, Sendable {
    public let type = "relay"
    public var kind: AhaKeyRelayKind

    public init(kind: AhaKeyRelayKind) {
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(AhaKeyRelayKind.self, forKey: .kind)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(kind, forKey: .kind)
    }
}

public enum AhaKeyRelayKind: String, Codable, Equatable, Sendable {
    case fnGlobe
}
