import AhaKeyConfigUI
import SwiftUI

struct AhaKeyStudioAIWorkspace: View {
    var body: some View {
        VStack(spacing: 0) {
            AhaKeyStudioWorkspaceHeader(
                title: "AI 引擎",
                subtitle: "管理本地优先的语音识别、后处理与模型运行状态。",
                trailing: {
                    Text("本地离线")
                        .font(AhaKeyUI.Font.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .ahaKeyPill()
                }
            )
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("此页将承载引擎提供方、模型路径、推理参数等设置。当前为本地 SwiftUI 占位实现；请从侧栏进入配置台继续配置键盘与 Inspector 主流程。")
                    .font(AhaKeyUI.Font.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Label("本地优先", systemImage: "internaldrive")
                    Label("模型参数", systemImage: "slider.horizontal.3")
                    Label("运行状态", systemImage: "waveform.path.ecg")
                }
                .font(AhaKeyUI.Font.subhead)
                .ahaKeyPanel()
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AhaKeyUI.ColorToken.card.opacity(0.42))
        }
    }
}

struct AhaKeyStudioUsageDataWorkspace: View {
    let estimatedVoiceSessions: Int
    let lastCommittedCharacterCountText: String
    let dirtyCount: Int
    let isDeviceConnected: Bool
    let deviceName: String?
    let nativeSpeechStatusMessage: String
    let nativeSpeechReady: Bool
    let voiceRelayStatusMessage: String
    let voiceRelayReady: Bool
    let syncStatusMessage: String
    let hasUnsyncedChanges: Bool
    let lastCommittedText: String

    var body: some View {
        VStack(spacing: 0) {
            AhaKeyStudioWorkspaceHeader(
                title: "使用数据",
                subtitle: "个人本机使用看板。当前展示来自本地状态的轻量统计，不上传云端。",
                trailing: {
                    Text("本机数据")
                        .font(AhaKeyUI.Font.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .ahaKeyPill()
                }
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        usageMetricCard("今日语音", value: "\(estimatedVoiceSessions)", detail: "次触发", systemImage: "mic")
                        usageMetricCard("最近写入", value: lastCommittedCharacterCountText, detail: "字符", systemImage: "text.cursor")
                        usageMetricCard("配置改动", value: "\(dirtyCount)", detail: "待同步项", systemImage: "slider.horizontal.3")
                        usageMetricCard("连接状态", value: isDeviceConnected ? "在线" : "离线", detail: deviceName ?? "AhaKey", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("语音输入链路")
                            .font(AhaKeyUI.Font.title2)
                        usageStatusRow("语音服务", value: nativeSpeechStatusMessage, ok: nativeSpeechReady)
                        usageStatusRow("后台语音键", value: voiceRelayStatusMessage, ok: voiceRelayReady)
                        usageStatusRow("设备同步", value: syncStatusMessage, ok: !hasUnsyncedChanges)
                    }
                    .padding(16)
                    .ahaKeySurface()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("最近一次识别")
                            .font(AhaKeyUI.Font.title2)
                        Text(lastCommittedText.isEmpty ? "暂无已写入文本。完成一次语音输入后，这里会展示最近写入摘要。" : lastCommittedText)
                            .font(AhaKeyUI.Font.callout)
                            .foregroundStyle(lastCommittedText.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .ahaKeySurface()
                }
                .padding(24)
            }
            .background(AhaKeyUI.ColorToken.card.opacity(0.42))
        }
    }

    private func usageMetricCard(_ title: String, value: String, detail: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AhaKeyUI.ColorToken.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                            .fill(AhaKeyUI.ColorToken.primary.opacity(0.12))
                    )
                Spacer()
            }
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AhaKeyUI.Font.subhead.weight(.semibold))
                Text(detail)
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .ahaKeySurface()
    }

    private func usageStatusRow(_ title: String, value: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AhaKeyUI.Font.subhead.weight(.semibold))
                Text(value)
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct AhaKeyStudioAccountWorkspace: View {
    let deviceName: String?

    var body: some View {
        VStack(spacing: 0) {
            AhaKeyStudioWorkspaceHeader(
                title: "账号管理",
                subtitle: "管理个人账户、订阅与本机隐私设置。当前为本地账户骨架，不影响设备业务逻辑。",
                trailing: {
                    Text("Pro Trial")
                        .font(AhaKeyUI.Font.footnote.weight(.semibold))
                        .foregroundStyle(AhaKeyUI.ColorToken.primary)
                        .ahaKeyPill(accent: AhaKeyUI.ColorToken.primary)
                }
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileCard

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                        accountSettingCard("订阅", detail: "Pro Trial · 已使用 3 天，共 30 天", systemImage: "creditcard")
                        accountSettingCard("隐私", detail: "语音转写和使用数据默认保存在本机", systemImage: "lock.shield")
                        accountSettingCard("设备", detail: deviceName ?? "尚未连接设备", systemImage: "keyboard")
                        accountSettingCard("支持", detail: "帮助、反馈与诊断导出入口预留", systemImage: "questionmark.circle")
                    }
                }
                .padding(24)
            }
            .background(AhaKeyUI.ColorToken.card.opacity(0.42))
        }
    }

    private var profileCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("AK")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AhaKeyUI.ColorToken.primary)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.large, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.primary.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("本机用户")
                    .font(AhaKeyUI.Font.title2)
                Text("未登录云账户 · 配置与使用数据保存在本机")
                    .font(AhaKeyUI.Font.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("登录 · 开发中")
                .font(AhaKeyUI.Font.subhead.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(AhaKeyUI.ColorToken.control.opacity(0.7))
                )
        }
        .padding(18)
        .ahaKeySurface()
    }

    private func accountSettingCard(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AhaKeyUI.ColorToken.primary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.primary.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AhaKeyUI.Font.subhead.weight(.semibold))
                Text(detail)
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .ahaKeySurface()
    }
}
