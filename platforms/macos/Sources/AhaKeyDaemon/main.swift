import AhaKeyCore
import ApplicationServices
import Darwin
import Foundation

struct AhaKeyDaemon {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--self-test" {
            let profile = AhaKeyProfile(
                id: "default",
                name: "Default",
                modes: [
                    AhaKeyModeProfile(
                        id: 1,
                        label: "AI",
                        keys: [
                            AhaKeyPhysicalKeyProfile(index: 0, label: "Doubao Fn", action: .shortcut(AhaKeyShortcutAction(hidCodes: [0xe7]))),
                            AhaKeyPhysicalKeyProfile(index: 1, label: "Approve / Bypass", action: .shortcut(AhaKeyShortcutAction(hidCodes: [0x6e]))),
                            AhaKeyPhysicalKeyProfile(index: 2, label: "Deny", action: .shortcut(AhaKeyShortcutAction(hidCodes: [0x6f]))),
                        ]
                    )
                ]
            )
            let plan = try AhaKeyCommandPlanner.applyProfilePlan(profile)
            writeJSON(["ok": true, "name": "ahakeyd", "schemaVersion": ahaKeyCurrentProfileSchemaVersion, "commands": plan.map { ["step": $0.step, "label": $0.label, "hex": $0.hex] }])
            return
        }

        if args.first == "--serve" {
            let options = DaemonOptions.parse(args)
            let server = try AhaKeyHTTPServer(options: options)
            try server.run()
            return
        }

        writeJSON([
            "ok": true,
            "name": "ahakeyd",
            "mode": "idle",
            "message": "run with --serve to start the loopback daemon API",
        ])
    }

    private static func writeJSON(_ object: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("failed to encode JSON: \(error.localizedDescription)\n".utf8))
            Foundation.exit(2)
        }
    }
}

try AhaKeyDaemon.main()

struct DaemonOptions: Sendable {
    var host = "127.0.0.1"
    var port: UInt16 = 17342
    var token = ProcessInfo.processInfo.environment["AHAKEYD_TOKEN"] ?? UUID().uuidString
    var profileRoot: URL?
    var allowedOrigins: Set<String> = ["http://127.0.0.1:5173", "http://localhost:5173", "http://127.0.0.1:5174", "http://localhost:5174", "http://127.0.0.1:4173", "http://localhost:4173"]

    static func parse(_ args: [String]) -> DaemonOptions {
        var options = DaemonOptions()
        var index = 1
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--port":
                if index + 1 < args.count, let value = UInt16(args[index + 1]) {
                    options.port = value
                    index += 2
                } else {
                    index += 1
                }
            case "--token":
                if index + 1 < args.count {
                    options.token = args[index + 1]
                    index += 2
                } else {
                    index += 1
                }
            case "--profile-root":
                if index + 1 < args.count {
                    options.profileRoot = URL(fileURLWithPath: args[index + 1], isDirectory: true)
                    index += 2
                } else {
                    index += 1
                }
            case "--allow-origin":
                if index + 1 < args.count {
                    options.allowedOrigins.insert(args[index + 1])
                    index += 2
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        return options
    }
}

final class AhaKeyHTTPServer: @unchecked Sendable {
    private let options: DaemonOptions
    private let store: AhaKeyProfileStore
    private let trustPolicy: AhaKeyTrustPolicy
    private let decoder = JSONDecoder()
    private let terminalApprovalRelay = TerminalApprovalRelay()
    private var state = DaemonRuntimeState()

    init(options: DaemonOptions) throws {
        self.options = options
        self.store = AhaKeyProfileStore(rootDirectory: options.profileRoot ?? AhaKeyProfileStore.defaultRootDirectory())
        self.trustPolicy = AhaKeyTrustPolicy(
            allowedHosts: ["127.0.0.1", "127.0.0.1:\(options.port)", "localhost", "localhost:\(options.port)"],
            allowedOrigins: options.allowedOrigins,
            token: options.token
        )
        terminalApprovalRelay.start()
    }

    func run() throws {
        let serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = options.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard listen(serverFD, 16) == 0 else {
            close(serverFD)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        print("ahakeyd listening on http://127.0.0.1:\(options.port)")
        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { continue }
            autoreleasepool {
                configureClientSocket(clientFD)
                let requestData = readRequest(fd: clientFD)
                let response: HTTPResponse
                if let requestData, let request = HTTPRequest(data: requestData) {
                    response = route(request)
                } else {
                    response = .json(status: 400, body: ["ok": false, "error": "invalid_request"])
                }
                response.data.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else { return }
                    _ = Darwin.write(clientFD, baseAddress, buffer.count)
                }
                close(clientFD)
            }
        }
    }

