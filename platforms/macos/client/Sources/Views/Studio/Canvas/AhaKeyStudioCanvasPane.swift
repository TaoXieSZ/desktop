import AhaKeyConfigUI
import SwiftUI

struct AhaKeyStudioCanvasPane: View {
    let modeDraft: AhaKeyModeDraft
    @Binding var selectedPart: AhaKeyStudioPart
    let lightBarPreview: LightBarPreviewState
    let switchTitle: String
    let dirtyParts: Set<AhaKeyStudioPart>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AhaKeyStudioModeEditorHeader(mode: modeDraft.mode)

            VStack(alignment: .leading, spacing: 8) {
                AhaKeyKeyboardCanvasView(
                    modeDraft: modeDraft,
                    selectedPart: selectedPart,
                    lightBarPreview: lightBarPreview,
                    switchTitle: switchTitle,
                    dirtyParts: dirtyParts,
                    onSelect: { selectedPart = $0 }
                )
                .aspectRatio(109.0 / 54.0, contentMode: .fit)
                .frame(maxWidth: .infinity)

                Text("点按灯条、屏幕、四个按键或拨杆即可进入对应配置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .ahaKeySurface()

            HStack(spacing: 12) {
                manualCallout(
                    title: "主流程",
                    detail: "默认键盘控制 -> 点编辑配置 -> 修改 -> 同步到设备 -> 返回控制"
                )
                manualCallout(
                    title: "模式切换",
                    detail: "短按设备按键切换模式，OLED 会先显示描述约 1 秒，再回到该模式动图"
                )
            }
        }
        .padding(24)
        .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        .background(AhaKeyUI.ColorToken.canvas.opacity(0.35))
    }

    private func manualCallout(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.callout)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ahaKeyRemarkPanel()
    }
}

struct AhaKeyStudioModeEditorHeader: View {
    let mode: AhaKeyModeSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("设备展示")
                    .font(AhaKeyUI.Font.title2)
                Text("65%")
                    .font(AhaKeyUI.Font.subhead)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
                Text(mode.title)
                    .font(AhaKeyUI.Font.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .ahaKeyPill()
            }

            Text(mode.guidance)
                .font(AhaKeyUI.Font.callout)
                .foregroundStyle(.secondary)
        }
    }
}
