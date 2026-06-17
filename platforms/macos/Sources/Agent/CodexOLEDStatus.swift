import AppKit
import Foundation

struct CodexOLEDStatus: Equatable {
    var model: String?
    var reasoning: String?
    var contextLeftPercent: Int?
    var turnTokens: Int?
    var event: String?
    var mode: UInt8
    /// 若非空，直接用这些行渲染（供 Claude HUD 等复用同一条上传链，绕过 Codex 专属的 model/token 格式）。
    var overrideLines: [String]? = nil

    var displayLines: [String] {
        if let overrideLines, !overrideLines.isEmpty {
            return overrideLines.prefix(3).map { Self.truncateASCII($0, maxLength: 22) }
        }
        let modelText: String
        switch (Self.clean(model), Self.clean(reasoning)) {
        case let (m?, r?):
            modelText = "\(m) \(r)"
        case let (m?, nil):
            modelText = m
        case let (nil, r?):
            modelText = "model \(r)"
        default:
            modelText = "model --"
        }

        let contextText = contextLeftPercent.map { "Context \($0)% left" } ?? "Context -- left"
        let tokenText = turnTokens.map { "Turn \(Self.formatTokenCount($0)) tok" } ?? "Turn -- tok"
        return [
            Self.truncateASCII(modelText, maxLength: 22),
            Self.truncateASCII(contextText, maxLength: 22),
            Self.truncateASCII(tokenText, maxLength: 22),
        ]
    }

    var displayKey: String {
        displayLines.joined(separator: "\n")
    }

    static func fromHookStdin(_ data: Data, event: String) -> CodexOLEDStatus {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var status = CodexOLEDStatus(
            model: firstString(in: obj, keys: ["model", "model_name", "modelName", "model_id", "modelId"]),
            reasoning: firstString(in: obj, keys: ["reasoning_effort", "reasoningEffort", "effort", "model_reasoning_effort", "modelReasoningEffort"]),
            contextLeftPercent: firstInt(in: obj, keys: ["context_remaining_percent", "contextRemainingPercent", "context_left_percent", "contextLeftPercent", "context_percent_left", "contextPercentLeft"]),
            turnTokens: firstInt(in: obj, keys: ["turn_tokens", "turnTokens", "current_turn_tokens", "currentTurnTokens", "last_turn_tokens", "lastTurnTokens"]),
            event: event,
            mode: 2
        )

        if status.model == nil || status.reasoning == nil {
            let config = readCodexConfigDefaults()
            status.model = status.model ?? config.model
            status.reasoning = status.reasoning ?? config.reasoning
        }
        if status.turnTokens == nil {
            status.turnTokens = deriveTurnTokens(from: obj, event: event)
        }
        status.contextLeftPercent = status.contextLeftPercent.map { min(100, max(0, $0)) }
        return status
    }

