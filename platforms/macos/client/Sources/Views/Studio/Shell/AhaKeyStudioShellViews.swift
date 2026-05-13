import AhaKeyConfigUI
import AppKit
import SwiftUI

enum AhaKeyWorkspaceSection: String, CaseIterable, Identifiable {
    case workbench
    case deviceInfo
    case ai
    case usageData
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workbench: return "配置台"
        case .deviceInfo: return "设备信息"
        case .ai: return "AI 引擎"
        case .usageData: return "使用数据"
        case .account: return "账号管理"
        }
    }

    var systemImage: String {
        switch self {
        case .workbench: return "house"
        case .deviceInfo: return "list.bullet.rectangle"
        case .ai: return "cpu"
        case .usageData: return "chart.bar.xaxis"
        case .account: return "person.crop.circle"
        }
    }
}

struct AhaKeyStudioTopBar: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var agentManager: AgentManager
    @Binding var rootWorkspaceMode: AhaKeyRootWorkspaceMode

    let selectedMode: AhaKeyModeSlot
    let switchTitle: String
    let isEditingConfiguration: Bool
    let syncToKeyboardButtonTitle: String
    let syncToKeyboardButtonHelp: String
    let canSyncConfiguration: Bool
    let configurationModeTitle: String
    let configurationModeDetail: String
    let configurationModeButtonTitle: String
    let configurationModeButtonHelp: String
    let isSyncing: Bool
    let appearanceMode: AhaKeyAppearanceMode
    let onSyncToKeyboard: () -> Void
    let onConfigurationMode: () -> Void
    let onToggleAppearanceMode: () -> Void
    let onRestoreCurrentModeDefaults: () -> Void
    let onClearCurrentOLED: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            brand
            statusPills
            Spacer(minLength: 0)
            rootWorkspacePicker
            connectionButton
            syncButton
            configurationModeButton
            appearanceButton
            overflowMenu
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(AhaKeyUI.ColorToken.card)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Text("AK")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AhaKeyUI.ColorToken.primary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.primary.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("AhaKey Studio")
                    .font(AhaKeyUI.Font.title3)
                Text("Native review prototype")
                    .font(AhaKeyUI.Font.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 2)
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            infoPill(
                title: bleManager.isConnected ? "已连接" : (bleManager.isScanning ? "扫描中" : "未连接"),
                subtitle: bleManager.deviceName ?? "等待设备",
                accent: bleManager.isConnected ? .green : .orange
            )
            infoPill(
                title: "电量",
                subtitle: bleManager.isConnected ? "\(bleManager.batteryLevel)%" : "—",
                accent: .blue
            )
            infoPill(
                title: "拨杆",
                subtitle: switchTitle,
                accent: switchTitle == "自动批准" ? .mint : .indigo
            )
            configurationModeStatus
        }
    }

    private var rootWorkspacePicker: some View {
        Picker("界面", selection: $rootWorkspaceMode) {
            ForEach(AhaKeyRootWorkspaceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
        .help("切换 IDE 工作台和 Agent 工作台")
    }

    @ViewBuilder
    private var connectionButton: some View {
        if !bleManager.isConnected, agentManager.bluetoothConnectionOwner == .ahaKeyStudio {
            Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                bleManager.userInitiatedConnect()
            }
            .buttonStyle(AhaKeySecondaryButtonStyle())
            .disabled(bleManager.isScanning)
        }
    }

    @ViewBuilder
    private var syncButton: some View {
        if isEditingConfiguration {
            Button(syncToKeyboardButtonTitle) {
                onSyncToKeyboard()
            }
            .buttonStyle(AhaKeySecondaryButtonStyle())
            .disabled(!canSyncConfiguration)
            .help(syncToKeyboardButtonHelp)
        }
    }

    private var configurationModeButton: some View {
        Button(configurationModeButtonTitle) {
            onConfigurationMode()
        }
        .buttonStyle(AhaKeyPrimaryButtonStyle())
        .disabled(isSyncing || agentManager.isAgentOperationInProgress)
        .help(configurationModeButtonHelp)
    }

    private var appearanceButton: some View {
        Button {
            onToggleAppearanceMode()
        } label: {
            Image(systemName: appearanceMode.systemImage)
        }
        .buttonStyle(AhaKeyIconButtonStyle())
        .help(appearanceMode.title)
    }

    private var overflowMenu: some View {
        Menu {
            Button("恢复当前模式默认值") {
                onRestoreCurrentModeDefaults()
            }
            Button("重新连接设备") {
                bleManager.disconnect()
                bleManager.userInitiatedConnect()
            }
            Button("清空 OLED 预览") {
                onClearCurrentOLED()
            }
            Divider()
            Button("隐藏到后台") {
                NSApp.keyWindow?.close()
            }
            Button("退出 AhaKey Studio") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
    }

    private var configurationModeStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(selectedMode == .mode2 ? Color.purple : (isEditingConfiguration ? Color.blue : Color.green))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(configurationModeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(configurationModeDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .ahaKeyPill(accent: isEditingConfiguration ? .blue : .green)
        .help("日常使用由 Agent 控制键盘；需要改键、OLED 或同步时，进入编辑配置后由 AhaKey Studio 临时接管蓝牙。")
    }

    private func infoPill(title: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AhaKeyUI.Font.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(subtitle)
                    .font(AhaKeyUI.Font.subhead.weight(.semibold))
            }
        }
        .ahaKeyPill(accent: accent)
    }
}

