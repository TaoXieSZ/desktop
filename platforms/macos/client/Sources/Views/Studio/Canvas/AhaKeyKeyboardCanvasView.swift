import SwiftUI

struct AhaKeyKeyboardCanvasView: View {
    let modeDraft: AhaKeyModeDraft
    let selectedPart: AhaKeyStudioPart
    let lightBarPreview: LightBarPreviewState
    let switchTitle: String
    let dirtyParts: Set<AhaKeyStudioPart>
    let onSelect: (AhaKeyStudioPart) -> Void

    private let baseWidth: CGFloat = 109
    private let baseHeight: CGFloat = 54

    var body: some View {
        GeometryReader { proxy in
            let drawingWidth = min(proxy.size.width, proxy.size.height * (baseWidth / baseHeight))
            let drawingHeight = drawingWidth * (baseHeight / baseWidth)

            ZStack {
                keyboardFrame(width: drawingWidth, height: drawingHeight)
            }
            .frame(width: drawingWidth, height: drawingHeight)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder
    private func keyboardFrame(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color(red: 0.92, green: 0.95, blue: 0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.08), radius: 18, y: 14)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                .padding(12)

            VStack {
                Spacer()
            }

            ForEach(Array([(8.0, 8.0), (101.0, 8.0), (8.0, 46.0), (101.0, 46.0)].enumerated()), id: \.offset) { _, point in
                Circle()
                    .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                    .background(Circle().fill(Color.white.opacity(0.4)))
                    .frame(width: scaled(4.8, in: width), height: scaled(4.8, in: width))
                    .position(position(point.0, point.1, width: width, height: height))
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .frame(width: scaled(4.2, in: width), height: scaled(12, in: width))
                .position(position(3.8, 28, width: width, height: height))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: scaled(70, in: width), height: scaled(24, in: width))
                .position(position(43.8, 37.3, width: width, height: height))

            ledBarButton(width: width, height: height)
            oledButton(width: width, height: height)
            keyButton(for: .voice, width: width, height: height)
            keyButton(for: .approve, width: width, height: height)
            keyButton(for: .reject, width: width, height: height)
            keyButton(for: .submit, width: width, height: height)
            modeSwitchKey(width: width, height: height)
            switchButton(width: width, height: height)
        }
    }

