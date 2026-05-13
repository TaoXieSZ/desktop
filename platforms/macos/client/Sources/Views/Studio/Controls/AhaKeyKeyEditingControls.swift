import SwiftUI

struct VoicePresetPicker: View {
    let selectedPreset: VoicePreset
    let onSelect: (VoicePreset) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(VoicePreset.allCases) { preset in
                Button {
                    if preset.availableInV1 {
                        onSelect(preset)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(preset.title)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if !preset.availableInV1 {
                                Text("开发中")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(preset.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(cardFill(for: preset))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(cardStroke(for: preset), lineWidth: preset == selectedPreset ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!preset.availableInV1)
            }
        }
    }

    private func cardFill(for preset: VoicePreset) -> Color {
        if preset == selectedPreset {
            return Color.accentColor.opacity(0.16)
        }
        if !preset.availableInV1 {
            return Color(nsColor: .controlBackgroundColor).opacity(0.65)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private func cardStroke(for preset: VoicePreset) -> Color {
        if preset == selectedPreset {
            return .accentColor
        }
        return Color.black.opacity(0.08)
    }
}

struct ShortcutBindingEditor: View {
    @Binding var shortcut: ShortcutBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ShortcutModifier.allCases) { modifier in
                    Toggle(isOn: modifierBinding(modifier)) {
                        Text(modifier.symbol)
                            .font(.system(.headline, design: .rounded))
                    }
                    .toggleStyle(.button)
                    .help(modifier.title)
                }
                if !shortcut.modifiers.isEmpty {
                    Button("清除修饰键") {
                        var next = shortcut
                        next.modifiers = []
                        shortcut = next
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Picker("主键", selection: primaryKeyBinding) {
                Text("未设置").tag(UInt8(0))
                ForEach(HIDUsage.allOptions, id: \.code) { option in
                    Text(option.name).tag(option.code)
                }
            }
            .pickerStyle(.menu)

            if !shortcut.modifiers.isEmpty {
                Text("当前为组合键（\(shortcut.displayLabel)）。若你只想发单键 Enter，勿打开 ⌘/⌃ 等，或点「清除修饰键」后再选 Enter。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modifierBinding(_ modifier: ShortcutModifier) -> Binding<Bool> {
        Binding(
            get: { shortcut.modifiers.contains(modifier) },
            set: { on in
                var next = shortcut
                next.setModifier(modifier, enabled: on)
                shortcut = next
            }
        )
    }

    private var primaryKeyBinding: Binding<UInt8> {
        Binding(
            get: { shortcut.keyCode },
            set: { newCode in
                var next = shortcut
                next.keyCode = newCode
                shortcut = next
            }
        )
    }
}
