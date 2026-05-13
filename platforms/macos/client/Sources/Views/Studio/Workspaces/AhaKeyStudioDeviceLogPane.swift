import AhaKeyConfigUI
import SwiftUI

struct AhaKeyStudioDeviceLogPane: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    let workModeDisplayName: String
    let switchStateDisplayName: String
    let onCopyBLELog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            deviceSummaryCard
            logCard
        }
        .padding(24)
        .frame(width: 430)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AhaKeyUI.ColorToken.canvas.opacity(0.35))
    }

    private var deviceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: bleManager.isConnected ? "keyboard.fill" : "keyboard")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(bleManager.isConnected ? AhaKeyUI.ColorToken.primary : Color.secondary)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: AhaKeyUI.Radius.large, style: .continuous)
                            .fill(bleManager.isConnected ? AhaKeyUI.ColorToken.primary.opacity(0.12) : AhaKeyUI.ColorToken.control)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(bleManager.deviceName ?? "AhaKey Keyboard")
                        .font(AhaKeyUI.Font.title2)
                        .lineLimit(1)
                    Text(bleManager.isConnected ? "设备在线 · \(workModeDisplayName)" : "等待连接")
                        .font(AhaKeyUI.Font.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(bleManager.isConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                deviceStatTile("电量", value: bleManager.isConnected ? "\(bleManager.batteryLevel)%" : "—", systemImage: "battery.75")
                deviceStatTile("固件", value: "v\(bleManager.firmwareMainVersion).\(bleManager.firmwareSubVersion)", systemImage: "shippingbox")
                deviceStatTile("信号", value: bleManager.isConnected ? "\(bleManager.signalStrength) dBm" : "—", systemImage: "wifi")
                deviceStatTile("拨杆", value: switchStateDisplayName, systemImage: "switch.2")
            }
        }
        .padding(16)
        .ahaKeySurface()
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("通信日志", systemImage: "terminal")
                    .font(AhaKeyUI.Font.title2)
                Spacer()
                Button {
                    onCopyBLELog()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("复制全部通信日志")
                Button {
                    bleManager.clearLog()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("清空通信日志")
            }

            communicationLogList
        }
        .padding(16)
        .ahaKeySurface()
        .frame(maxHeight: .infinity)
    }

    private var communicationLogList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if bleManager.commLog.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.tertiary)
                        Text("暂无通信记录")
                            .font(AhaKeyUI.Font.subhead.weight(.semibold))
                        Text("连接、查询状态或探测协议后，BLE 通信会常驻显示在这里。")
                            .font(AhaKeyUI.Font.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(bleManager.commLog.suffix(120)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 74, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(entry.isError ? .red : .secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.64))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                    .strokeBorder(AhaKeyUI.ColorToken.border, lineWidth: 1)
            )
            .onChange(of: bleManager.commLog.count) { _, _ in
                if let last = bleManager.commLog.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func deviceStatTile(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AhaKeyUI.ColorToken.primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: AhaKeyUI.Radius.small, style: .continuous)
                        .fill(AhaKeyUI.ColorToken.primary.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AhaKeyUI.Font.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AhaKeyUI.Font.subhead.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AhaKeyUI.Radius.medium, style: .continuous)
                .fill(AhaKeyUI.ColorToken.control.opacity(0.58))
        )
    }
}