    private func configureClientSocket(_ fd: Int32) {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func readRequest(fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var expectedLength: Int?
        while data.count < 128 * 1024 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
            if expectedLength == nil, let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = data[..<headerEnd.lowerBound]
                let headerText = String(decoding: headerData, as: UTF8.self)
                let contentLength = headerText
                    .components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") } ?? 0
                expectedLength = headerEnd.upperBound + contentLength
            }
            if let expectedLength, data.count >= expectedLength {
                break
            }
        }
        return data.isEmpty ? nil : data
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        let corsOrigin = allowedCORSOrigin(for: request)
        do {
            if let denied = authorizeHost(request, corsOrigin: corsOrigin) {
                return denied
            }
            if request.method == "OPTIONS" {
                return .empty(status: 204, corsOrigin: corsOrigin)
            }
            if request.method == "GET", request.path == "/health" {
                return .json(status: 200, body: ["ok": true, "name": "ahakeyd", "host": options.host, "port": Int(options.port), "schemaVersion": ahaKeyCurrentProfileSchemaVersion], corsOrigin: corsOrigin)
            }
            if request.method == "GET", request.path == "/api/status" {
                let permissionSnapshot = permissions()
                return .json(status: 200, body: [
                    "ok": true,
                    "device": ["connected": false, "status": "not_connected", "blocker": "device_not_connected"],
                    "activeProfileId": state.activeProfileId ?? NSNull(),
                    "profileCount": try store.listProfiles().count,
                    "lastError": state.lastError ?? NSNull(),
                    "relay": relayStatus(permissionSnapshot),
                    "approvalRelay": terminalApprovalRelay.status(),
                ], corsOrigin: corsOrigin)
            }
            if request.method == "GET", request.path == "/api/permissions" {
                return .json(status: 200, body: ["ok": true, "permissions": permissions()], corsOrigin: corsOrigin)
            }
            if request.method == "GET", request.path == "/api/profiles" {
                return .json(status: 200, body: ["ok": true, "profiles": try store.listProfiles().map(profileSummary)], corsOrigin: corsOrigin)
            }
            if request.method == "GET", request.path.hasPrefix("/api/profiles/") {
                let id = String(request.path.dropFirst("/api/profiles/".count))
                return .json(status: 200, body: ["ok": true, "profile": try jsonObject(store.readProfile(id: id))], corsOrigin: corsOrigin)
            }
            if request.method == "PUT", request.path.hasPrefix("/api/profiles/") {
                if let denied = authorize(request, stateChanging: true, corsOrigin: corsOrigin) { return denied }
                let id = String(request.path.dropFirst("/api/profiles/".count))
                try AhaKeyProfileValidator.validateProfileId(id)
                let profile = try decoder.decode(AhaKeyProfile.self, from: request.body)
                guard profile.id == id else {
                    return .json(status: 400, body: ["ok": false, "error": "profile_id_mismatch"], corsOrigin: corsOrigin)
                }
                let url = try store.writeProfile(profile)
                state.activeProfileId = profile.id
                state.lastError = nil
                return .json(status: 200, body: ["ok": true, "profile": try jsonObject(profile), "path": url.path], corsOrigin: corsOrigin)
            }
            if request.method == "POST", request.path == "/api/apply" {
                if let denied = authorize(request, stateChanging: true, corsOrigin: corsOrigin) { return denied }
                let payload = try decoder.decode(ApplyRequest.self, from: request.body)
                let profile = payload.profile
                let commands = try AhaKeyCommandPlanner.applyProfilePlan(profile)
                let blockers = relayBlockers(profile: profile, permissions: permissions())
                let hardware = payload.dryRun
                    ? HardwareApplyResult(dryRun: true, hardwareMutated: false, results: [])
                    : try applyProfileToHardware(profile)
                state.activeProfileId = profile.id
                state.lastError = nil
                return .json(status: 200, body: [
                    "ok": true,
                    "dryRun": payload.dryRun,
                    "hardwareMutated": hardware.hardwareMutated,
                    "commands": commands.map(commandJSON),
                    "blockers": blockers,
                    "hardwareResults": hardware.results,
                ], corsOrigin: corsOrigin)
            }
            return .json(status: 404, body: ["ok": false, "error": "not_found"], corsOrigin: corsOrigin)
        } catch {
            let message = describe(error)
            state.lastError = message
            return .json(status: 400, body: ["ok": false, "error": message], corsOrigin: corsOrigin)
        }
    }

    private func authorizeHost(_ request: HTTPRequest, corsOrigin: String?) -> HTTPResponse? {
        let decision = trustPolicy.authorize(host: request.headers["host"], origin: nil, token: nil, stateChanging: false)
        guard !decision.allowed else { return nil }
        return .json(status: 403, body: ["ok": false, "error": decision.reason ?? "denied"], corsOrigin: corsOrigin)
    }

    private func authorize(_ request: HTTPRequest, stateChanging: Bool, corsOrigin: String?) -> HTTPResponse? {
        let decision = trustPolicy.authorize(
            host: request.headers["host"],
            origin: request.headers["origin"],
            token: request.headers["x-ahakey-token"],
            stateChanging: stateChanging
        )
        guard !decision.allowed else { return nil }
        let reason = decision.reason ?? "denied"
        let status = reason == "missing_token" || reason == "invalid_token" ? 401 : 403
        return .json(status: status, body: ["ok": false, "error": reason], corsOrigin: corsOrigin)
    }

    private func allowedCORSOrigin(for request: HTTPRequest) -> String? {
        guard let origin = request.headers["origin"], trustPolicy.allowedOrigins.contains(origin) else {
            return nil
        }
        return origin
    }

    private func profileSummary(_ profile: AhaKeyProfile) -> [String: Any] {
        ["id": profile.id, "name": profile.name, "schemaVersion": profile.schemaVersion]
    }

    private func commandJSON(_ command: AhaKeyCommandIntent) -> [String: Any] {
        ["step": command.step, "label": command.label, "hex": command.hex, "hardwareMutating": command.hardwareMutating]
    }

    private func permissions() -> [String: Any] {
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        let postEvent = CGPreflightPostEventAccess()
        return [
            "bluetooth": "unknown",
            "accessibility": accessibility,
            "inputMonitoring": inputMonitoring,
            "postEvent": postEvent,
        ]
    }

    private func relayStatus(_ permissions: [String: Any]) -> [String: Any] {
        let blockers = relayPermissionBlockers(permissions)
        return [
            "ready": blockers.isEmpty,
            "kind": "fnGlobe",
            "blockers": blockers,
        ]
    }

    private func relayBlockers(profile: AhaKeyProfile, permissions: [String: Any]) -> [[String: Any]] {
        guard profileContainsRelay(profile) else { return [] }
        return relayPermissionBlockers(permissions).map { ["kind": "fnGlobe", "reason": $0] }
    }

    private func relayPermissionBlockers(_ permissions: [String: Any]) -> [String] {
        var blockers: [String] = []
        if permissions["accessibility"] as? Bool != true {
            blockers.append("accessibility_missing")
        }
        if permissions["inputMonitoring"] as? Bool != true {
            blockers.append("input_monitoring_missing")
        }
        if permissions["postEvent"] as? Bool != true {
            blockers.append("post_event_missing")
        }
        return blockers
    }

    private func profileContainsRelay(_ profile: AhaKeyProfile) -> Bool {
        profile.modes.contains { mode in
            mode.keys.contains { key in
                if case .relay = key.action {
                    return true
                }
                return false
            }
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func applyProfileToHardware(_ profile: AhaKeyProfile) throws -> HardwareApplyResult {
        try AhaKeyProfileValidator.validate(profile)
        var results: [[String: Any]] = []
        var hardwareMutated = false

        for mode in profile.modes.sorted(by: { $0.id < $1.id }) {
            for key in mode.keys.sorted(by: { $0.index < $1.index }) {
                switch key.action {
                case .shortcut(let shortcut):
                    let result = try runBridgeHelper(
                        mode: mode.id,
                        keyIndex: key.index,
                        hidCodes: shortcut.hidCodes,
                        label: key.label
                    )
                    results.append([
                        "mode": mode.id,
                        "keyIndex": key.index,
                        "label": key.label,
                        "helper": result,
                    ])
                    if result["hardwareMutated"] as? Bool == true {
                        hardwareMutated = true
                    }
                case .relay(let relay):
                    results.append([
                        "mode": mode.id,
                        "keyIndex": key.index,
                        "label": key.label,
                        "relay": relay.kind.rawValue,
                        "hardwareMutated": false,
                        "reason": "relay_action_not_written_to_firmware",
                    ])
                }
            }
        }

        return HardwareApplyResult(dryRun: false, hardwareMutated: hardwareMutated, results: results)
    }

    private func runBridgeHelper(mode: Int, keyIndex: Int, hidCodes: [UInt8], label: String) throws -> [String: Any] {
        let process = Process()
        let helperURL = helperExecutableURL()
        process.executableURL = helperURL.executable
        process.arguments = helperURL.arguments + [
            "apply-shortcut",
            "--mode", String(mode),
            "--key-index", String(keyIndex),
            "--hid-codes", hidCodes.map(String.init).joined(separator: ","),
            "--label", label,
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let object = try JSONSerialization.jsonObject(with: output) as? [String: Any]
        guard var object else {
            throw AhaKeyDaemonError.helperFailed("helper did not return JSON: \(stderrText)")
        }
        object["stderr"] = stderrText
        object["exitCode"] = Int(process.terminationStatus)
        guard process.terminationStatus == 0, object["ok"] as? Bool == true else {
            throw AhaKeyDaemonError.helperFailed(object["error"] as? String ?? stderrText)
        }
        return object
    }

    private func helperExecutableURL() -> (executable: URL, arguments: [String]) {
        let current = URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = current.deletingLastPathComponent().appendingPathComponent("AhaKeyWebBridgeHelper")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return (sibling, [])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["swift", "run", "--package-path", "platforms/macos", "AhaKeyWebBridgeHelper"])
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "key_not_found \(key.stringValue): \(context.debugDescription)"
        case DecodingError.typeMismatch(let type, let context):
            return "type_mismatch \(type): \(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context):
            return "value_not_found \(type): \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "data_corrupted: \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
}

enum AhaKeyDaemonError: Error, LocalizedError {
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperFailed(let detail):
            return "hardware_apply_failed: \(detail)"
        }
    }
}

