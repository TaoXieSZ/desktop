import Combine
import Foundation
import VoiceAgent

/// SwiftUI 主 View 直接复用的 agent 包装。
///
/// 设计意图：把 `VoiceAgentRunner` 的 actor API 转换成 `ObservableObject`，
/// 暴露三件 UI 关心的事情——
/// - `messages`：可直接 `ForEach` 的对话条目；
/// - `isThinking`：调用中状态；
/// - `lastError`：上次失败描述。
///
/// runner 内部事件同时暴露为字符串流与结构化 run event 流：
/// - `events`：兼容旧调试输出；
/// - `runEvents`：用于实时 run tree / subagent 面板。
@MainActor
public final class VoiceAssistantModel: ObservableObject {
    public struct ChatMessage: Identifiable, Equatable {
        public enum Role: String, Sendable, Equatable {
            case user
            case assistant
            case system
        }

        public let id: UUID
        public let role: Role
        public var content: String
        public let createdAt: Date

        public init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.content = content
            self.createdAt = createdAt
        }
    }

    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var isThinking: Bool = false
    @Published public var lastError: String?

    public let systemPrompt: String
    /// runner 内部的工具/子 agent 事件流。可在调试视图里 `for await event in assistantModel.events` 读取。
    public let events: AsyncStream<String>
    /// 结构化 run/subagent/tool 事件流，用于可视化调试面板。
    public let runEvents: AsyncStream<VoiceAgentRunEvent>

    private let runner: VoiceAgentRunner
    private nonisolated let eventContinuation: AsyncStream<String>.Continuation
    private nonisolated let runEventContinuation: AsyncStream<VoiceAgentRunEvent>.Continuation

    private let initialSubAgents: [VoiceSubAgent]

    public init(
        systemPrompt: String,
        model: String = VoiceAgentRuntimeConfig.openAIModel,
        options: VoiceAgentOptions = VoiceAgentOptions(temperature: 0.3, maxTokens: 2048),
        tools: [any VoiceAgentTool] = [],
        subAgents: [VoiceSubAgent] = [],
        client: any VoiceAgentLLMClient = OpenAICompatibleChatClient.configuredOpenAI()
    ) {
        self.systemPrompt = systemPrompt
        self.initialSubAgents = subAgents
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let (runStream, runContinuation) = AsyncStream<VoiceAgentRunEvent>.makeStream()
        self.events = stream
        self.runEvents = runStream
        self.eventContinuation = continuation
        self.runEventContinuation = runContinuation
        let onEvent: VoiceAgentEventCallback = { [continuation] event in
            continuation.yield(event)
        }
        let onRunEvent: VoiceAgentRunEventCallback = { [runContinuation] event in
            runContinuation.yield(event)
        }
        self.runner = VoiceAgentRunner(
            model: model,
            systemPrompt: systemPrompt,
            client: client,
            tools: tools,
            options: options,
            onEvent: onEvent,
            onRunEvent: onRunEvent
        )
    }

    /// Register initial subagents. Call once after init (e.g. in .task modifier).
    public func registerInitialSubAgents() async {
        for agent in initialSubAgents {
            await runner.registerSubAgent(agent)
        }
    }

    deinit {
        eventContinuation.finish()
        runEventContinuation.finish()
    }

    /// 发送一轮用户输入；UI 状态在调用前后自动维护，失败写入 `lastError` 而非抛出。
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isThinking else { return }

        appendUser(trimmed)
        isThinking = true
        lastError = nil
        defer { isThinking = false }

        do {
            let reply = try await runner.send(trimmed)
            appendAssistant(reply)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 仅写入用户气泡而不调用 LLM，便于上层做可逆 UI 编辑。
    public func appendUser(_ content: String) {
        messages.append(ChatMessage(role: .user, content: content))
    }

    /// 在 UI 端预占一个 assistant 气泡（流式或异步追加场景使用）。
    public func appendAssistant(_ content: String) {
        messages.append(ChatMessage(role: .assistant, content: content))
    }

    /// 清空 UI 与 runner 历史，保留 system prompt。
    public func reset() async {
        await runner.reset()
        messages.removeAll()
        lastError = nil
    }

    /// 直接读取 runner 的完整历史（含 system / tool 消息），用于调试或导出。
    public func transcript() async -> [VoiceAgentMessage] {
        await runner.history()
    }

    /// 当前 runner 保存的 root/subagent run 快照，按创建顺序返回。
    public func runSnapshots() async -> [VoiceAgentRunSnapshot] {
        await runner.runSnapshots()
    }

    public func runSnapshot(runID: UUID) async -> VoiceAgentRunSnapshot? {
        await runner.runSnapshot(runID: runID)
    }

    /// Register a named subagent that the root agent can delegate to by name.
    public func registerSubAgent(_ subAgent: VoiceSubAgent) async {
        await runner.registerSubAgent(subAgent)
    }
}

