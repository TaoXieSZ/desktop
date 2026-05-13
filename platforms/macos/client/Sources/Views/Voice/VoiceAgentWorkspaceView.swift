import SwiftUI
import VoiceAgent

struct VoiceAgentWorkspaceView<Header: View>: View {
    @ObservedObject private var session: VoiceAgentSessionStore
    @ObservedObject private var assistantModel: VoiceAssistantModel
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @State private var promptDraft = ""

    var modeEditorHeader: Header
    var onOpenConfiguration: (() -> Void)?

    @MainActor
    init(
        session: VoiceAgentSessionStore,
        modeEditorHeader: Header,
        onOpenConfiguration: (() -> Void)? = nil
    ) {
        self.session = session
        self.assistantModel = session.assistantModel
        self.modeEditorHeader = modeEditorHeader
        self.onOpenConfiguration = onOpenConfiguration
    }

    var body: some View {
        HStack(spacing: 0) {
            canvasPane
            Divider()
            inspectorPane
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Canvas (Left)

    private var canvasPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                modeEditorHeader
                transcriptContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            voiceCaptureBanner
            Divider()
            promptBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(assistantModel.messages) { message in
                        transcriptRow(message)
                    }

                    if let error = assistantModel.lastError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.08))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector (Right)

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                inspectorHeader
                actionButtons

                if session.runSnapshots.isEmpty {
                    emptyRunTree
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(orderedRuns) { run in
                                runRow(run)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(24)

            if let selected = selectedRun {
                Divider()
                runDetailPane(selected)
            }
        }
        .frame(width: 390)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var selectedRun: VoiceAgentRunSnapshot? {
        guard let id = session.selectedRunID else { return nil }
        return session.runSnapshots.first { $0.runID == id }
    }

    private func runDetailPane(_ run: VoiceAgentRunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    run.kind == .root ? "Main Messages" : "Subagent Messages",
                    systemImage: run.kind == .root ? "bubble.left.and.bubble.right" : "arrow.triangle.branch"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    session.selectedRunID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            let visibleMessages = run.messages.filter {
                $0.role == .user || $0.role == .assistant
            }.filter { !$0.content.isEmpty }

            if visibleMessages.isEmpty {
                Text("No messages in this run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(visibleMessages.enumerated()), id: \.offset) { _, msg in
                            runMessageRow(msg)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: 280)
    }

    private func runMessageRow(_ message: VoiceAgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.content)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(message.role == .user ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label("Run Tree", systemImage: "list.bullet.indent")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("\(session.runSnapshots.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(runtimeStatusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if assistantModel.isThinking {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                Task { await resetSession() }
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(assistantModel.isThinking)

            if let onOpenConfiguration {
                Button {
                    onOpenConfiguration()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    // MARK: - Voice Capture Banner

    @ViewBuilder
    private var voiceCaptureBanner: some View {
        if nativeSpeech.isRecording || !nativeSpeech.transcriptPreview.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(nativeSpeech.isRecording ? Color.red : Color.secondary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                    .opacity(nativeSpeech.isRecording ? 1.0 : 0.5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(nativeSpeech.isRecording ? "正在听写…" : "整理文字…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !nativeSpeech.transcriptPreview.isEmpty {
                        Text(nativeSpeech.transcriptPreview)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(nativeSpeech.isRecording ? 0.08 : 0.04))
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.opacity)
        }
    }

    // MARK: - Prompt Bar

    private var promptBar: some View {
        HStack(spacing: 12) {
            TextField("Send a prompt to the main agent", text: $promptDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(assistantModel.isThinking)
                .onSubmit {
                    Task { await sendPrompt() }
                }

            Button {
                Task { await sendPrompt() }
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(assistantModel.isThinking || promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Run Tree Helpers

    private var emptyRunTree: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Idle", systemImage: "circle.dotted")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("No runs yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func runRow(_ run: VoiceAgentRunSnapshot) -> some View {
        Button {
            session.selectedRunID = session.selectedRunID == run.runID ? nil : run.runID
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(statusColor(run.status))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(run.kind == .root ? "Main" : "Subagent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if !run.toolCalls.isEmpty {
                            Text("\(run.toolCalls.count) tools")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(run.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let output = run.output, !output.isEmpty {
                        Text(output)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let error = run.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(run.depth) * 18)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(session.selectedRunID == run.runID ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func transcriptRow(_ message: VoiceAssistantModel.ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.content)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(message.role == .user ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Logic

    private var orderedRuns: [VoiceAgentRunSnapshot] {
        session.runSnapshots.sorted {
            if $0.startedAt == $1.startedAt {
                return $0.runID.uuidString < $1.runID.uuidString
            }
            return $0.startedAt < $1.startedAt
        }
    }

    private var runtimeStatusText: String {
        if VoiceAgentRuntimeConfig.openAIAPIKey == nil {
            return "Keychain API key not found"
        }
        if assistantModel.isThinking {
            return "Running"
        }
        return "Ready"
    }

    private func sendPrompt() async {
        let text = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        promptDraft = ""
        await session.sendPrompt(text)
    }

    private func resetSession() async {
        await session.reset()
    }

    private func statusColor(_ status: VoiceAgentRunStatus) -> Color {
        switch status {
        case .running:
            .orange
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}

// MARK: - Convenience initializer (no header needed)

extension VoiceAgentWorkspaceView where Header == EmptyView {
    @MainActor
    init(
        session: VoiceAgentSessionStore,
        onOpenConfiguration: (() -> Void)? = nil
    ) {
        self.init(
            session: session,
            modeEditorHeader: EmptyView(),
            onOpenConfiguration: onOpenConfiguration
        )
    }
}
