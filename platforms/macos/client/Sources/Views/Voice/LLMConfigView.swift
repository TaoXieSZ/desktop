import SwiftUI
import VoiceAgent

/// LLM 模型配置面板：API Key、Base URL、Model。
struct LLMConfigView: View {
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var model: String = ""
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false

    private let keychainService = VoiceAgentRuntimeConfig.keychainService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置 AI 模型接口（兼容 OpenAI 格式）")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("API Key")
                    .frame(width: 70, alignment: .leading)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
            }

            HStack(spacing: 8) {
                Text("Base URL")
                    .frame(width: 70, alignment: .leading)
                TextField("https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
            }

            HStack(spacing: 8) {
                Text("Model")
                    .frame(width: 70, alignment: .leading)
                TextField("gpt-4o / claude-sonnet-4-20250514 / ...", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
            }

            HStack {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                }
                Spacer()
                Button("保存并应用") { save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("支持所有 OpenAI 兼容接口（OpenAI、Claude via proxy、Deepseek、通义等）。保存后会立即生效，无需重启。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { load() }
    }

    private func load() {
        apiKey = VoiceAgentKeychain.openAIAPIKey(
            service: keychainService,
            account: VoiceAgentRuntimeConfig.keychainAPIKeyAccount
        ) ?? ""
        baseURL = VoiceAgentKeychain.openAIAPIKey(
            service: keychainService,
            account: VoiceAgentRuntimeConfig.keychainBaseURLAccount
        ) ?? ""
        model = VoiceAgentKeychain.openAIAPIKey(
            service: keychainService,
            account: VoiceAgentRuntimeConfig.keychainModelAccount
        ) ?? ""
    }

    private func save() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        // 验证 URL 格式
        if !trimmedURL.isEmpty {
            guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
                statusMessage = "Base URL 格式无效"
                statusIsError = true
                return
            }
        }

        let ok1 = VoiceAgentKeychain.saveToKeychain(
            service: keychainService,
            account: VoiceAgentRuntimeConfig.keychainAPIKeyAccount,
            value: trimmedKey
        )

        var ok2 = true
        if !trimmedURL.isEmpty {
            ok2 = VoiceAgentKeychain.saveToKeychain(
                service: keychainService,
                account: VoiceAgentRuntimeConfig.keychainBaseURLAccount,
                value: trimmedURL
            )
        }

        var ok3 = true
        if !trimmedModel.isEmpty {
            ok3 = VoiceAgentKeychain.saveToKeychain(
                service: keychainService,
                account: VoiceAgentRuntimeConfig.keychainModelAccount,
                value: trimmedModel
            )
        }

        if ok1 && ok2 && ok3 {
            statusMessage = "已保存，正在重建 AI 会话..."
            statusIsError = false
            // 重建 session 以应用新的 base URL 和 model
            Task {
                await VoiceAgentSessionStore.shared.rebuildSession()
                statusMessage = "已生效"
            }
        } else {
            statusMessage = "保存失败"
            statusIsError = true
        }
    }
}
