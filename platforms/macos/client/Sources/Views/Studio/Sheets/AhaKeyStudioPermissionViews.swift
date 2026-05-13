import AppKit
import SwiftUI

struct VoicePermissionOnboardingSheet: View {
    @ObservedObject var voiceRelay: VoiceRelayService
    @ObservedObject var nativeSpeech: NativeSpeechTranscriptionService
    @Environment(\.dismiss) private var dismiss

    @State private var fixInProgress = false
    @State private var fixAlertTitle = ""
    @State private var fixAlertMessage = ""
    @State private var fixAlertIsSuccess = false
    @State private var showFixAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("开启语音快捷键权限")
                .font(.system(size: 24, weight: .semibold))

            Text("为了让 AhaKey 的语音键在后台直接接管语音，第一次使用时需要给 AhaKey Studio 打开系统权限。macOS 原生语音还会额外用到苹果自己的麦克风和语音转写能力。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(title: "输入监控", granted: voiceRelay.inputMonitoringGranted, detail: "允许 AhaKey Studio 在后台监听实体语音键。")
                permissionRow(title: "辅助功能", granted: voiceRelay.accessibilityGranted, detail: "允许 AhaKey Studio 把语音键转换成苹果原生转写或 Fn/Globe。")
                permissionRow(title: "麦克风", granted: nativeSpeech.microphoneGranted, detail: "允许 AhaKey Studio 使用苹果原生语音采集。")
                permissionRow(title: "语音转写", granted: nativeSpeech.speechRecognitionGranted, detail: "允许 AhaKey Studio 使用苹果原生语音识别。")
            }

            Text("操作建议：先点「现在申请权限」——macOS 上输入监控/辅助功能常常不再弹系统对话框，约半秒后会自动打开「隐私与安全性」，请在列表中勾选 AhaKey Studio；麦克风和语音在之前就拒绝过的话也不会再弹窗，需在设置里手动打开。若你已在系统设置里改好，可点「我已完成，重新检查」。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("若系统里已勾选允许，本应用仍显示未开启：请完全退出 AhaKey Studio 并再启动一次。输入监控、辅助功能等常按进程生效，只点「重新检查」或从后台切回，有时读到的仍是旧状态，重启后即可与系统设置一致。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("外发 / DMG / Xcode：默认正式包在系统「隐私与安全性」里显示为「AhaKey Studio」；用 Xcode 以 Debug 运行本工程时显示为「AhaKey Studio（调试）」，请按名称分别授权。路径或签名不同也会被系统当成另一款 App。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(voiceRelay.lastPermissionCheckSummary)
                Text(nativeSpeech.lastPermissionCheckSummary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("现在申请权限") {
                    requestStudioPermissionsThenOpenPrivacySettingsIfNeeded(
                        voiceRelay: voiceRelay,
                        nativeSpeech: nativeSpeech
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("我已完成，重新检查") {
                    voiceRelay.refreshPermissions(deferredTCCRequery: true)
                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                }
                .buttonStyle(.bordered)

                RestartToApplyPermissionsButton(title: "退出并重新打开")

                if !nativeSpeech.microphoneGranted || !nativeSpeech.speechRecognitionGranted {
                    Button("打开系统设置") {
                        openStudioNativeSpeechPrivacySettingsURL()
                    }
                    .buttonStyle(.bordered)
                }

                if DebugSigningFixer.isAvailable {
                    Button(fixInProgress ? "重置中…" : "⚙️ 重置开发环境签名（通常不需要）") {
                        runDebugSigningFix()
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(fixInProgress)
                    .help("仅在异常情况下使用：证书过期 / 换 Mac / Team ID 变化 / 钥匙串损坏导致权限失效时，点一下会重新签名 app 并重置 TCC 授权。正式发行版（无源码目录）看不到此按钮。")
                }

                Spacer()

                Button("稍后再说") {
                    voiceRelay.dismissPermissionOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            if voiceRelay.inputMonitoringGranted && voiceRelay.accessibilityGranted {
                Text("基础权限已经齐了。关闭这个弹窗后，AhaKey Studio 会继续在后台监听语音键；如果你使用 macOS 原生语音，麦克风和语音转写也建议一起打开。")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onChange(of: voiceRelay.inputMonitoringGranted) { _, _ in
            closeIfReady()
        }
        .onChange(of: voiceRelay.accessibilityGranted) { _, _ in
            closeIfReady()
        }
        .alert(fixAlertTitle, isPresented: $showFixAlert) {
            if fixAlertIsSuccess {
                Button("立即退出 App") { NSApp.terminate(nil) }
                Button("稍后再退", role: .cancel) {}
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(fixAlertMessage)
        }
    }

    private func runDebugSigningFix() {
        fixInProgress = true
        DebugSigningFixer.run { result in
            fixInProgress = false
            fixAlertIsSuccess = result.success
            fixAlertTitle = result.success ? "修复完成" : "修复失败"
            fixAlertMessage = result.output
            showFixAlert = true
        }
    }

    private func closeIfReady() {
        guard voiceRelay.inputMonitoringGranted && voiceRelay.accessibilityGranted else { return }
        voiceRelay.dismissPermissionOnboarding()
        dismiss()
    }

    private func permissionRow(title: String, granted: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(granted ? "已开启" : "未开启")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

func openStudioNativeSpeechPrivacySettingsURL() {
    let candidates = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "x-apple.systempreferences:com.apple.preference.security?Privacy"
    ]

    for candidate in candidates {
        if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
            break
        }
    }
}

@MainActor
private func openStudioCombinedVoicePrivacySettingsURL() {
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

@MainActor
private func requestStudioPermissionsThenOpenPrivacySettingsIfNeeded(
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService,
    delay: TimeInterval = 0.45
) {
    voiceRelay.refreshPermissions(requestIfNeeded: true)
    nativeSpeech.refreshPermissions(requestIfNeeded: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        openStudioCombinedVoicePrivacySettingsURL()
    }
}

private func relaunchApplicationForPermissionRefresh() {
    let bundlePath = Bundle.main.bundlePath
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundlePath]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // 仍尝试退出，避免卡死；用户可手动再开。
        }
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}

private struct RestartToApplyPermissionsButton: View {
    var title: String = "退出并重新打开…"
    @State private var showConfirm = false

    var body: some View {
        Button(title) { showConfirm = true }
            .buttonStyle(.bordered)
            .help("在系统设置中修改权限后，需重启本应用，检测才会与系统一致。")
            .alert("需要重启以刷新权限", isPresented: $showConfirm) {
                Button("取消", role: .cancel) {}
                Button("立即重启") { relaunchApplicationForPermissionRefresh() }
            } message: {
                Text("将先退出本应用，再自动重新打开。重新打开后「重新检查权限」会读取最新系统状态。")
            }
    }
}