struct AhaKeyStudioSidebar: View {
    @Binding var selectedWorkspace: AhaKeyWorkspaceSection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .padding(.bottom, 12)
            navigationItems
            Spacer(minLength: 16)
            trialCard
            dockButtons
                .padding(.top, 12)
        }
        .padding(16)
        .frame(width: 254)
        .frame(maxHeight: .infinity)
        .background(AhaKeyUI.ColorToken.card)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("AK")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                        .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
                )
            Text("AhaKey Stu...")
                .font(AhaKeyUI.Font.title3)
                .lineLimit(1)
            Spacer()
            Text("Pro Trial")
                .font(AhaKeyUI.Font.footnote.weight(.semibold))
                .foregroundStyle(AhaKeyUI.ColorToken.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(AhaKeyUI.ColorToken.primary.opacity(0.12)))
                .overlay(Capsule().strokeBorder(AhaKeyUI.ColorToken.primary.opacity(0.35), lineWidth: 1))
        }
        .padding(.bottom, 12)
    }

    private var navigationItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AhaKeyWorkspaceSection.allCases) { section in
                Button {
                    switchWorkspace(section)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedWorkspace == section ? Color.primary : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                                    .fill(selectedWorkspace == section ? Color.primary.opacity(0.08) : AhaKeyUI.ColorToken.control)
                            )
                        Text(section.title)
                            .font(AhaKeyUI.Font.subhead.weight(selectedWorkspace == section ? .semibold : .medium))
                            .foregroundStyle(selectedWorkspace == section ? Color.primary : Color.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                            .fill(selectedWorkspace == section ? Color.primary.opacity(0.055) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pro Trial")
                .font(AhaKeyUI.Font.caption.weight(.semibold))
                .foregroundStyle(AhaKeyUI.ColorToken.primary)
                .textCase(.uppercase)
            Text("在试用结束前升级到 Pro")
                .font(AhaKeyUI.Font.subhead.weight(.semibold))
                .foregroundStyle(.primary)
            Text("已使用 3 天，共 30 天")
                .font(AhaKeyUI.Font.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: 0.1)
                .controlSize(.small)
            Text("升级 · 开发中")
                .font(AhaKeyUI.Font.subhead.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(AhaKeyUI.ColorToken.control.opacity(0.7))
                )
        }
        .padding(14)
        .ahaKeySurface(radius: AhaKeyUI.Radius.medium)
    }

    private var dockButtons: some View {
        HStack(spacing: 8) {
            sidebarDockButton("person", help: "账号") {
                switchWorkspace(.account)
            }
            sidebarDockButton("tray", help: "收件箱")
            sidebarDockButton("gearshape", help: "设置")
            sidebarDockButton("questionmark.circle", help: "帮助")
        }
    }

    private func switchWorkspace(_ section: AhaKeyWorkspaceSection) {
        guard selectedWorkspace != section else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            selectedWorkspace = section
        }
    }

    private func sidebarDockButton(_ systemImage: String, help: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                        .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help == "账号" ? help : "\(help) · 开发中")
        .disabled(help != "账号")
        .opacity(help == "账号" ? 1 : 0.55)
    }
}

struct AhaKeyStudioStatusBar: View {
    let selectionText: String
    let selectionIcon: String
    let firmwareMainVersion: Int
    let firmwareSubVersion: Int
    let dirtyCount: Int
    let onShowOnboarding: () -> Void
    let onShowPermissions: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Label(selectionText, systemImage: selectionIcon)
                .font(AhaKeyUI.Font.subhead)
            Divider()
                .frame(height: 14)
            Label("蓝牙延迟 14 ms", systemImage: "rectangle.fill")
                .font(AhaKeyUI.Font.subhead)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 14)
            Text("固件 v\(firmwareMainVersion).\(firmwareSubVersion)")
                .font(AhaKeyUI.Font.subhead)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 14)
            Text("AI 引擎 本地离线")
                .font(AhaKeyUI.Font.subhead)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 14)
            Text(dirtyCount == 0 ? "配置已就绪" : "未同步改动 \(dirtyCount)")
                .font(AhaKeyUI.Font.subhead)
                .foregroundStyle(dirtyCount == 0 ? Color.secondary : Color.orange)
            Spacer()
            Button("新手引导") {
                onShowOnboarding()
            }
            .buttonStyle(AhaKeySecondaryButtonStyle())
            Button("权限引导") {
                onShowPermissions()
            }
            .buttonStyle(AhaKeySecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(AhaKeyUI.ColorToken.card)
    }
}

struct AhaKeyStudioWorkspaceHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AhaKeyUI.Font.largeTitle)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AhaKeyUI.Font.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AhaKeyUI.ColorToken.card)
    }
}
