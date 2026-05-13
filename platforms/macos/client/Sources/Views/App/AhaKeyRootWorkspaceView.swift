import SwiftUI

enum AhaKeyRootWorkspaceMode: String, CaseIterable, Identifiable {
    case classic
    case newWorkbench

    static let storageKey = "AhaKey.RootWorkspaceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            "IDE工作台"
        case .newWorkbench:
            "Agent工作台"
        }
    }
}

struct AhaKeyRootWorkspaceView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @AppStorage(AhaKeyRootWorkspaceMode.storageKey) private var modeRawValue = AhaKeyRootWorkspaceMode.classic.rawValue

    private var mode: AhaKeyRootWorkspaceMode {
        AhaKeyRootWorkspaceMode(rawValue: modeRawValue) ?? .classic
    }

    private var modeBinding: Binding<AhaKeyRootWorkspaceMode> {
        Binding(
            get: { mode },
            set: { modeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        AhaKeyStudioView(
            bleManager: bleManager,
            rootWorkspaceMode: modeBinding
        )
        .onAppear {
            let draft = AhaKeyStudioStore.load() ?? .default
            AgentManager.shared.applyStoredBluetoothPreferenceOnLaunch(bleManager: bleManager)
            VoiceRelayService.shared.start()
            NativeSpeechTranscriptionService.shared.start()
            VoiceRelayService.shared.updateRoutes(from: draft)
            SwitchStateNotifier.shared.bind(to: bleManager)
            NotificationCenter.default.post(
                name: .ahaKeyKeyboardWorkModeChanged,
                object: nil,
                userInfo: ["workMode": bleManager.workMode]
            )
        }
    }
}
