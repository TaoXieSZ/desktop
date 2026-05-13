import AhaKeyConfigUI
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var unifiedOnboardingCompleted = false
    @AppStorage(AhaKeyAppearanceMode.storageKey) private var appearanceModeRaw = AhaKeyAppearanceMode.light.rawValue
    #if DEBUG
    @State private var debugLiveOnboardingPreview = false
    #endif

    var body: some View {
        ZStack {
            AhaKeyRootWorkspaceView(bleManager: bleManager)
                .allowsHitTesting(unifiedOnboardingCompleted)
            if !unifiedOnboardingCompleted {
                UnifiedTypelessOnboardingView(
                    permissionState: onboardingPermissionState,
                    actions: onboardingActions
                ) { _, _ in
                    unifiedOnboardingCompleted = true
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .all)
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusEffectDisabled()
        .onAppear {
            voiceRelay.showsPermissionOnboarding = false
        }
        .onChange(of: unifiedOnboardingCompleted) { _, completed in
            if !completed {
                voiceRelay.showsPermissionOnboarding = false
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyDebugShowOnboardingPreview)) { _ in
            debugLiveOnboardingPreview = true
        }
        .sheet(isPresented: $debugLiveOnboardingPreview) {
            UnifiedTypelessOnboardingView(
                permissionState: onboardingPermissionState,
                actions: onboardingActions
            ) { _, _ in
                debugLiveOnboardingPreview = false
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .frame(minWidth: 1280, minHeight: 820)
        }
        #endif
    }

    private var appearanceMode: AhaKeyAppearanceMode {
        AhaKeyAppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }

    private var onboardingPermissionState: OnboardingPermissionState {
        OnboardingPermissionState(
            inputMonitoringGranted: voiceRelay.inputMonitoringGranted,
            accessibilityGranted: voiceRelay.accessibilityGranted,
            microphoneGranted: nativeSpeech.microphoneGranted,
            speechRecognitionGranted: nativeSpeech.speechRecognitionGranted,
            voiceSummary: voiceRelay.lastPermissionCheckSummary,
            speechSummary: nativeSpeech.lastPermissionCheckSummary,
            isRecording: nativeSpeech.isRecording,
            transcriptPreview: nativeSpeech.transcriptPreview,
            lastCommittedText: nativeSpeech.lastCommittedText,
            speechStatusMessage: nativeSpeech.statusMessage
        )
    }

    private var onboardingActions: OnboardingPermissionActions {
        OnboardingPermissionActions(
            requestPermissions: {
                voiceRelay.refreshPermissions(requestIfNeeded: true)
                nativeSpeech.refreshPermissions(requestIfNeeded: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    openCombinedVoicePrivacySettingsURL()
                }
            },
            recheckPermissions: {
                voiceRelay.refreshPermissions(deferredTCCRequery: true)
                nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                voiceRelay.showsPermissionOnboarding = false
            },
            openSystemSettings: {
                openCombinedVoicePrivacySettingsURL()
            },
            toggleTryExperience: {
                nativeSpeech.toggleRecordingFromVoiceKey()
                voiceRelay.showsPermissionOnboarding = false
            }
        )
    }
}

@MainActor
private func openCombinedVoicePrivacySettingsURL() {
    let candidates = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "x-apple.systempreferences:com.apple.preference.security?Privacy",
    ]
    for candidate in candidates {
        guard let url = URL(string: candidate) else { continue }
        if NSWorkspace.shared.open(url) {
            return
        }
    }
    let appPaths = [
        "/System/Applications/System Settings.app",
        "/System/Library/CoreServices/Applications/System Settings.app",
        "/System/Applications/System Preferences.app",
    ]
    for path in appPaths where FileManager.default.fileExists(atPath: path) {
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            return
        }
    }
}
