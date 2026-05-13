import Foundation
import Darwin
import VoiceAgent

@MainActor
func makeDefaultVoiceAssistantModel() -> VoiceAssistantModel {
    VoiceAssistantModel.voiceAssistant(subAgents: defaultVoiceSubAgents())
}

private func defaultVoiceSubAgents() -> [VoiceSubAgent] {
    [VoiceSubAgent.feishuMessenger()]
}

@MainActor
final class VoiceAgentSessionStore: ObservableObject {
    static let shared = VoiceAgentSessionStore()

    @Published private(set) var runSnapshots: [VoiceAgentRunSnapshot] = []
    @Published var selectedRunID: UUID?

    private(set) var assistantModel: VoiceAssistantModel

    private var activeKeyboardMode: AhaKeyModeSlot = .mode0
    private var hasStarted = false
    private var runEventsTask: Task<Void, Never>?
    private var keyboardModeObserver: NSObjectProtocol?
    private var flashedCompletedRunIDs = Set<UUID>()

    private init() {
        self.assistantModel = makeDefaultVoiceAssistantModel()
    }

    func start(keyboardMode: AhaKeyModeSlot = .mode0) {
        activeKeyboardMode = keyboardMode
        installKeyboardModeObserverIfNeeded()
        installVoicePromptConsumer()

        guard !hasStarted else { return }
        hasStarted = true

        runEventsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.assistantModel.registerInitialSubAgents()
            await self.refreshRunSnapshots(selectLatestIfNeeded: false)

            for await event in self.assistantModel.runEvents {
                await self.refreshRunSnapshots(selectLatestIfNeeded: true)
                self.handleRunEvent(event)
            }
        }
    }

    func updateKeyboardMode(_ mode: AhaKeyModeSlot) {
        activeKeyboardMode = mode
    }

    func sendPrompt(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await assistantModel.send(trimmed)
        await refreshRunSnapshots(selectLatestIfNeeded: true)
        selectedRunID = runSnapshots.last?.runID
    }

    func reset() async {
        await assistantModel.reset()
        runSnapshots = []
        selectedRunID = nil
    }

    /// 重新加载飞书 subagent（联系人变更后调用）。
    func reloadFeishuSubAgent() async {
        let feishu = VoiceSubAgent.feishuMessenger()
        await assistantModel.registerSubAgent(feishu)
    }

    /// 重建整个 VoiceAgent session（LLM 配置变更后调用）。
    /// 会丢失当前对话历史。
    func rebuildSession() async {
        runEventsTask?.cancel()
        runEventsTask = nil

        assistantModel = makeDefaultVoiceAssistantModel()
        runSnapshots = []
        selectedRunID = nil
        flashedCompletedRunIDs = Set()
        hasStarted = false

        start(keyboardMode: activeKeyboardMode)
    }

    private func refreshRunSnapshots(selectLatestIfNeeded: Bool) async {
        runSnapshots = await assistantModel.runSnapshots()

        if let selectedRunID, runSnapshots.contains(where: { $0.runID == selectedRunID }) {
            return
        }

        if selectLatestIfNeeded || selectedRunID == nil {
            selectedRunID = runSnapshots.last?.runID
        }
    }

    private func handleRunEvent(_ event: VoiceAgentRunEvent) {
        guard case let .runCompleted(runID, _) = event else { return }
        guard !flashedCompletedRunIDs.contains(runID) else { return }
        guard let run = runSnapshots.first(where: { $0.runID == runID }), run.kind == .root else { return }
        guard activeKeyboardMode != .mode2 else { return }

        flashedCompletedRunIDs.insert(runID)
        Self.flashAgentLight(state: 6, durationMilliseconds: 900)
    }

    private static func flashAgentLight(state: Int, durationMilliseconds: Int) {
        let request: [String: Any] = [
            "cmd": "flash_state",
            "value": state,
            "duration_ms": durationMilliseconds,
        ]

        DispatchQueue.global(qos: .utility).async {
            _ = sendAgentSocketRequest(request, timeout: 1.0)
        }
    }

    private func installVoicePromptConsumer() {
        NativeSpeechTranscriptionService.shared.setFinalTranscriptConsumer { [weak self] text in
            guard let self, self.activeKeyboardMode == .mode2 else { return false }
            Task { @MainActor in
                await self.sendPrompt(text)
            }
            return true
        }
    }

    private func installKeyboardModeObserverIfNeeded() {
        guard keyboardModeObserver == nil else { return }
        keyboardModeObserver = NotificationCenter.default.addObserver(
            forName: .ahaKeyKeyboardWorkModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?["workMode"] as? Int,
                  let mode = AhaKeyModeSlot(rawValue: raw)
            else { return }
            Task { @MainActor in
                self?.updateKeyboardMode(mode)
            }
        }
    }
}

private func sendAgentSocketRequest(_ request: [String: Any], timeout: TimeInterval) -> [String: Any]? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var tv = timeval(
        tv_sec: Int(timeout),
        tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
    )
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    "/tmp/ahakey.sock".withCString { src in
        withUnsafeMutablePointer(to: &addr.sun_path) { dst in
            _ = strcpy(UnsafeMutableRawPointer(dst).assumingMemoryBound(to: CChar.self), src)
        }
    }

    let connected = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return nil }

    guard var payload = try? JSONSerialization.data(withJSONObject: request, options: []) else { return nil }
    payload.append(0x0A)
    let wrote = payload.withUnsafeBytes { ptr -> Int in
        guard let base = ptr.baseAddress else { return -1 }
        return write(fd, base, ptr.count)
    }
    guard wrote == payload.count else { return nil }

    var buf = [UInt8](repeating: 0, count: 1024)
    let n = read(fd, &buf, buf.count)
    guard n > 0 else { return nil }

    return (try? JSONSerialization.jsonObject(with: Data(buf[0 ..< n]))) as? [String: Any]
}
