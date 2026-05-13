import AppKit
import DynamicNotchKit
import SwiftUI

@main
struct AhaKeyNotchSmokeApp: App {
    @NSApplicationDelegateAdaptor(NotchSmokeDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class NotchSmokeDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchSmokeController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = controller
        let notch = DynamicNotch(
            hoverBehavior: [.increaseShadow],
            style: .notch
        ) {
            SmokeExpandedMenu(
                onAppear: {
                    controller.expandedMenuAppeared()
                },
                onHoverChanged: { controller.expandedHoverChanged($0) },
                onCompact: {
                    controller.compactNow()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        } compactLeading: {
            SmokeCompactItem(
                systemName: "keyboard",
                title: "AhaKey",
                color: .cyan,
                onHoverChanged: { hovering in
                    controller.compactHoverChanged(hovering)
                }
            )
        } compactTrailing: {
            SmokeCompactItem(
                systemName: "mic.fill",
                title: "Voice",
                color: .green,
                onHoverChanged: { hovering in
                    controller.compactHoverChanged(hovering)
                }
            )
        }

        controller.attach(notch)
        controller.compactNow()
    }
}

@MainActor
final class NotchSmokeController {
    private var notch: (any DynamicNotchControllable)?
    private var pendingCompactTask: Task<Void, Never>?
    private var pointerTimer: Timer?
    private var isHoveringExpanded = false
    private var isExpanded = false

    func attach(_ notch: any DynamicNotchControllable) {
        self.notch = notch
        startPointerTracking()
    }

    func compactNow() {
        pendingCompactTask?.cancel()
        isExpanded = false
        isHoveringExpanded = false
        Task {
            await notch?.compact(on: targetScreen)
        }
    }

    func expandNow() {
        pendingCompactTask?.cancel()
        isExpanded = true
        Task {
            await notch?.expand(on: targetScreen)
        }
    }

    func compactHoverChanged(_ hovering: Bool) {
        if hovering {
            expandNow()
        }
    }

    func expandedMenuAppeared() {
        pendingCompactTask?.cancel()
        isExpanded = true
    }

    func expandedHoverChanged(_ hovering: Bool) {
        isHoveringExpanded = hovering
        if hovering {
            pendingCompactTask?.cancel()
        } else {
            scheduleCompactIfIdle()
        }
    }

    private func scheduleCompactIfIdle() {
        pendingCompactTask?.cancel()
        pendingCompactTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.compactIfIdle()
        }
    }

    private func compactIfIdle() {
        guard isExpanded, !isHoveringExpanded else { return }
        compactNow()
    }

    private func startPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.expandIfPointerIsInTopHotZone()
            }
        }
        RunLoop.main.add(pointerTimer!, forMode: .common)
    }

    private func expandIfPointerIsInTopHotZone() {
        guard !isExpanded, topHotZone.contains(NSEvent.mouseLocation) else { return }
        expandNow()
    }

    private var topHotZone: CGRect {
        let screen = targetScreen
        let width: CGFloat = 440
        let height: CGFloat = 58
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private var targetScreen: NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
    }
}

private struct SmokeCompactItem: View {
    let systemName: String
    let title: String
    let color: Color
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
    }
}

private struct SmokeExpandedMenu: View {
    let onAppear: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onCompact: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AhaKey Island")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Hover menu smoke target")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCompact) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                menuButton("VoiceAgent", systemName: "waveform")
                menuButton("Device", systemName: "battery.75percent")
                menuButton("Approve", systemName: "checkmark.circle")
                menuButton("OLED", systemName: "rectangle.inset.filled")
            }

            HStack(spacing: 8) {
                Button("Quit Smoke", action: onQuit)
                    .buttonStyle(.bordered)
                Spacer()
                Text("Move cursor away to collapse")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onAppear(perform: onAppear)
        .onHover(perform: onHoverChanged)
    }

    private func menuButton(_ title: String, systemName: String) -> some View {
        Button {
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 90, height: 58)
        }
        .buttonStyle(.borderless)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
