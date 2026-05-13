import AppKit
import SwiftUI
import VoiceAgent

struct AhaKeyVoiceAgentConfigurationSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("VoiceAgent 设置")
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    isPresented = false
                }
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    setupGuideSection

                    GroupBox("AI 模型") {
                        LLMConfigView()
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("飞书 / Lark") {
                        FeishuSetupView()
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 640, height: 760)
    }

    private var setupGuideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("快速开始")
                    .font(.title3.weight(.semibold))
            }

            Text("按照以下步骤完成配置，即可通过语音让 AI 助手帮你发飞书消息。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                guideStep(
                    number: 1,
                    title: "配置 AI 模型",
                    description: "在下方「AI 模型」区域填入你的 API Key。支持 OpenAI、Claude（需代理）、Deepseek、通义等兼容接口。",
                    isDone: llmAPIKeyConfigured
                )

                guideStep(
                    number: 2,
                    title: "配置飞书",
                    description: "在飞书开放平台创建应用获取 App ID 和 Secret，填入下方「飞书」区域后扫码登录。\n需要的权限：im:message（消息）、contact:user:search（通讯录）。",
                    link: ("打开飞书开放平台", "https://open.feishu.cn/app"),
                    isDone: larkCLIInstalled
                )

                guideStep(
                    number: 3,
                    title: "添加联系人（可选）",
                    description: "预设常用群聊或联系人可以加速消息发送。也可以不设置，直接说联系人名字，AI 会自动搜索。",
                    isDone: false
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func guideStep(
        number: Int,
        title: String,
        description: String,
        code: String? = nil,
        link: (String, String)? = nil,
        isDone: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : Color.blue.opacity(0.15))
                    .frame(width: 24, height: 24)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let code {
                    Text(code)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.05)))
                }

                if let link {
                    Button(link.0) {
                        if let url = URL(string: link.1) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var larkCLIInstalled: Bool {
        var paths: [String] = []
        if let bundlePath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("lark-cli").path {
            paths.append(bundlePath)
        }
        paths += [
            "/usr/local/bin/lark-cli",
            "/opt/homebrew/bin/lark-cli",
            ProcessInfo.processInfo.environment["HOME"].map { "\($0)/.npm-global/bin/lark-cli" },
        ].compactMap { $0 }
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private var llmAPIKeyConfigured: Bool {
        VoiceAgentRuntimeConfig.openAIAPIKey != nil
    }
}