    static func fromSocketObject(_ obj: [String: Any]) -> CodexOLEDStatus {
        CodexOLEDStatus(
            model: obj["model"] as? String,
            reasoning: obj["reasoning"] as? String,
            contextLeftPercent: intValue(obj["contextLeftPercent"]),
            turnTokens: intValue(obj["turnTokens"]),
            event: obj["event"] as? String,
            mode: UInt8(clamping: intValue(obj["mode"]) ?? 2),
            overrideLines: (obj["lines"] as? [String]).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func socketPayload() -> [String: Any] {
        [
            "cmd": "codexOledStatus",
            "model": Self.clean(model) ?? NSNull(),
            "reasoning": Self.clean(reasoning) ?? NSNull(),
            "contextLeftPercent": contextLeftPercent.map { Int($0) } ?? NSNull(),
            "turnTokens": turnTokens.map { Int($0) } ?? NSNull(),
            "event": event ?? NSNull(),
            "mode": Int(mode),
            "lines": displayLines,
        ]
    }

    static func formatTokenCount(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    static func truncateASCII(_ text: String, maxLength: Int) -> String {
        let ascii = text.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && !CharacterSet.controlCharacters.contains(scalar) ? Character(scalar) : "?"
        }
        let clean = String(ascii)
        guard clean.count > maxLength else { return clean }
        return String(clean.prefix(max(1, maxLength - 1))) + "~"
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readCodexConfigDefaults() -> (model: String?, reasoning: String?) {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return (nil, nil)
        }
        return (
            topLevelTomlString("model", in: text),
            topLevelTomlString("model_reasoning_effort", in: text)
        )
    }

    private static func topLevelTomlString(_ key: String, in text: String) -> String? {
        var inTable = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inTable = true }
            guard !inTable, line.hasPrefix("\(key)") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func deriveTurnTokens(from obj: [String: Any], event: String) -> Int? {
        guard let total = totalTokens(in: obj) else { return nil }
        let session = firstString(in: obj, keys: ["session_id", "sessionId", "conversation_id", "conversationId"]) ?? "default"
        var state = TokenBaselineStore.load()
        if event == "CodexUserPromptSubmit" {
            state[session] = total
            TokenBaselineStore.save(state)
            return 0
        }
        guard let baseline = state[session] else {
            state[session] = total
            TokenBaselineStore.save(state)
            return nil
        }
        return max(0, total - baseline)
    }

    private static func totalTokens(in obj: [String: Any]) -> Int? {
        if let v = firstInt(in: obj, keys: ["total_tokens", "totalTokens", "used_tokens", "usedTokens"]) {
            return v
        }
        let input = firstInt(in: obj, keys: ["total_input_tokens", "totalInputTokens", "input_tokens", "inputTokens"]) ?? 0
        let output = firstInt(in: obj, keys: ["total_output_tokens", "totalOutputTokens", "output_tokens", "outputTokens"]) ?? 0
        return input + output > 0 ? input + output : nil
    }

    private static func firstString(in obj: Any, keys: Set<String>) -> String? {
        if let dict = obj as? [String: Any] {
            for (key, value) in dict {
                if keys.contains(key), let text = value as? String, clean(text) != nil {
                    return text
                }
            }
            for value in dict.values {
                if let found = firstString(in: value, keys: keys) { return found }
            }
        } else if let array = obj as? [Any] {
            for value in array {
                if let found = firstString(in: value, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func firstInt(in obj: Any, keys: Set<String>) -> Int? {
        if let dict = obj as? [String: Any] {
            for (key, value) in dict where keys.contains(key) {
                if let v = intValue(value) { return v }
            }
            for value in dict.values {
                if let found = firstInt(in: value, keys: keys) { return found }
            }
        } else if let array = obj as? [Any] {
            for value in array {
                if let found = firstInt(in: value, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

private enum TokenBaselineStore {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("AhaKeyConfig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("codex-token-baselines.json")
    }

    static func load() -> [String: Int] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            return [:]
        }
        return obj
    }

    static func save(_ state: [String: Int]) {
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) else { return }
        try? data.write(to: url)
    }
}

enum AgentOLEDTextRenderer {
    static let width = 160
    static let height = 80

    static func render(lines: [String]) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            return Data(repeating: 0, count: width * height * 2)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        for (index, rawLine) in lines.prefix(3).enumerated() {
            let y = 53 - (index * 22)
            let line = CodexOLEDStatus.truncateASCII(rawLine, maxLength: 22)
            (line as NSString).draw(at: NSPoint(x: 6, y: y), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        var data = Data(capacity: width * height * 2)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let color = rep.colorAt(x: x, y: y) ?? .black
                let rgb = color.usingColorSpace(.deviceRGB) ?? .black
                let red = UInt16(max(0, min(255, Int(round(rgb.redComponent * 255)))))
                let green = UInt16(max(0, min(255, Int(round(rgb.greenComponent * 255)))))
                let blue = UInt16(max(0, min(255, Int(round(rgb.blueComponent * 255)))))
                let rgb565 = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
                data.append(UInt8((rgb565 >> 8) & 0xFF))
                data.append(UInt8(rgb565 & 0xFF))
            }
        }
        return data
    }
}