struct HardwareApplyResult {
    var dryRun: Bool
    var hardwareMutated: Bool
    var results: [[String: Any]]
}

struct DaemonRuntimeState {
    var activeProfileId: String?
    var lastError: String?
}

struct ApplyRequest: Codable {
    var dryRun: Bool
    var profile: AhaKeyProfile
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init?(data: Data) {
        guard let raw = String(data: data, encoding: .utf8),
              let range = raw.range(of: "\r\n\r\n") else { return nil }
        let head = String(raw[..<range.lowerBound])
        let bodyText = String(raw[range.upperBound...])
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        method = parts[0]
        let urlParts = parts[1].split(separator: "?", maxSplits: 1).map(String.init)
        path = urlParts[0]
        var parsed: [String: String] = [:]
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            parsed[pieces[0].lowercased()] = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        headers = parsed
        if let lengthText = parsed["content-length"],
           let length = Int(lengthText),
           let bodyData = bodyText.data(using: .utf8) {
            body = Data(bodyData.prefix(length))
        } else {
            body = Data(bodyText.utf8)
        }
    }
}

struct HTTPResponse {
    var data: Data

    static func empty(status: Int, corsOrigin: String? = nil) -> HTTPResponse {
        build(status: status, contentType: "text/plain; charset=utf-8", body: Data(), corsOrigin: corsOrigin)
    }

    static func json(status: Int, body: [String: Any], corsOrigin: String? = nil) -> HTTPResponse {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } catch {
            data = Data("{\"ok\":false,\"error\":\"json_encode_failed\"}".utf8)
        }
        return build(status: status, contentType: "application/json; charset=utf-8", body: data, corsOrigin: corsOrigin)
    }

    private static func build(status: Int, contentType: String, body: Data, corsOrigin: String?) -> HTTPResponse {
        let reason = statusReason(status)
        var headers = "HTTP/1.1 \(status) \(reason)\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        if let corsOrigin {
            headers += "Access-Control-Allow-Origin: \(corsOrigin)\r\n"
        }
        headers += "Access-Control-Allow-Methods: GET,PUT,POST,OPTIONS\r\n"
        headers += "Access-Control-Allow-Headers: Content-Type,X-AhaKey-Token\r\n"
        headers += "Connection: close\r\n\r\n"
        var data = Data(headers.utf8)
        data.append(body)
        return HTTPResponse(data: data)
    }

    private static func statusReason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}