    private func ledBarButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.lightBar
        let rect = frame(12.3, 5.0, 55.6, 9.8, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: rect.height * 0.12) {
                Text("灯条")
                    .font(.system(size: max(rect.height * 0.18, 10), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .center)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                    HStack(spacing: rect.width * 0.085) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(ledColor(for: index))
                                .frame(width: rect.width * 0.12, height: rect.height * 0.22)
                        }
                    }
                    .padding(.horizontal, rect.width * 0.08)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: rect.height * 0.48)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func oledButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.oledDisplay
        let rect = frame(71.2, 7.7, 24.2, 13.4, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                LinearGradient(
                    colors: [Color.black.opacity(0.2), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .center, spacing: 4) {
                    if modeDraft.oled.localAssetPath == nil {
                        if modeDraft.mode == .mode0 {
                            HStack(spacing: 6) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: rect.height * 0.24, weight: .semibold))
                                    .foregroundStyle(Color.orange.opacity(0.92))
                                Text("Mode 0")
                                    .font(.system(size: rect.height * 0.18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Text("默认动图")
                                .font(.system(size: rect.height * 0.18))
                                .foregroundStyle(.white.opacity(0.55))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: rect.height * 0.22, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("未上传")
                                    .font(.system(size: rect.height * 0.18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Text("等待自定义")
                                .font(.system(size: rect.height * 0.18))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: rect.height * 0.22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                            Text("已上传")
                                .font(.system(size: rect.height * 0.2, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Text("预览动画中")
                            .font(.system(size: rect.height * 0.18))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(rect.width * 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func keyButton(for role: AhaKeyKeyRole, width: CGFloat, height: CGFloat) -> some View {
        let part = role.part
        let keyDraft = modeDraft.key(for: role)
        let specs: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
        switch role {
        case .voice:
            specs = (10.2, 29.2, 16.2, 16.8)
        case .approve:
            specs = (27.2, 29.2, 16.2, 16.8)
        case .reject:
            specs = (44.2, 29.2, 16.2, 16.8)
        case .submit:
            specs = (61.2, 29.2, 16.2, 16.8)
        }
        let rect = frame(specs.x, specs.y, specs.w, specs.h, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: rect.height * 0.07) {
                ZStack {
                    RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(red: 0.95, green: 0.96, blue: 0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    Image(systemName: role.systemImage)
                        .font(.system(size: rect.height * 0.24, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.88))
                }
                .frame(width: rect.width * 0.8, height: rect.height * 0.76)

                Text(keyDraft.description.isEmpty ? keyDraft.displaySummary : keyDraft.description)
                    .font(.system(size: rect.height * 0.11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func modeSwitchKey(width: CGFloat, height: CGFloat) -> some View {
        let rect = frame(78.9, 40.9, 8.0, 10.2, width: width, height: height)
        return VStack(spacing: rect.height * 0.08) {
            ZStack {
                RoundedRectangle(cornerRadius: rect.width * 0.2, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: rect.width * 0.2, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: rect.height * 0.18, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.42))
            }
            .frame(width: rect.width * 0.78, height: rect.height * 0.5)

            Text("Mode")
                .font(.system(size: rect.height * 0.1, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .help("实体模式切换键")
    }

    private func switchButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.toggleSwitch
        let rect = frame(87.8, 35.6, 6.8, 10.6, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    Capsule()
                        .fill(Color.white)
                        .frame(width: rect.width * 0.36, height: rect.height * 0.65)
                        .overlay(Circle().fill(Color.gray.opacity(0.24)).frame(width: rect.width * 0.28, height: rect.width * 0.28))
                        .offset(y: switchTitle == "自动批准" ? -rect.height * 0.08 : rect.height * 0.12)
                }
                .frame(width: rect.width * 0.58, height: rect.height * 0.78)

                Text(switchTitle)
                    .font(.system(size: rect.height * 0.12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: x / baseWidth * width,
            y: y / baseHeight * height,
            width: w / baseWidth * width,
            height: h / baseHeight * height
        )
    }

    private func position(_ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: x / baseWidth * width, y: y / baseHeight * height)
    }

    private func scaled(_ value: CGFloat, in width: CGFloat) -> CGFloat {
        value / baseWidth * width
    }

    private func ledColor(for index: Int) -> Color {
        switch AhaKeyLightBarDraft.hardwareEffect(for: lightBarPreview) {
        case .middleLight:
            [Color.red.opacity(0.28), Color.red.opacity(0.86), Color.red.opacity(0.86), Color.red.opacity(0.28)][index]
        case .singleMove:
            [Color.cyan, Color.blue.opacity(0.65), Color.cyan, Color.blue.opacity(0.65)][index]
        case .breathing:
            [Color.orange.opacity(0.65), Color.yellow.opacity(0.82), Color.orange.opacity(0.65), Color.yellow.opacity(0.82)][index]
        case .rainbowMove:
            [Color.orange, Color.yellow, Color.green, Color.blue][index]
        case .rainbowWave:
            [Color.pink, Color.orange, Color.green, Color.blue][index]
        case .rainbowWaveSlow:
            [Color.purple, Color.pink, Color.teal, Color.blue.opacity(0.8)][index]
        case .off:
            [Color.gray.opacity(0.18), Color.gray.opacity(0.18), Color.gray.opacity(0.18), Color.gray.opacity(0.18)][index]
        }
    }
}

private struct HotspotChrome: ViewModifier {
    let part: AhaKeyStudioPart
    let selectedPart: AhaKeyStudioPart
    let dirtyParts: Set<AhaKeyStudioPart>

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selectedPart == part ? Color.accentColor : Color.black.opacity(0.05), lineWidth: selectedPart == part ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if dirtyParts.contains(part) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            .shadow(color: selectedPart == part ? Color.accentColor.opacity(0.18) : .clear, radius: 10)
    }
}
