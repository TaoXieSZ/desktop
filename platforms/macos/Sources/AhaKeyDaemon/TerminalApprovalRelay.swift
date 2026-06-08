import ApplicationServices
import Foundation

final class TerminalApprovalRelay: @unchecked Sendable {
    private let queue = DispatchQueue(label: "lab.jawa.ahakey.terminal-approval-relay")
    private let approveTriggerKeyCode: CGKeyCode = 80 // F19
    private let denyTriggerKeyCode: CGKeyCode = 90 // F20
    private let enterKeyCode: CGKeyCode = 36
    private let downArrowKeyCode: CGKeyCode = 125
    private let doublePressWindow: TimeInterval = 0.28
    private let syntheticEventUserData: Int64 = 0x4148414B45594150

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var pendingApprove: DispatchWorkItem?
    private var relayState = "not_started"
    private var lastAction = "none"

    func start() {
        queue.sync {
            guard thread == nil else { return }
            guard permissionsGranted else {
                relayState = "blocked"
                return
            }

            let worker = Thread { [weak self] in
                self?.installEventTap()
            }
            worker.name = "AhaKey terminal approval relay"
            thread = worker
            relayState = "starting"
            worker.start()
        }
    }

    func status() -> [String: Any] {
        queue.sync {
            let blockers = permissionBlockers
            return [
                "ready": blockers.isEmpty && eventTap != nil,
                "state": relayState,
                "lastAction": lastAction,
                "approveTrigger": "F19",
                "denyTrigger": "F20",
                "doublePressMs": Int(doublePressWindow * 1000),
                "singleApprove": "Enter",
                "doubleApprove": "Down,Enter",
                "deny": "Down,Down,Enter",
                "blockers": blockers,
            ]
        }
    }

    private func installEventTap() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let relay = Unmanaged<TerminalApprovalRelay>.fromOpaque(refcon).takeUnretainedValue()
            return relay.handleEvent(type: type, event: event)
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            queue.sync { relayState = "tap_create_failed" }
            appendDiagnostic("event tap create failed")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            queue.sync { relayState = "runloop_source_failed" }
            appendDiagnostic("runloop source create failed")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        queue.sync {
            eventTap = tap
            runLoopSource = source
            relayState = "listening"
        }
        appendDiagnostic("terminal approval relay listening: F19 approve/double-bypass, F20 deny")
        CFRunLoopRun()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            queue.sync {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    relayState = "listening"
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventUserData {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == approveTriggerKeyCode || keyCode == denyTriggerKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            return nil
        }

        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard !isAutoRepeat else { return nil }

        if keyCode == approveTriggerKeyCode {
            handleApprovePress()
        } else {
            handleDenyPress()
        }
        return nil
    }

    private func handleApprovePress() {
        queue.async {
            if let pending = self.pendingApprove {
                pending.cancel()
                self.pendingApprove = nil
                self.lastAction = "bypass"
                self.appendDiagnostic("approve double press -> bypass")
                self.postSequence([self.downArrowKeyCode, self.enterKeyCode])
                return
            }

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingApprove = nil
                self.lastAction = "approve"
                self.appendDiagnostic("approve single press -> enter")
                self.postSequence([self.enterKeyCode])
            }
            self.pendingApprove = work
            self.queue.asyncAfter(deadline: .now() + self.doublePressWindow, execute: work)
        }
    }

    private func handleDenyPress() {
        queue.async {
            self.pendingApprove?.cancel()
            self.pendingApprove = nil
            self.lastAction = "deny"
            self.appendDiagnostic("deny press -> down,down,enter")
            self.postSequence([self.downArrowKeyCode, self.downArrowKeyCode, self.enterKeyCode])
        }
    }

    private func postSequence(_ keyCodes: [CGKeyCode]) {
        for keyCode in keyCodes {
            postKey(keyCode, keyDown: true)
            Thread.sleep(forTimeInterval: 0.035)
            postKey(keyCode, keyDown: false)
            Thread.sleep(forTimeInterval: 0.045)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, keyDown: Bool) {
        let sources: [CGEventSourceStateID] = [.combinedSessionState, .hidSystemState]
        for stateID in sources {
            guard let event = CGEvent(
                keyboardEventSource: CGEventSource(stateID: stateID),
                virtualKey: keyCode,
                keyDown: keyDown
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
            event.post(tap: stateID == .combinedSessionState ? .cgSessionEventTap : .cghidEventTap)
        }
    }

    private var permissionsGranted: Bool {
        AXIsProcessTrusted() && CGPreflightListenEventAccess() && CGPreflightPostEventAccess()
    }

    private var permissionBlockers: [String] {
        var blockers: [String] = []
        if !AXIsProcessTrusted() {
            blockers.append("accessibility_missing")
        }
        if !CGPreflightListenEventAccess() {
            blockers.append("input_monitoring_missing")
        }
        if !CGPreflightPostEventAccess() {
            blockers.append("post_event_missing")
        }
        return blockers
    }

    private func appendDiagnostic(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
            .appendingPathComponent("terminal-approval-relay.log")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data(line.utf8).write(to: url)
            } else if let handle = try? FileHandle(forWritingTo: url) {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            }
        } catch {
            // Diagnostics must never break keyboard input.
        }
    }
}