// MARK: - Convenience

public extension VoiceAssistantModel {
    /// 与 `VoiceAgentLiveSession` 默认 prompt 对齐的语音助手实例。
    static func voiceAssistant(
        tools: [any VoiceAgentTool] = [],
        subAgents: [VoiceSubAgent] = [],
        options: VoiceAgentOptions = VoiceAgentOptions(temperature: 0.3, maxTokens: 2048)
    ) -> VoiceAssistantModel {
        VoiceAssistantModel(
            systemPrompt: """
            # 身份

            你是 AhaKey Mode 2 的语音助手总控。用户通过语音或文字向你下达指令，\
            你的职责是理解意图、决定执行策略、交付结果。

            # 你的能力

            1. **工具调用**：你可以调用已注册的工具来完成具体操作（搜索、计算、API 调用等）。\
               工具列表会在可用时自动出现在你的 function calling 接口中。
            2. **委派 subagent**：你可以启动子 agent 来并行处理独立的子任务。\
               子 agent 分两种：
               - **命名专家**：通过 `agent` 参数指定名字，他们有自己的专属工具和记忆，\
                 会记住之前做过的任务，擅长各自的领域。可用专家列表会在 subagent 工具描述中列出。
               - **匿名通用**：不指定 `agent` 参数，临时创建一个通用 agent，适合一次性任务。
            3. **直接回答**：对于简单问题，你自己就是最高效的执行者。

            # 执行策略

            ## 直接完成（默认路径）

            大多数请求你应该自己完成：
            - 简单问答、知识查询、翻译、总结
            - 格式整理、文案润色、单步计算
            - 需要前后文连贯的多轮对话
            - 任何一个人做比拆开更快的事情
            - 需要调用一两个工具就能搞定的事情

            ## 意图闸门

            调用任何有外部副作用的功能前，先判断用户是在“要求你执行动作”，还是只是在陈述自己的计划/状态。

            - 明确执行：用户说“帮我、替我、给我、用 X、发送、创建、打开、执行、查一下”等明确让你做的指令，且必要信息完整，可以继续执行。
            - 陈述计划：用户说“我想、我要、我准备、我等会、我待会、我去、我需要去、我打算”并描述自己要做的事时，默认这是用户自己的计划，不要调用工具。
            - 模糊请求：既可能是用户自己要做，也可能是让你代办时，先确认。例如“我要给张三发 hello”应回复“要我现在替你发送吗？”
            - 缺少信息：动作明确但缺少收件人、内容、目标对象、时间等必要信息时，先追问缺失项，不要猜。
            - 高风险动作：发消息、改配置、调用外部 API、写入或删除数据都属于有副作用动作；表达不清时必须确认。

            例子：
            - “我等会要给智能助手发 hello world” -> 不发送，可问是否需要代发。
            - “帮我给智能助手发 hello world” -> 明确执行，信息完整时进入对应功能。
            - “给智能助手发一下” -> 缺少消息内容，先问要发什么。
            - “我要给智能助手发 hello world” -> 模糊，先确认是否现在由你代发。

            ## 固定专家路由

            - 飞书/Lark 发消息请求：如果可用专家列表中有 `feishu`，必须委派给 `agent: "feishu"`。\
              委派 prompt 必须包含收件人标识（联系人名、邮箱、手机号、直接 ID，或 receive_id + receive_id_type）和要发送的完整消息内容。
            - `feishu` 专家会自己查本地联系人别名和飞书通讯录；不要因为用户只给了名字就要求用户手动找 ID。
            - 如果用户没有给出收件人或消息内容，先追问缺失信息，不要猜测收件人。

            ## 委派 subagent（仅在明确收益时）

            仅当请求可以拆成 2-4 个**彼此独立、互不依赖**的子任务，\
            且并行执行能显著缩短总耗时时，才使用 subagent。

            委派前自问：
            1. 子任务之间是否真的无依赖？如果 B 需要 A 的结果，就不要并行。
            2. 我自己串行做是否也就几秒钟？如果是，不值得委派的开销。
            3. 拆分后每个子任务是否足够自洽？subagent 看不到我们的对话历史。
            4. 有没有命名专家适合这个任务？优先用专家，他们有工具和记忆。

            委派指令要求：
            - `prompt` 必须自包含：把必要背景写进去，不要引用"上面提到的"。
            - 目标明确：说清楚要交付什么格式、什么粒度。
            - 如果有合适的命名专家，用 `agent` 参数指定；否则省略让系统分配匿名 agent。

            # 回复风格

            - 简洁直接，先给结论再展开。
            - 如果委派了 subagent，收到结果后做一次整合性总结再回复用户，\
              不要原样转发子任务的输出。
            - 用户说中文就回中文，说英文就回英文。
            """,
            options: options,
            tools: tools,
            subAgents: subAgents
        )
    }
}
