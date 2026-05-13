import SwiftUI
import VoiceAgent

/// 飞书集成配置面板：用户填入飞书应用凭证 → lark-cli 配置 → 扫码登录 → 联系人管理。
/// lark-cli 二进制内置于 app bundle，用户无需安装 Node.js。
struct FeishuSetupView: View {
    @State private var appID: String = ""
    @State private var appSecret: String = ""
    @State private var larkCLIStatus: LarkCLIStatus = .checking
    @State private var loginURL: String?
    @State private var deviceCode: String?
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            larkCLISection
            Divider()
            FeishuContactsConfigView()
        }
        .onAppear { checkLarkCLI() }
    }

    // MARK: - lark-cli 配置与登录

    private var larkCLISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("飞书账号")
                    .font(.callout.weight(.semibold))
                Spacer()
                statusBadge
            }

            switch larkCLIStatus {
            case .checking:
                ProgressView("检查中…")
                    .controlSize(.small)

            case .notInstalled:
                Text("lark-cli 未找到，请联系开发者。")
                    .font(.caption)
                    .foregroundStyle(.red)

            case .notConfigured:
                VStack(alignment: .leading, spacing: 8) {
                    Text("请填入飞书开放平台应用的凭证（从 open.feishu.cn 创建应用后获取）：")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("App ID")
                            .frame(width: 80, alignment: .leading)
                        TextField("cli_xxxxxxxxx", text: $appID)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                    }

                    HStack(spacing: 8) {
                        Text("App Secret")
                            .frame(width: 80, alignment: .leading)
                        SecureField("填入 App Secret", text: $appSecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                    }

                    Button("配置并登录") { configureLarkCLI() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(appID.trimmingCharacters(in: .whitespaces).isEmpty
                            || appSecret.trimmingCharacters(in: .whitespaces).isEmpty)
                }

            case .notLoggedIn:
                if let loginURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("请在浏览器中打开以下链接，用飞书扫码完成授权：")
                            .font(.caption)
                        Text(loginURL)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                            .lineLimit(3)

                        HStack {
                            Button("复制链接") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(loginURL, forType: .string)
                            }
                            .controlSize(.small)

                            Button("在浏览器打开") {
                                if let url = URL(string: loginURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .controlSize(.small)

                            Button("已完成授权") { completeLogin() }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("已配置应用，点击登录完成用户授权。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("登录飞书") { startLogin() }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                            Button("重新配置") { larkCLIStatus = .notConfigured }
                                .controlSize(.small)
                        }
                    }
                }

            case .loggedIn(let user):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已登录: \(user)")
                        .font(.caption)
                }
                HStack {
                    Button("重新登录") { startLogin() }
                        .controlSize(.small)
                    Button("重新配置") { larkCLIStatus = .notConfigured }
                        .controlSize(.small)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch larkCLIStatus {
        case .loggedIn:
            Text("已连接")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.15)))
                .foregroundStyle(.green)
        case .notLoggedIn:
            Text("未登录")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .foregroundStyle(.orange)
        case .notConfigured:
            Text("未配置")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .foregroundStyle(.orange)
        case .notInstalled:
            Text("异常")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red.opacity(0.15)))
                .foregroundStyle(.red)
        case .checking:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func checkLarkCLI() {
        Task.detached {
            guard let path = Self.findLarkCLI() else {
                await MainActor.run { larkCLIStatus = .notInstalled }
                return
            }

            // 检查是否已配置（有 app 凭证）
            let configOutput = Self.runProcess(path, args: ["config", "show"])
            if configOutput.contains("not configured") || configOutput.contains("no app") || configOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { larkCLIStatus = .notConfigured }
                return
            }

            // 检查登录状态
            let authOutput = Self.runProcess(path, args: ["auth", "status"])
            if authOutput.contains("logged_in") || authOutput.contains("user") {
                let user = Self.extractUser(from: authOutput)
                await MainActor.run { larkCLIStatus = .loggedIn(user: user) }
            } else {
                await MainActor.run { larkCLIStatus = .notLoggedIn }
            }
        }
    }

    private func configureLarkCLI() {
        Task.detached {
            guard let path = Self.findLarkCLI() else { return }
            let trimmedID = await appID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSecret = await appSecret.trimmingCharacters(in: .whitespacesAndNewlines)

            // 用用户填入的凭证配置 lark-cli
            let process = Process()
            let pipe = Pipe()
            let inputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["config", "init", "--app-id", trimmedID, "--app-secret-stdin", "--brand", "feishu"]
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = inputPipe
            do { try process.run() } catch {
                await MainActor.run {
                    statusMessage = "配置失败: \(error.localizedDescription)"
                    statusIsError = true
                }
                return
            }
            inputPipe.fileHandleForWriting.write(Data((trimmedSecret + "\n").utf8))
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            // 配置完后直接进入登录流程
            await MainActor.run { startLogin() }
        }
    }

    private func startLogin() {
        Task.detached {
            guard let path = Self.findLarkCLI() else { return }

            let output = Self.runProcess(path, args: [
                "auth", "login",
                "--domain", "im,contact",
                "--json", "--no-wait",
            ])

            if let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["device_code"] as? String,
               let url = json["verification_url"] as? String {
                await MainActor.run {
                    deviceCode = code
                    loginURL = url
                    larkCLIStatus = .notLoggedIn
                    statusMessage = nil
                    statusIsError = false
                }
            } else {
                await MainActor.run {
                    statusMessage = "启动登录失败: \(output.prefix(200))"
                    statusIsError = true
                }
            }
        }
    }

    private func completeLogin() {
        guard let code = deviceCode else { return }
        Task.detached {
            guard let path = Self.findLarkCLI() else { return }
            let output = Self.runProcess(path, args: ["auth", "login", "--device-code", code])

            if output.contains("OK") || output.contains("logged_in") || output.contains("success") {
                let user = Self.extractUser(from: output)
                await MainActor.run {
                    larkCLIStatus = .loggedIn(user: user)
                    loginURL = nil
                    deviceCode = nil
                    statusMessage = nil
                    statusIsError = false
                }
            } else {
                await MainActor.run {
                    statusMessage = "登录失败，请确认已在浏览器完成授权后重试"
                    statusIsError = true
                }
            }
        }
    }

    // MARK: - Helpers

    nonisolated private static func findLarkCLI() -> String? {
        var paths: [String] = []

        // 优先 app bundle 内置
        if let bundlePath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("lark-cli").path,
           FileManager.default.fileExists(atPath: bundlePath) {
            paths.append(bundlePath)
        }

        paths += [
            "/usr/local/bin/lark-cli",
            "/opt/homebrew/bin/lark-cli",
            ProcessInfo.processInfo.environment["HOME"].map { "\($0)/.npm-global/bin/lark-cli" },
        ].compactMap { $0 }

        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    nonisolated private static func runProcess(_ execPath: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func extractUser(from output: String) -> String {
        if let range = output.range(of: "user: ") ?? output.range(of: "name: ") {
            let after = output[range.upperBound...]
            let name = after.prefix(while: { $0 != " " && $0 != "(" && $0 != "\n" && $0 != "," })
            if !name.isEmpty { return String(name) }
        }
        return "已授权"
    }
}

// MARK: - Status enum

private enum LarkCLIStatus {
    case checking
    case notInstalled
    case notConfigured
    case notLoggedIn
    case loggedIn(user: String)
}
