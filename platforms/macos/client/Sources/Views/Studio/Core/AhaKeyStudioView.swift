import AppKit
import AhaKeyConfigUI
import SwiftUI
import UniformTypeIdentifiers
import VoiceAgent

struct AhaKeyStudioView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @Binding private var rootWorkspaceMode: AhaKeyRootWorkspaceMode
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @StateObject private var voiceAgentSession = VoiceAgentSessionStore.shared
    @StateObject private var agentManager = AgentManager.shared

    @State private var studioDraft: AhaKeyStudioDraft
    @State private var lastSyncedDraft: AhaKeyStudioDraft
    @State private var selectedMode: AhaKeyModeSlot
    @State private var selectedPart: AhaKeyStudioPart
    @State private var lightBarPreview: LightBarPreviewState
    @State private var lastSyncDate: Date?
    @State private var syncStatusMessage = "修改会先保存在本地，连接设备后再同步。"
    @State private var isSyncing = false
    @State private var showsOLEDPlaybackPreview = false
    @State private var showsVoiceAgentConfiguration = false
    @State private var selectedWorkspace: AhaKeyWorkspaceSection = .workbench
    @AppStorage(AhaKeyAppearanceMode.storageKey) private var appearanceModeRaw = AhaKeyAppearanceMode.light.rawValue

    init(
        bleManager: AhaKeyBLEManager,
        rootWorkspaceMode: Binding<AhaKeyRootWorkspaceMode> = .constant(.classic)
    ) {
        self.bleManager = bleManager
        _rootWorkspaceMode = rootWorkspaceMode
        let initialDraft = AhaKeyStudioStore.load() ?? .default
        // 注意：不要在这里调用 VoiceRelayService.updateRoutes —— SwiftUI 会因 bleManager
        // 的 @Published 属性（workMode/电量/连接状态等）频繁重建 view，init 会跟着多次执行。
        // 任何在 init 里调用 updateRoutes 都会重置 functionRelay 的 holdingRoute（按住状态），
        // 导致微信等"按住说话"过几秒就自动结束。正确入口在下面的 .onAppear。
        _studioDraft = State(initialValue: initialDraft)
        _lastSyncedDraft = State(initialValue: initialDraft)
        let initialMode = AhaKeyModeSlot(rawValue: bleManager.workMode) ?? .mode0
        _selectedMode = State(initialValue: initialMode)
        _selectedPart = State(initialValue: .key1)
        _lightBarPreview = State(initialValue: .aiRunning)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebarPane
                Divider()
                workspacePane
            }
            .background(AhaKeyUI.ColorToken.card)
            Divider()
            statusBar
        }
        .frame(minWidth: 1280, minHeight: 820)
        .background(AhaKeyUI.ColorToken.base)
        .groupBoxStyle(AhaKeyPlainPanelGroupBoxStyle())
        .onAppear {
            agentManager.applyStoredBluetoothPreferenceOnLaunch(bleManager: bleManager)
            voiceRelay.start()
            nativeSpeech.start()
            voiceAgentSession.start(keyboardMode: AhaKeyModeSlot(rawValue: bleManager.workMode) ?? .mode0)
            applyingCursorRejectMacroSelfHealIfNeeded()
            voiceRelay.updateRoutes(from: studioDraft)
            SwitchStateNotifier.shared.bind(to: bleManager)
            NotificationCenter.default.post(
                name: .ahaKeyKeyboardWorkModeChanged,
                object: nil,
                userInfo: ["workMode": bleManager.workMode]
            )
        }
        .onChange(of: studioDraft) { _, newValue in
            AhaKeyStudioStore.save(newValue)
            voiceRelay.updateRoutes(from: newValue)
        }
        // 键盘物理档位变化（BLE 查询/通知上报）→ 自动切到对应 Mode 标签，
        // 这样 OLED 预览、快捷键草稿、发出去的 updateState 三者一致。
        .onChange(of: bleManager.workMode) { _, newValue in
            if let slot = AhaKeyModeSlot(rawValue: newValue), slot != selectedMode {
                selectedMode = slot
            }
            if let slot = AhaKeyModeSlot(rawValue: newValue) {
                voiceAgentSession.updateKeyboardMode(slot)
            }
        }
        .alert("Agent", isPresented: Binding(
            get: { agentManager.agentUserAlert != nil },
            set: { if !$0 { agentManager.agentUserAlert = nil } }
        )) {
            Button("好", role: .cancel) {
                agentManager.agentUserAlert = nil
            }
        } message: {
            Text(agentManager.agentUserAlert ?? "")
        }
        .sheet(isPresented: $showsOLEDPlaybackPreview) {
            OLEDMotionPreviewSheet(
                modeTitle: selectedMode.title,
                assetPath: currentModeDraft.oled.localAssetPath
            )
        }
        .sheet(isPresented: $voiceRelay.showsPermissionOnboarding) {
            VoicePermissionOnboardingSheet(
                voiceRelay: voiceRelay,
                nativeSpeech: nativeSpeech
            )
        }
        .sheet(isPresented: $showsVoiceAgentConfiguration) {
            voiceAgentConfigurationSheet
        }
    }

    private var topBar: some View {
        AhaKeyStudioTopBar(
            bleManager: bleManager,
            agentManager: agentManager,
            rootWorkspaceMode: $rootWorkspaceMode,
            selectedMode: selectedMode,
            switchTitle: currentSwitchTitle,
            isEditingConfiguration: isEditingConfiguration,
            syncToKeyboardButtonTitle: syncToKeyboardButtonTitle,
            syncToKeyboardButtonHelp: syncToKeyboardButtonHelp,
            canSyncConfiguration: canSyncConfiguration,
            configurationModeTitle: configurationModeTitle,
            configurationModeDetail: configurationModeDetail,
            configurationModeButtonTitle: configurationModeButtonTitle,
            configurationModeButtonHelp: configurationModeButtonHelp,
            isSyncing: isSyncing,
            appearanceMode: appearanceMode,
            onSyncToKeyboard: {
                syncAllModesToDevice(returnToKeyboardControlWhenDone: false)
            },
            onConfigurationMode: handleConfigurationModeButton,
            onToggleAppearanceMode: toggleAppearanceMode,
            onRestoreCurrentModeDefaults: restoreCurrentModeDefaults,
            onClearCurrentOLED: clearCurrentOLED
        )
    }

    private var sidebarPane: some View {
        AhaKeyStudioSidebar(selectedWorkspace: $selectedWorkspace)
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

    @ViewBuilder
    private var workspacePane: some View {
        ZStack {
            switch selectedWorkspace {
            case .workbench:
                workbenchWorkspace
            case .deviceInfo:
                deviceInfoWorkspace
            case .ai:
                aiWorkspace
            case .usageData:
                usageDataWorkspace
            case .account:
                accountWorkspace
            }
        }
        .id("\(rootWorkspaceMode.rawValue)-\(selectedWorkspace.rawValue)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var workbenchWorkspace: some View {
        VStack(spacing: 0) {
            workspaceHeader(
                title: "配置台",
                subtitle: "配置键盘模式、语音键、OLED 与灯条。编辑配置时由 AhaKey Studio 临时接管蓝牙。",
                trailing: {
                    HStack(spacing: 8) {
                        Text(dirtyCount == 0 ? "配置已就绪" : "未同步 \(dirtyCount) 项")
                            .font(AhaKeyUI.Font.footnote.weight(.semibold))
                            .foregroundStyle(dirtyCount == 0 ? Color.secondary : Color.orange)
                            .ahaKeyPill(accent: dirtyCount == 0 ? .green : .orange)
                        Picker("模式", selection: $selectedMode) {
                            ForEach(AhaKeyModeSlot.allCases) { mode in
                                Text(mode.name).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 300)
                    }
                }
            )
            Divider()
            if selectedMode == .mode2 {
                VoiceAgentWorkspaceView(
                    session: voiceAgentSession,
                    modeEditorHeader: modeEditorHeader,
                    onOpenConfiguration: openVoiceAgentConfiguration
                )
            } else {
                HStack(spacing: 0) {
                    canvasPane
                    Divider()
                    inspectorPane
                }
            }
        }
    }

    private var deviceInfoWorkspace: some View {
        VStack(spacing: 0) {
            workspaceHeader(
                title: "设备信息",
                subtitle: "查看连接、Agent、BLE、拨杆与日志。这里不做键盘映射，映射配置请回到配置台。",
                trailing: {
                    Text(agentManager.bluetoothConnectionOwner.title)
                        .font(AhaKeyUI.Font.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .ahaKeyPill()
                }
            )
            Divider()
            HStack(spacing: 0) {
                AhaKeyStudioDeviceLogPane(
                    bleManager: bleManager,
                    workModeDisplayName: workModeDisplayName,
                    switchStateDisplayName: switchStateDisplayName,
                    onCopyBLELog: copyBLELog
                )
                Divider()
                DeviceInfoView(bleManager: bleManager)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AhaKeyUI.ColorToken.card.opacity(0.42))
            }
        }
    }

    private var aiWorkspace: some View {
        AhaKeyStudioAIWorkspace()
    }

    private var usageDataWorkspace: some View {
        AhaKeyStudioUsageDataWorkspace(
            estimatedVoiceSessions: estimatedVoiceSessions,
            lastCommittedCharacterCountText: lastCommittedCharacterCountText,
            dirtyCount: dirtyCount,
            isDeviceConnected: bleManager.isConnected,
            deviceName: bleManager.deviceName,
            nativeSpeechStatusMessage: nativeSpeech.statusMessage,
            nativeSpeechReady: nativeSpeech.microphoneGranted && nativeSpeech.speechRecognitionGranted,
            voiceRelayStatusMessage: voiceRelay.statusMessage,
            voiceRelayReady: voiceRelay.inputMonitoringGranted && voiceRelay.accessibilityGranted,
            syncStatusMessage: syncStatusMessage,
            hasUnsyncedChanges: hasUnsyncedChanges,
            lastCommittedText: nativeSpeech.lastCommittedText
        )
    }

    private var accountWorkspace: some View {
        AhaKeyStudioAccountWorkspace(deviceName: bleManager.deviceName)
    }

    private func previewCanvasPane(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AhaKeyUI.Font.title2)
                Text(subtitle)
                    .font(AhaKeyUI.Font.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                AhaKeyKeyboardCanvasView(
                    modeDraft: currentModeDraft,
                    selectedPart: selectedPart,
                    lightBarPreview: lightBarPreview,
                    switchTitle: currentSwitchTitle,
                    dirtyParts: dirtyPartsForCurrentMode(),
                    onSelect: { _ in }
                )
                .aspectRatio(109.0 / 54.0, contentMode: .fit)
                .allowsHitTesting(false)
            }
            .padding(20)
            .ahaKeySurface()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AhaKeyUI.ColorToken.canvas.opacity(0.35))
    }

    private func workspaceHeader<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        AhaKeyStudioWorkspaceHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing
        )
    }

    private var appearanceMode: AhaKeyAppearanceMode {
        AhaKeyAppearanceMode(rawValue: appearanceModeRaw) ?? .light
    }

    private func toggleAppearanceMode() {
        appearanceModeRaw = appearanceMode.next.rawValue
    }

    private var canvasPane: some View {
        AhaKeyStudioCanvasPane(
            modeDraft: currentModeDraft,
            selectedPart: $selectedPart,
            lightBarPreview: lightBarPreview,
            switchTitle: currentSwitchTitle,
            dirtyParts: dirtyPartsForCurrentMode()
        )
    }

    private var modeEditorHeader: some View {
        AhaKeyStudioModeEditorHeader(mode: selectedMode)
    }

    private var inspectorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("配置面板")
                    .font(AhaKeyUI.Font.title2)
                Spacer()
                Text("35%")
                    .font(AhaKeyUI.Font.subhead)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(chromeBarBackground)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inspectorHeader

                    Group {
                        switch selectedPart {
                        case .key1, .key2, .key3, .key4:
                            keyInspector
                        case .oledDisplay:
                            oledInspector
                                .disabled(!isEditingConfiguration)
                        case .lightBar:
                            lightBarInspector
                                .disabled(!isEditingConfiguration)
                        case .toggleSwitch:
                            switchInspector
                                .disabled(!isEditingConfiguration)
                        }
                    }
                }
                .padding(18)
            }

            Divider()
            inspectorSyncHint
            Divider()
            inspectorFooter
        }
        .frame(width: 430)
        .frame(maxHeight: .infinity)
        .background(AhaKeyUI.ColorToken.card.opacity(0.42))
    }

    private var inspectorHeader: some View {
        EmptyView()
    }

    private var inspectorSyncHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hasUnsyncedChanges ? "arrow.down.doc.fill" : "checkmark.circle.fill")
                .foregroundStyle(hasUnsyncedChanges ? Color.orange : Color.green)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(hasUnsyncedChanges ? "有改动尚未写入键盘" : "当前配置已就绪")
                    .font(AhaKeyUI.Font.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(hasUnsyncedChanges ? "同步后配置才会写入硬件；退出编辑前建议先保存配置。" : "修改按键、OLED 或描述后，这里会提示待同步状态。")
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AhaKeyUI.ColorToken.control.opacity(0.45))
    }

    private var inspectorFooter: some View {
        HStack(spacing: 10) {
            Text(isEditingConfiguration ? "编辑模式" : "键盘控制")
                .font(AhaKeyUI.Font.footnote.weight(.semibold))
                .foregroundStyle(isEditingConfiguration ? Color.blue : Color.secondary)
            Spacer(minLength: 0)

            Button("重发当前模式") {
                resendCurrentModeToDevice()
            }
            .buttonStyle(AhaKeySecondaryButtonStyle())
            .disabled(!bleManager.isConnected || isSyncing)

            Button(configurationModeButtonTitle) {
                handleConfigurationModeButton()
            }
            .buttonStyle(AhaKeyPrimaryButtonStyle())
            .disabled(isSyncing || agentManager.isAgentOperationInProgress)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(chromeBarBackground)
    }

    private var keyInspector: some View {
        let key = currentSelectedKey
        return VStack(alignment: .leading, spacing: 16) {
            keyHeroHeader(for: key)
            keySummaryStrip(for: key)
            keyConfigurationCard(for: key)
            keyPermissionCard(for: key)
            keyUsageDisclosure(for: key)
        }
    }

    private func keyHeroHeader(for key: AhaKeyKeyDraft) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: key.role.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.large, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.large, style: .continuous)
                        .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Key \(key.role.rawValue + 1)")
                        .font(.system(size: 26, weight: .semibold))
                        .lineLimit(1)
                    if partIsDirty(key.role.part) {
                        Text("未同步")
                            .font(AhaKeyUI.Font.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .ahaKeyPill(accent: .orange)
                    }
                }
                Text(key.role.title)
                    .font(AhaKeyUI.Font.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func keySummaryStrip(for key: AhaKeyKeyDraft) -> some View {
        HStack(spacing: 0) {
            keySummaryItem(
                icon: key.role == .voice ? "waveform" : key.role.systemImage,
                accent: .blue,
                title: "当前功能",
                value: key.role == .voice ? "语音输入" : key.role.title
            )
            Divider().padding(.vertical, 10)
            keySummaryItem(
                icon: "square.stack.3d.up",
                accent: .purple,
                title: "当前方案",
                value: key.displaySummary
            )
            Divider().padding(.vertical, 10)
            keySummaryItem(
                icon: "checkmark",
                accent: keyAvailabilityColor(for: key),
                title: "当前状态",
                value: keyAvailabilityTitle(for: key)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .ahaKeySurface(radius: AhaKeyUI.Radius.large)
    }

    private func keySummaryItem(icon: String, accent: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AhaKeyUI.Font.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AhaKeyUI.Font.title3)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyConfigurationCard(for key: AhaKeyKeyDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("按键配置")
                    .font(AhaKeyUI.Font.title2)
                Spacer()
                Button(keyConfigSyncButtonTitle) {
                    syncAllModesToDevice(returnToKeyboardControlWhenDone: false)
                }
                .buttonStyle(AhaKeyPrimaryButtonStyle())
                .disabled(!canSyncConfiguration)
                .help(syncToKeyboardButtonHelp)
            }

            VStack(spacing: 12) {
                if key.role == .voice {
                    inspectorFormRow(title: "功能类型") {
                        Text("语音输入")
                            .font(AhaKeyUI.Font.callout)
                    }
                    inspectorFormRow(title: "语音方案") {
                        Picker("语音方案", selection: selectedVoicePresetBinding) {
                            ForEach(VoicePreset.allCases) { preset in
                                Text(preset.availableInV1 ? preset.title : "\(preset.title) · 开发中").tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    inspectorFormRow(title: "触发方式") {
                        Text("单击开始，再按结束")
                            .font(AhaKeyUI.Font.callout)
                            .foregroundStyle(.secondary)
                    }
                    inspectorFormRow(title: "绑定键位") {
                        Text((key.voicePreset ?? .custom).defaultBinding.displayLabel)
                            .font(AhaKeyUI.Font.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    inspectorFormRow(title: "功能类型") {
                        Text(key.role.title)
                            .font(AhaKeyUI.Font.callout)
                    }
                    inspectorFormRow(title: "绑定模式") {
                        Picker("绑定模式", selection: selectedKeyBindingModeBinding) {
                            Text("单键 / 组合键").tag(KeyBindingMode.shortcut)
                            Text("宏").tag(KeyBindingMode.macro)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if key.usesMacro {
                        macroEditor(for: key)
                            .padding(.top, 2)
                    } else {
                        inspectorFormRow(title: "绑定键位") {
                            ShortcutBindingEditor(shortcut: selectedKeyShortcutBinding)
                        }
                    }
                }

                inspectorFormRow(title: "按键名称") {
                    TextField("例如 Record / Accept / Reject / Enter", text: selectedKeyDescriptionBinding)
                        .textFieldStyle(.plain)
                        .font(AhaKeyUI.Font.callout)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                                .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
                        )
                }
            }

            if key.role == .voice {
                Text(voicePresetDetail)
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if currentSelectedKey.description.containsNonASCII {
                Text("设备 OLED 只稳定支持 ASCII。中文、emoji 和全角字符会在写入时被自动过滤，当前写入：\(currentSelectedKeySanitizedDescription.isEmpty ? "空白" : currentSelectedKeySanitizedDescription)")
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isEditingConfiguration {
                Text("当前为键盘控制模式，配置项只读。点击顶部“编辑配置”后可修改并同步到设备。")
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .ahaKeySurface(radius: AhaKeyUI.Radius.large)
        .disabled(!isEditingConfiguration)
    }

    private func inspectorFormRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(AhaKeyUI.Font.subhead.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 82, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 40)
    }

    private func keyPermissionCard(for key: AhaKeyKeyDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("状态与权限")
                .font(AhaKeyUI.Font.title2)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                if key.role == .voice {
                    permissionTile("后台监听", granted: voiceRelay.isListening || voiceRelay.inputMonitoringGranted)
                    permissionTile("麦克风", granted: nativeSpeech.microphoneGranted)
                    permissionTile("输入监控", granted: voiceRelay.inputMonitoringGranted)
                    permissionTile("语音转写", granted: nativeSpeech.speechRecognitionGranted)
                } else {
                    permissionTile("配置草稿", granted: !partIsDirty(key.role.part))
                    permissionTile("设备连接", granted: bleManager.isConnected)
                    permissionTile("编辑模式", granted: isEditingConfiguration)
                    permissionTile("可同步", granted: canSyncConfiguration || !hasUnsyncedChanges)
                }
            }

            HStack(spacing: 10) {
                Button {
                    voiceRelay.refreshPermissions(deferredTCCRequery: true)
                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                } label: {
                    Label("检查权限", systemImage: "checkmark.shield")
                }
                .buttonStyle(AhaKeySecondaryButtonStyle())

                Button {
                    if key.role == .voice {
                        nativeSpeech.toggleRecordingFromVoiceKey()
                    } else {
                        resendCurrentModeToDevice()
                    }
                } label: {
                    Label(key.role == .voice ? "测试按键" : "重发当前模式", systemImage: key.role == .voice ? "waveform" : "arrow.clockwise")
                }
                .buttonStyle(AhaKeySecondaryButtonStyle())
                .disabled(key.role != .voice && (!bleManager.isConnected || isSyncing))
            }
        }
        .padding(16)
        .ahaKeySurface(radius: AhaKeyUI.Radius.large)
    }

    private func permissionTile(_ title: String, granted: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AhaKeyUI.Font.subhead.weight(.semibold))
                Text(granted ? "已开启" : "未开启")
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                .fill(AhaKeyUI.ColorToken.control.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
        )
    }

    private func keyUsageDisclosure(for key: AhaKeyKeyDraft) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if key.role == .voice {
                    Text("保持 AhaKey Studio 在后台运行，按实体语音键开始 macOS 原生转写，再按一次结束并写回当前光标。")
                    Text("若权限显示异常，请在系统设置中开启输入监控、辅助功能、麦克风和语音转写后，完全退出并重新打开本应用。")
                } else {
                    Text(key.role.manualText)
                    Text("完成配置后点击顶部或本卡片内的“同步到设备”，设备侧短按切换模式时会显示按键描述。")
                }
            }
            .font(AhaKeyUI.Font.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Text("使用说明")
                    .font(AhaKeyUI.Font.title3)
                Spacer()
            }
        }
        .padding(16)
        .ahaKeySurface(radius: AhaKeyUI.Radius.large)
    }

    private func keyAvailabilityColor(for key: AhaKeyKeyDraft) -> Color {
        keyAvailabilityTitle(for: key) == "可用" ? .green : .orange
    }

    private func keyAvailabilityTitle(for key: AhaKeyKeyDraft) -> String {
        if key.role == .voice {
            return nativeSpeech.microphoneGranted && nativeSpeech.speechRecognitionGranted ? "可用" : "待授权"
        }
        return isEditingConfiguration ? "可编辑" : "只读"
    }

    // MARK: - 宏编辑器视图

    @ViewBuilder
    private func macroEditor(for key: AhaKeyKeyDraft) -> some View {
        let stepCount = key.macro.count
        let byteCount = stepCount * 2
        let overLimit = byteCount > 98 // 固件 payload 上限

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("步骤（依次执行）")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(stepCount) 步 · \(byteCount) / 98 字节")
                    .font(.caption)
                    .foregroundStyle(overLimit ? .red : .secondary)
            }

            if key.macro.isEmpty {
                Text("空宏。点下方“添加步骤”开始录制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(key.macro.enumerated()), id: \.element.id) { index, step in
                        macroStepRow(
                            index: index,
                            step: step,
                            totalCount: key.macro.count
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    appendMacroStep()
                } label: {
                    Label("添加步骤", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(overLimit)

                Button(role: .destructive) {
                    updateSelectedKey { $0.macro = [] }
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(key.macro.isEmpty)
            }

            if overLimit {
                Text("超过固件单键宏 98 字节 / 49 步上限，同步时会被拒绝。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("固件按顺序串行发送；延时单位 3ms（最大 765ms）。需要更长延时请叠加多个延时步骤。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !key.macro.isEmpty {
                Text("预览：\(key.macro.displaySummary)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func macroStepRow(index: Int, step: MacroStep, totalCount: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Picker("", selection: macroStepActionBinding(id: step.id)) {
                ForEach(MacroAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 96)

            if step.action.takesKeycodeParam {
                Picker("", selection: macroStepKeycodeBinding(id: step.id)) {
                    Text("未设置").tag(UInt8(0))
                    ForEach(HIDUsage.allOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 96)
            } else if step.action.takesDelayParam {
                // 勿对带标题的 Stepper 用 labelsHidden()，否则连「15 ms」一并被藏掉。
                HStack(spacing: 8) {
                    Text("\(max(1, Int(step.param)) * 3) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, alignment: .trailing)
                    Stepper(
                        "",
                        value: macroStepDelayBinding(id: step.id),
                        in: 1...255
                    )
                    .labelsHidden()
                }
                .frame(minWidth: 120)
            } else {
                Color.clear.frame(minWidth: 96, maxHeight: 1)
            }

            Spacer(minLength: 0)

            Button {
                moveMacroStep(from: index, by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                moveMacroStep(from: index, by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(index >= totalCount - 1)

            Button(role: .destructive) {
                removeMacroStep(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }

    private func macroStepActionBinding(id: UUID) -> Binding<MacroAction> {
        Binding(
            get: {
                currentSelectedKey.macro.first { $0.id == id }?.action ?? .noOp
            },
            set: { newAction in
                updateMacroStep(id: id) { step in
                    let previous = step.action
                    step.action = newAction
                    // 动作换类别后清零 param，避免把 "Enter 的 HID 码 0x28" 当成延时值 ×3ms 解读。
                    if previous.takesKeycodeParam != newAction.takesKeycodeParam
                        || previous.takesDelayParam != newAction.takesDelayParam
                    {
                        switch newAction {
                        case .delay:
                            step.param = 5 // 默认 15ms，比较通用
                        case .downKey, .upKey:
                            step.param = HIDUsage.enter
                        case .noOp, .upAllKeys:
                            step.param = 0
                        }
                    }
                }
            }
        )
    }

    private func macroStepKeycodeBinding(id: UUID) -> Binding<UInt8> {
        Binding(
            get: {
                currentSelectedKey.macro.first { $0.id == id }?.param ?? 0
            },
            set: { newValue in
                updateMacroStep(id: id) { $0.param = newValue }
            }
        )
    }

    private func macroStepDelayBinding(id: UUID) -> Binding<UInt8> {
        Binding(
            get: {
                currentSelectedKey.macro.first { $0.id == id }?.param ?? 0
            },
            set: { newValue in
                updateMacroStep(id: id) { $0.param = newValue }
            }
        )
    }

    private var oledInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("当前模式的 OLED 动图") {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.9))
                            .frame(height: 140)

                        if let image = currentOLEDPreviewImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("当前仅支持动图")
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("文字、token、模型状态显示开发中")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("选择动图") {
                            selectOLEDGIF()
                        }
                        .buttonStyle(.bordered)

                        Button("预览动图") {
                            showsOLEDPlaybackPreview = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentModeDraft.oled.localAssetPath == nil)

                        Button(bleManager.isUploadingOLED ? "上传中…" : "上传到 \(selectedMode.title)") {
                            uploadCurrentOLEDToDevice()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!bleManager.isConnected || bleManager.isUploadingOLED || currentModeDraft.oled.localAssetPath == nil)

                        Button("清空") {
                            clearCurrentOLED()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text("当前目标：\(selectedMode.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: oledFramesPerSecondBinding, in: 5 ... 20) {
                        Text("播放速度 \(currentModeDraft.oled.framesPerSecond) FPS")
                    }

                    if let progress = bleManager.oledUploadProgress, bleManager.isUploadingOLED {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: progress.fractionCompleted)
                            Text("已写入 \(progress.completedFrames)/\(progress.totalFrames) 帧，分块 \(progress.completedChunks)/\(progress.totalChunks)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("硬性限制：GIF 源文件 ≤ 2 MB。建议 5–20 FPS、最多 74 帧；将自动缩放到 160×80（RGB565）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(currentModeDraft.oled.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox("显示逻辑") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("切换到当前模式时，OLED 会先显示该模式的按键描述，约 1 秒后回到该模式动图。")
                    Text("后续会继续增加文字状态、token 用量、模型环境等信息显示能力。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var lightBarReadOnlyInfo: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("出厂灯条映射（只读）")
                    .font(.subheadline.weight(.semibold))
                Text("灯条由键盘固件根据 Hook 上报的 IDE 状态点亮，本软件不能改写。下表为各业务场景对应的典型 Hook 状态与出厂灯效说明；画布与「预览到设备」均按此表展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private var lightBarInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            lightBarReadOnlyInfo

            GroupBox("业务状态 → Hook 状态 → 出厂灯效") {
                VStack(alignment: .leading, spacing: 12) {
                    let cases = Array(LightBarPreviewState.allCases)
                    ForEach(Array(cases.enumerated()), id: \.offset) { index, state in
                        let hw = AhaKeyLightBarDraft.hardwareEffect(for: state)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(state.title)
                                    .font(.callout.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(hw.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text("Hook 上报：\(state.ideState.label)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(hw.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if index < cases.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("状态预览") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(lightBarPreview.title)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Spacer()
                        Button("预览到设备") {
                            previewCurrentLightEffectOnDevice()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!bleManager.isConnected || currentDevicePreviewIDEState == nil)
                    }

                    Text("当前画布预览：\(currentLightEffect.title)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(currentLightPreviewHint)
                        .font(.caption)
                        .foregroundStyle(currentDevicePreviewIDEState == nil ? .orange : .secondary)
                    if bleManager.isConnected && bleManager.workMode != 0 {
                        Text("ℹ️ 出厂固件只在物理 Mode 0（1、2 灯）下完整映射了 state → 灯效；当前键盘在 Mode \(bleManager.workMode)，点预览多半看不到效果，把拨杆切到 Mode 0 再试。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(LightBarPreviewState.allCases) { state in
                            Button {
                                lightBarPreview = state
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(state.title)
                                        .font(.callout.weight(.semibold))
                                    Text(AhaKeyLightBarDraft.hardwareEffect(for: state).title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(state == lightBarPreview ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(state == lightBarPreview ? Color.accentColor : Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("若需让某套灯效出现，请用下方「预览到设备」向固件发送一次对应可达的 IDE 状态试灯；或在 Agent 连上键盘后，通过实际触发 Hook 观察。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var switchInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("实时档位") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(currentSwitchTitle)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Spacer()
                        Circle()
                            .fill(currentSwitchTitle == "自动批准" ? Color.green : Color.indigo)
                            .frame(width: 10, height: 10)
                    }
                    Text("拨杆是物理档位，不是按下瞬态。0 档显示“自动批准”，1 档显示“手动批准”。这里只读取键盘上报的位置，不模拟物理拨动。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            switchEffectivenessBox

            if bleManager.switchState == 0 {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("自动批准依赖 Agent 与 Hook，且须蓝牙由 Agent 占用", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout.weight(.semibold))
                        Text("Claude：PermissionRequest 时返回 allow。Cursor：preToolUse（以及你自建的 beforeShell beforeMCP 钩子）stdout 会返回 permission=allow。若 agent 未连键盘或本 App 占着 BLE，会退成交回确认。须 Agent 在跑、Hook 已装。涉及 shell/删文件等高危时建议用手动档。需要逐条确认时请把拨杆切到“手动批准”。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("如何理解这个部件") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自动批准：Claude 用 PermissionRequest；Cursor 用 preToolUse 等并返回 JSON permission。均需 Agent + Hooks，且设备蓝牙由 Agent 连接。")
                    Text("手动批准：会交回用户/终端确认。若 Cursor 仍弹窗，请看 diagnostics 里 ide=cursor 与 diagnostic 字段。")
                    Text("若仍出现手动：在「设备信息」里打开「工具批准诊断」查看 permission-request.log（含 ide、hookEvent、diagnostic 等）。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var switchEffectivenessBox: some View {
        let agentReady = agentManager.isInstalled && agentManager.isRunning && agentManager.hooksInstalled
        let hasAnyMissing = !agentManager.isInstalled || !agentManager.isRunning || !agentManager.hooksInstalled
        GroupBox(agentReady ? "已生效" : "未生效") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: agentReady ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(agentReady ? .green : .orange)
                    Text(agentReady
                         ? "Agent 与 Hook 已就位时，拨杆会参与 Claude 的 PermissionRequest 与 Cursor 的 preToolUse 等批准链。"
                         : "拨杆在 IDE 中生效需先安装 Agent 与 Hook，并把蓝牙交给 Agent；否则仅为状态显示。")
                        .font(.callout)
                }

                if hasAnyMissing {
                    VStack(alignment: .leading, spacing: 4) {
                        agentChecklistRow(label: "LaunchAgent 已安装", ok: agentManager.isInstalled)
                        agentChecklistRow(label: "Agent 已连接蓝牙", ok: agentManager.isRunning)
                        agentChecklistRow(label: "Claude / Cursor Hook 已配置", ok: agentManager.hooksInstalled)
                    }
                    .padding(.leading, 4)

                    HStack(spacing: 8) {
                        if !agentManager.isInstalled {
                            Button("安装 Agent + Hook") {
                                agentManager.install()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else if !agentManager.isRunning {
                            // 与「设备信息」相同：在 launchd 中 load + start 守护进程。
                            // 若当前由本 App 占用蓝牙，此处也应引导先去设备信息把「蓝牙连接」切给 Agent，否则与主流程二选一相冲突（故与 DeviceInfo 同样禁用直接启动）。
                            Button("启动 Agent") {
                                agentManager.start()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(agentManager.bluetoothConnectionOwner == .ahaKeyStudio)
                            .help(
                                agentManager.bluetoothConnectionOwner == .ahaKeyStudio
                                ? "当前由本 App 占用蓝牙。请打开下方「设备信息…」，在「蓝牙连接」里选「由 Agent 占用」后再启 Agent；与设备信息里「启动」按钮规则一致。"
                                : "与「设备信息」中的启动相同，由 launchd 加载并执行 ahakeyconfig-agent。"
                            )
                        }
                        Button("设备信息（蓝牙 / 启停 Agent）") {
                            switchWorkspace(.deviceInfo)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func agentChecklistRow(label: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(ok ? .primary : .secondary)
        }
    }


    private var statusBar: some View {
        AhaKeyStudioStatusBar(
            selectionText: statusBarSelectionText,
            selectionIcon: statusBarSelectionIcon,
            firmwareMainVersion: bleManager.firmwareMainVersion,
            firmwareSubVersion: bleManager.firmwareSubVersion,
            dirtyCount: dirtyCount,
            onShowOnboarding: {
                NotificationCenter.default.post(name: .ahaKeyDebugShowOnboardingPreview, object: nil)
            },
            onShowPermissions: {
                voiceRelay.showsPermissionOnboarding = true
            }
        )
    }

    private var voiceAgentConfigurationSheet: some View {
        AhaKeyVoiceAgentConfigurationSheet(isPresented: $showsVoiceAgentConfiguration)
    }

    private var chromeBarBackground: Color {
        AhaKeyUI.ColorToken.card
    }

    private var currentModeDraft: AhaKeyModeDraft {
        studioDraft.draft(for: selectedMode)
    }

    private var currentSelectedKey: AhaKeyKeyDraft {
        let role = selectedPart.keyRole ?? .voice
        return currentModeDraft.key(for: role)
    }

    private var currentSwitchTitle: String {
        bleManager.switchState == 0 ? "自动批准" : "手动批准"
    }

    private var workModeDisplayName: String {
        switch bleManager.workMode {
        case 0: return "Mode 0"
        case 1: return "Mode 1"
        case 2: return "Mode 2"
        default: return "Mode \(bleManager.workMode)"
        }
    }

    private var switchStateDisplayName: String {
        bleManager.switchState == 0 ? "自动批准" : "手动批准"
    }

    private var currentOLEDPreviewImage: NSImage? {
        guard let path = currentModeDraft.oled.localAssetPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var currentOLEDAssetURL: URL? {
        guard let path = currentModeDraft.oled.localAssetPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    private var currentLightEffect: LightEffectStyle {
        AhaKeyLightBarDraft.hardwareEffect(for: lightBarPreview)
    }

    private var currentDevicePreviewIDEState: IDEState? {
        currentLightEffect.previewIDEState(forSwitchState: bleManager.switchState)
    }

    private var currentLightPreviewHint: String {
        currentLightEffect.previewHint(forSwitchState: bleManager.switchState)
    }

    private var isEditingConfiguration: Bool {
        agentManager.bluetoothConnectionOwner == .ahaKeyStudio
    }

    private var configurationModeTitle: String {
        if selectedMode == .mode2 {
            return "VoiceAgent"
        }
        return isEditingConfiguration ? "编辑配置中" : "键盘控制中"
    }

    private var configurationModeDetail: String {
        if selectedMode == .mode2 {
            return "主 agent 工作台"
        }
        if isEditingConfiguration {
            if bleManager.isConnected {
                return "AhaKey Studio 正在配置键盘"
            }
            return bleManager.isScanning ? "AhaKey Studio 正在连接键盘" : "AhaKey Studio 等待连接键盘"
        }
        if agentManager.isRunning && agentManager.isAgentBLEConnected {
            return "Agent 正在控制键盘"
        }
        if agentManager.isRunning {
            return "Agent 运行中，等待键盘连接"
        }
        if agentManager.isInstalled {
            return "Agent 已安装，正在准备控制"
        }
        return "需要安装 Agent 后才能控制键盘"
    }

    private var configurationModeButtonTitle: String {
        if selectedMode == .mode2 {
            return "VoiceAgent 设置"
        }
        if isSyncing {
            return "同步中…"
        }
        if isEditingConfiguration {
            return "返回控制"
        }
        return "编辑配置"
    }

    private var configurationModeButtonHelp: String {
        if selectedMode == .mode2 {
            return "打开 VoiceAgent 运行时配置入口；当前 API key 暂时从 Keychain 读取。"
        }
        if isEditingConfiguration {
            if hasUnsyncedChanges {
                return "将当前草稿同步到键盘，然后把蓝牙交还给 Agent。"
            }
            return "没有未同步改动，直接把蓝牙交还给 Agent。"
        }
        return "临时由 AhaKey Studio 接管蓝牙，用于改键、OLED、同步和本机灯效测试。"
    }

    private var statusBarSelectionText: String {
        if selectedMode == .mode2 {
            return "VoiceAgent · \(selectedMode.title)"
        }
        return "\(selectedPart.title) · \(selectedMode.title)"
    }

    private var statusBarSelectionIcon: String {
        if selectedMode == .mode2 {
            return "point.3.connected.trianglepath.dotted"
        }
        return selectedPart.systemImage
    }

    private var syncToKeyboardButtonTitle: String {
        if isSyncing { return "同步中…" }
        return hasUnsyncedChanges ? "同步到键盘" : "已同步"
    }

    private var keyConfigSyncButtonTitle: String {
        if isSyncing { return "同步中…" }
        if !isEditingConfiguration { return "先编辑配置" }
        if !bleManager.isConnected { return "等待连接" }
        return hasUnsyncedChanges ? "同步到设备" : "已同步"
    }

    private var syncToKeyboardButtonHelp: String {
        if !bleManager.isConnected {
            return "键盘未连接，当前只能保存本地草稿。"
        }
        if !hasUnsyncedChanges {
            return "当前配置已写入键盘，无需再次同步。"
        }
        return "将当前 Mode、按键、OLED 和灯效草稿写入键盘。"
    }

    private var canSyncConfiguration: Bool {
        isEditingConfiguration &&
        hasUnsyncedChanges &&
        bleManager.isConnected &&
        !isSyncing &&
        !agentManager.isAgentOperationInProgress
    }

    private var estimatedVoiceSessions: Int {
        var count = 0
        if nativeSpeech.isRecording { count += 1 }
        if !nativeSpeech.lastCommittedText.isEmpty { count += 1 }
        if !nativeSpeech.transcriptPreview.isEmpty { count += 1 }
        return count
    }

    private var lastCommittedCharacterCountText: String {
        let count = nativeSpeech.lastCommittedText.count
        return count == 0 ? "—" : "\(count)"
    }

    private var voicePresetDetail: String {
        let preset = currentSelectedKey.voicePreset ?? .custom
        return preset.detail
    }

    private func permissionBadge(title: String, granted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(granted ? "已开启" : "未开启")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .ahaKeyPill(accent: granted ? .green : .orange)
    }

    private var currentSelectedKeySanitizedDescription: String {
        currentSelectedKey.description.sanitizedASCII(maxLength: 20)
    }

    private var selectedKeyDescriptionBinding: Binding<String> {
        Binding(
            get: { currentSelectedKey.description },
            set: { newValue in
                updateSelectedKey { key in
                    key.description = String(newValue.prefix(20))
                }
            }
        )
    }

    private var selectedKeyShortcutBinding: Binding<ShortcutBinding> {
        Binding(
            get: { currentSelectedKey.shortcut },
            set: { newValue in
                updateSelectedKey { $0.shortcut = newValue }
            }
        )
    }

    private var selectedVoicePresetBinding: Binding<VoicePreset> {
        Binding(
            get: { currentSelectedKey.voicePreset ?? .custom },
            set: { preset in
                guard preset.availableInV1 else { return }
                applyVoicePreset(preset)
            }
        )
    }

    private var oledFramesPerSecondBinding: Binding<Int> {
        Binding(
            get: { currentModeDraft.oled.framesPerSecond },
            set: { newValue in
                updateCurrentMode { mode in
                    mode.oled.framesPerSecond = min(20, max(5, newValue))
                }
            }
        )
    }

    private var hasUnsyncedChanges: Bool {
        dirtyCount > 0
    }

    private var dirtyCount: Int {
        AhaKeyStudioConfigurationSync.dirtyCount(
            current: studioDraft,
            baseline: lastSyncedDraft
        )
    }

    private func restoreCurrentModeDefaults() {
        let restored = AhaKeyModeDraft.default(for: selectedMode)
        var next = studioDraft
        next.updateMode(restored)
        studioDraft = next
        syncStatusMessage = "\(selectedMode.title) 已恢复默认值，等待同步。"
    }

    private func clearCurrentOLED() {
        updateCurrentMode { mode in
            mode.oled.localAssetPath = nil
            mode.oled.statusLine = AhaKeyOLEDDraft.default(for: selectedMode).statusLine
        }
    }

    private func applyVoicePreset(_ preset: VoicePreset) {
        updateSelectedKey { key in
            key.voicePreset = preset
            if preset != .custom {
                key.shortcut = preset.defaultBinding
            }
            if key.description.isEmpty {
                key.description = key.role.defaultDescription
            }
        }
    }

    // MARK: - 宏编辑

    /// 按键当前处于 "宏" 还是 "快捷键" 录入模式。
    /// 状态仅由 `macro` 是否为空推导，避免多出一个独立 flag。
    private enum KeyBindingMode {
        case shortcut
        case macro
    }

    private var selectedKeyBindingModeBinding: Binding<KeyBindingMode> {
        Binding(
            get: { currentSelectedKey.usesMacro ? .macro : .shortcut },
            set: { newValue in
                switch newValue {
                case .shortcut:
                    updateSelectedKey { key in
                        key.macro = []
                    }
                case .macro:
                    updateSelectedKey { key in
                        guard key.macro.isEmpty else { return }
                        // Mode 0「No」键的 shortcut 故意为空，实际绑定是固件宏 ↓↓⏎；若仍用「空 shortcut → Enter 种子」，
                        // 从「单键」切回「宏」时会被误植成只按 Enter，覆盖用户刚配好的三键宏。
                        if selectedMode == .mode0, key.role == .reject {
                            key.macro = AhaKeyModeDraft.claudeNoMacroSteps.map { step in
                                MacroStep(action: step.action, param: step.param)
                            }
                            return
                        }
                        // 其它键：用当前 shortcut 的主键作种子（没配就用 Enter），避免空白宏列表。
                        let seed: UInt8 = key.shortcut.keyCode == 0 ? HIDUsage.enter : key.shortcut.keyCode
                        key.macro = [
                            MacroStep(action: .downKey, param: seed),
                            MacroStep(action: .upKey, param: seed),
                        ]
                    }
                }
            }
        )
    }

    private func appendMacroStep() {
        updateSelectedKey { key in
            // 默认追加 "按下 Enter"——多数用户添加步骤都是想按键，延时/松开可以再切。
            key.macro.append(MacroStep(action: .downKey, param: HIDUsage.enter))
        }
    }

    private func removeMacroStep(at index: Int) {
        updateSelectedKey { key in
            guard key.macro.indices.contains(index) else { return }
            key.macro.remove(at: index)
        }
    }

    private func moveMacroStep(from index: Int, by offset: Int) {
        updateSelectedKey { key in
            let target = index + offset
            guard key.macro.indices.contains(index), key.macro.indices.contains(target) else { return }
            key.macro.swapAt(index, target)
        }
    }

    private func updateMacroStep(id: UUID, transform: (inout MacroStep) -> Void) {
        updateSelectedKey { key in
            guard let idx = key.macro.firstIndex(where: { $0.id == id }) else { return }
            transform(&key.macro[idx])
        }
    }

    private func updateSelectedKey(_ transform: (inout AhaKeyKeyDraft) -> Void) {
        guard let role = selectedPart.keyRole else { return }
        updateCurrentMode { mode in
            var key = mode.key(for: role)
            transform(&key)
            mode.updateKey(key)
        }
    }

    private func updateCurrentMode(_ transform: (inout AhaKeyModeDraft) -> Void) {
        updateMode(selectedMode, transform)
    }

    private func updateMode(_ modeSlot: AhaKeyModeSlot, _ transform: (inout AhaKeyModeDraft) -> Void) {
        var next = studioDraft
        var mode = next.draft(for: modeSlot)
        transform(&mode)
        next.updateMode(mode)
        studioDraft = next
    }

    private func partIsDirty(_ part: AhaKeyStudioPart) -> Bool {
        AhaKeyStudioConfigurationSync.isDirty(
            part,
            in: selectedMode,
            current: studioDraft,
            baseline: lastSyncedDraft
        )
    }

    private func dirtyPartsForCurrentMode() -> Set<AhaKeyStudioPart> {
        AhaKeyStudioConfigurationSync.dirtyParts(
            in: selectedMode,
            current: studioDraft,
            baseline: lastSyncedDraft
        )
    }

    private func selectOLEDGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gif")!]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try OLEDFrameEncoder.validateGIFSourceFileSize(at: url)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "GIF 文件过大。"
                syncStatusMessage = msg
                updateCurrentMode { mode in
                    mode.oled.statusLine = msg
                }
                return
            }
            let frameCount = OLEDFrameEncoder.frameCount(at: url)
            updateCurrentMode { mode in
                mode.oled.localAssetPath = url.path
                mode.oled.statusLine = "已选 \(max(frameCount, 1)) 帧 GIF 预览；切换模式时会先显示描述，再回到当前模式动图。"
            }
            syncStatusMessage = "已更新 \(selectedMode.title) 的 OLED 预览，连接后可直接上传到设备。"
        }
    }

    private func handleConfigurationModeButton() {
        if selectedMode == .mode2 {
            openVoiceAgentConfiguration()
            return
        }
        if isEditingConfiguration {
            finishEditingConfiguration()
        } else {
            enterEditingConfiguration()
        }
    }

    private func openVoiceAgentConfiguration() {
        showsVoiceAgentConfiguration = true
        syncStatusMessage = "VoiceAgent 配置入口已预留，当前运行时读取 Keychain。"
    }

    private func enterEditingConfiguration() {
        agentManager.setBluetoothConnectionOwner(.ahaKeyStudio, bleManager: bleManager)
        syncStatusMessage = "已进入编辑配置，AhaKey Studio 将临时接管蓝牙。"
    }

    private func finishEditingConfiguration() {
        guard hasUnsyncedChanges else {
            returnToKeyboardControl()
            return
        }

        guard bleManager.isConnected else {
            syncStatusMessage = "键盘尚未连接，无法同步未保存改动。请等待连接成功后再返回控制。"
            bleManager.userInitiatedConnect()
            return
        }

        syncAllModesToDevice(returnToKeyboardControlWhenDone: true)
    }

    private func returnToKeyboardControl() {
        agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
        syncStatusMessage = "已返回键盘控制，Agent 将接管蓝牙。"
    }

    private func syncAllModesToDevice(returnToKeyboardControlWhenDone: Bool = false) {
        guard bleManager.isConnected else {
            syncStatusMessage = "设备未连接，当前只保存本地草稿。"
            return
        }

        let syncDraft = applyingCursorRejectMacroSelfHealIfNeeded()
        var commands = AhaKeyStudioConfigurationSync.commands(
            for: AhaKeyModeSlot.allCases,
            in: syncDraft
        )
        commands.append((data: AhaKeyCommand.saveConfig(), label: "保存全部配置到设备"))

        let total = commands.count
        isSyncing = true
        syncStatusMessage = "正在写入设备（约 \(total) 条，全部发完后再保存/交还 Agent）…"
        let returnAgent = returnToKeyboardControlWhenDone
        bleManager.writeCommandsSequentially(commands) {
            Task { @MainActor in
                // 队列与 50ms 间隔已保证顺序；略等再交还蓝牙，避免固件尚未处理完最后帧。
                try? await Task.sleep(for: .milliseconds(250))
                self.lastSyncedDraft = self.studioDraft
                self.lastSyncDate = Date()
                self.isSyncing = false
                self.syncStatusMessage = "已全部写入设备并保存。"
                if returnAgent {
                    self.returnToKeyboardControl()
                }
            }
        }
    }

    private func resendCurrentModeToDevice() {
        guard bleManager.isConnected else {
            syncStatusMessage = "设备未连接，当前只保存本地草稿。"
            return
        }

        let syncDraft = applyingCursorRejectMacroSelfHealIfNeeded()
        var commands = AhaKeyStudioConfigurationSync.commands(
            for: [selectedMode],
            in: syncDraft
        )
        commands.append((data: AhaKeyCommand.saveConfig(), label: "保存 \(selectedMode.title) 当前配置"))

        isSyncing = true
        syncStatusMessage = "正在写入 \(selectedMode.title)…"
        bleManager.writeCommandsSequentially(commands) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                self.lastSyncDate = Date()
                self.isSyncing = false
                self.syncStatusMessage = "已重新发送 \(self.selectedMode.title) 当前模式。"
            }
        }
    }

    @discardableResult
    private func applyingCursorRejectMacroSelfHealIfNeeded() -> AhaKeyStudioDraft {
        let healedDraft = AhaKeyStudioConfigurationSync.applyingCursorRejectMacroSelfHeal(to: studioDraft)
        if healedDraft != studioDraft {
            studioDraft = healedDraft
        }
        return healedDraft
    }

    private func uploadCurrentOLEDToDevice() {
        guard bleManager.isConnected else {
            syncStatusMessage = "设备未连接，先连上键盘再上传 OLED 动图。"
            return
        }
        guard let assetPath = currentModeDraft.oled.localAssetPath else {
            syncStatusMessage = "先为 \(selectedMode.title) 选择一个 GIF，再上传到设备。"
            return
        }

        let targetMode = selectedMode
        let targetFPS = currentModeDraft.oled.framesPerSecond
        let assetURL = URL(fileURLWithPath: assetPath)

        updateMode(targetMode) { mode in
            mode.oled.statusLine = "正在上传动图到 \(targetMode.title)…"
        }
        syncStatusMessage = "开始上传 \(targetMode.title) 的 OLED 动图。"

        Task { @MainActor in
            do {
                let frames = try OLEDFrameEncoder.frames(fromGIFAt: assetURL)
                let startIndex = try await resolveOLEDUploadStartIndex(for: targetMode, frameCount: frames.count)
                try await bleManager.uploadOLEDFrames(
                    frames,
                    fps: targetFPS,
                    mode: UInt8(targetMode.rawValue),
                    startIndex: UInt16(startIndex)
                )
                updateMode(targetMode) { mode in
                    mode.oled.statusLine = "已上传 \(frames.count) 帧到设备，槽位起点 \(startIndex)；切换模式时会先显示描述，再回到当前模式动图。"
                }
                syncStatusMessage = "\(targetMode.title) OLED 动图已上传完成。"
            } catch {
                updateMode(targetMode) { mode in
                    mode.oled.statusLine = "上传失败：\(error.localizedDescription)"
                }
                syncStatusMessage = "\(targetMode.title) OLED 上传失败：\(error.localizedDescription)"
            }
        }
    }

    private func resolveOLEDUploadStartIndex(for targetMode: AhaKeyModeSlot, frameCount: Int) async throws -> Int {
        var states: [AhaKeyPictureState] = []
        for mode in AhaKeyModeSlot.allCases {
            states.append(try await bleManager.readPictureState(mode: UInt8(mode.rawValue)))
        }

        return try AhaKeyOLEDPlacementPlanner.startIndex(
            for: targetMode,
            frameCount: frameCount,
            states: states
        )
    }

    private func previewCurrentLightEffectOnDevice() {
        guard let ideState = currentDevicePreviewIDEState else {
            syncStatusMessage = currentLightPreviewHint
            return
        }
        bleManager.updateIDEState(ideState)
        if bleManager.workMode == 0 {
            syncStatusMessage = "已把 \(currentLightEffect.title) 的可达预览发送到设备（Mode 0）。"
        } else {
            syncStatusMessage = "已发送 \(ideState.label) 到设备。注意：键盘当前在 Mode \(bleManager.workMode)，出厂固件可能没有在此档位映射此 state，把拨杆切到 Mode 0 可看到完整效果。"
        }
    }

    private func copyBLELog() {
        let text = bleManager.commLog.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func openNativeSpeechPrivacySettings() {
        openStudioNativeSpeechPrivacySettingsURL()
    }
}
