import Foundation

public struct AhaKeyProfileStore: Sendable {
    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL = AhaKeyProfileStore.defaultRootDirectory()) {
        self.rootDirectory = rootDirectory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public static func defaultRootDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKey/profiles", isDirectory: true)
    }

    public func profileURL(id: String) throws -> URL {
        try AhaKeyProfileValidator.validateProfileId(id)
        let root = rootDirectory.standardizedFileURL
        let url = root.appendingPathComponent("\(id).json").standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard url.path.hasPrefix(rootPath) else {
            throw AhaKeyProfileValidationError.invalidProfileId(id)
        }
        return url
    }

    public func readProfile(id: String) throws -> AhaKeyProfile {
        let url = try profileURL(id: id)
        do {
            return try readValidatedProfile(from: url, expectedId: id)
        } catch {
            let backup = backupURL(for: url)
            guard FileManager.default.fileExists(atPath: backup.path) else { throw error }
            return try readValidatedProfile(from: backup, expectedId: id)
        }
    }

    public func listProfiles() throws -> [AhaKeyProfile] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".backup.json") }
            .compactMap { url in
                do {
                    let expectedId = url.deletingPathExtension().lastPathComponent
                    return try readValidatedProfile(from: url, expectedId: expectedId)
                } catch {
                    let expectedId = url.deletingPathExtension().lastPathComponent
                    return try? readValidatedProfile(from: backupURL(for: url), expectedId: expectedId)
                }
            }
            .sorted { $0.id < $1.id }
    }

    public func writeProfile(_ profile: AhaKeyProfile) throws -> URL {
        try AhaKeyProfileValidator.validate(profile)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let url = try profileURL(id: profile.id)
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = backupURL(for: url)
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.copyItem(at: url, to: backup)
        }
        let data = try encoder.encode(profile)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func migrateIfNeeded(_ profile: AhaKeyProfile) throws -> AhaKeyProfile {
        if profile.schemaVersion == ahaKeyCurrentProfileSchemaVersion {
            try AhaKeyProfileValidator.validate(profile)
            return profile
        }
        if profile.schemaVersion > ahaKeyCurrentProfileSchemaVersion {
            throw AhaKeyProfileValidationError.unsupportedSchemaVersion(profile.schemaVersion)
        }
        throw AhaKeyProfileValidationError.unsupportedSchemaVersion(profile.schemaVersion)
    }

    public func backupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private func readValidatedProfile(from url: URL, expectedId: String? = nil) throws -> AhaKeyProfile {
        let data = try Data(contentsOf: url)
        let profile = try decoder.decode(AhaKeyProfile.self, from: data)
        let migrated = try migrateIfNeeded(profile)
        if let expectedId, migrated.id != expectedId {
            throw AhaKeyProfileValidationError.invalidProfileId(migrated.id)
        }
        return migrated
    }
}
