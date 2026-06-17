import Foundation

/// Claude Code 的 OLED HUD 状态。
///
/// Claude 的 hook stdin 不像 Codex 那样带 model/token/context 数字，能稳定拿到的是
/// 「当前事件 + 工具 + 权限模式 + cwd」。所以 HUD 展示「在做什么」而不是「用了多少 token」。
/// 渲染与上传复用 daemon 既有的 `codexOledStatus` 链路（通过 overrideLines 传任意行）。
struct ClaudeOLEDStatus {
    var event: String          // PreToolUse / PostToolUse / PermissionRequest / Stop / ...
    var toolName: String?
    var permissionMode: String?
    var cwd: String?
    var mode: UInt8 = 0        // Claude = 默认层 Mode 0

    /// 三行展示：模型/标题 · 当前活动 · 细节(项目名)。每行 <=22 ASCII。
    var displayLines: [String] {
        let header = Self.modelLabel()
        let activity = Self.activityLine(event: event, toolName: toolName)
        let detail = Self.detailLine(permissionMode: permissionMode, cwd: cwd)
        return [
            CodexOLEDStatus.truncateASCII(header, maxLength: 22),
            CodexOLEDStatus.truncateASCII(activity, maxLength: 22),
            CodexOLEDStatus.truncateASCII(detail, maxLength: 22),
        ]
    }

    var displayKey: String { displayLines.joined(separator: "\n") }

    static func fromHookStdin(_ data: Data, event: String) -> ClaudeOLEDStatus {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ClaudeOLEDStatus(
            event: event,
            toolName: (obj["tool_name"] as? String) ?? (obj["toolName"] as? String),
            permissionMode: (obj["permission_mode"] as? String) ?? (obj["permissionMode"] as? String),
            cwd: obj["cwd"] as? String
        )
    }

    /// 复用 daemon 的 `codexOledStatus` 渲染/上传链：把行直接放进 `lines`（overrideLines）。
    func socketPayload() -> [String: Any] {
        [
            "cmd": "claudeOledStatus",
            "event": event,
            "mode": Int(mode),
            "lines": displayLines,
        ]
    }

    // MARK: - Line builders

    private static func modelLabel() -> String {
        for key in ["ANTHROPIC_MODEL", "CLAUDE_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL"] {
            if let v = ProcessInfo.processInfo.environment[key], !v.trimmingCharacters(in: .whitespaces).isEmpty {
                return shortModel(v)
            }
        }
        return "Claude Code"
    }

    private static func shortModel(_ raw: String) -> String {
        // claude-opus-4-8[1m] -> opus-4-8 ; claude-sonnet-4-6 -> sonnet-4-6
        var s = raw
        if let r = s.range(of: "claude-") { s.removeSubrange(r) }
        if let b = s.firstIndex(of: "[") { s = String(s[..<b]) }
        return s.isEmpty ? "Claude" : s
    }

    private static func activityLine(event: String, toolName: String?) -> String {
        let tool = (toolName?.isEmpty == false) ? toolName! : "tool"
        switch event {
        case "UserPromptSubmit": return "thinking..."
        case "PreToolUse": return "> \(tool)"
        case "PostToolUse": return "\(tool) done"
        case "PermissionRequest": return "ask: \(tool)"
        case "Notification": return "notify"
        case "Stop": return "idle"
        case "SessionStart": return "session start"
        case "SessionEnd": return "session end"
        default: return event
        }
    }

    private static func detailLine(permissionMode: String?, cwd: String?) -> String {
        let project = cwd.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        let mode = permissionMode.flatMap { $0.isEmpty ? nil : $0 }
        switch (project, mode) {
        case let (p?, m?): return "\(p) · \(m)"
        case let (p?, nil): return p
        case let (nil, m?): return m
        default: return "Claude Code"
        }
    }
}
