import AppKit
import Foundation

@MainActor
final class CodexOLEDStatusFileBridge {
    static let shared = CodexOLEDStatusFileBridge()

    private weak var bleManager: AhaKeyBLEManager?
    private var source: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1
    private var lastDisplayKey: String?
    private var isUploading = false
    private var pending: Payload?
    private let codexHUDModes: [UInt8] = [0, 1, 2]
    var onPayloadLinesChanged: (([String]) -> Void)?

    private struct Payload {
        let lines: [String]
        let mode: UInt8
        let displayKey: String
    }

    private var statusURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("AhaKeyConfig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("codex-oled-status.json")
    }

    private var bridgeLogURL: URL {
        statusURL
            .deletingLastPathComponent()
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("codex-oled-bridge.log")
    }

    func start(bleManager: AhaKeyBLEManager) {
        self.bleManager = bleManager
        guard source == nil else {
            log("start reused existing watcher")
            processLatest()
            return
        }

        let url = statusURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data("{}".utf8).write(to: url)
        }
        watchedFD = open(url.path, O_EVTONLY)
        guard watchedFD >= 0 else {
            log("failed to open status file watcher: \(url.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedFD,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            let eventMask = source.data
            Task { @MainActor in
                guard let self else { return }
                self.log("file event: \(eventMask.rawValue)")
                if eventMask.contains(.delete) || eventMask.contains(.rename) {
                    self.rearmWatcher()
                } else {
                    self.processLatest()
                }
            }
        }
        source.setCancelHandler { [fd = watchedFD] in
            if fd >= 0 { close(fd) }
        }
        self.source = source
        source.resume()
        log("watching \(url.path)")
        processLatest()
    }

    func stop() {
        source?.cancel()
        source = nil
        watchedFD = -1
    }

    private func rearmWatcher() {
        guard let bleManager else { return }
        stop()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self.start(bleManager: bleManager)
        }
    }

    private func processLatest() {
        guard let payload = readPayload() else { return }
        log("read payload: \(payload.displayKey.replacingOccurrences(of: "\n", with: " | "))")
        onPayloadLinesChanged?(payload.lines)
        pending = payload
        drain()
    }

    private func drain() {
        guard !isUploading, let payload = pending else { return }
        pending = nil
        guard payload.displayKey != lastDisplayKey else {
            log("skip duplicate payload")
            return
        }
        guard let bleManager, bleManager.isConnected, !bleManager.isUploadingOLED else {
            log("waiting: connected=\(bleManager?.isConnected ?? false) uploading=\(bleManager?.isUploadingOLED ?? false)")
            pending = payload
            return
        }

        isUploading = true
        log("upload start: requestedMode=\(payload.mode) modes=\(codexHUDModes.map(String.init).joined(separator: ","))")
        Task { @MainActor in
            do {
                let frame = Self.render(lines: payload.lines)
                for mode in self.codexHUDModes {
                    try await bleManager.uploadOLEDFrames(
                        [frame],
                        fps: 1,
                        mode: mode,
                        startIndex: 0
                    )
                }
                lastDisplayKey = payload.displayKey
                log("upload complete")
            } catch {
                // Keep the latest payload pending so the next file event or app reconnect can retry.
                log("upload failed: \(error.localizedDescription)")
                pending = payload
            }
            isUploading = false
            drain()
        }
    }

    private func readPayload() -> Payload? {
        guard let data = try? Data(contentsOf: statusURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawLines = obj["lines"] as? [String]
        let model = obj["model"] as? String
        let reasoning = obj["reasoning"] as? String
        let context = obj["contextLeftPercent"] as? Int
        let tokens = obj["turnTokens"] as? Int
        let lines = rawLines ?? [
            [model, reasoning].compactMap { $0 }.joined(separator: " "),
            context.map { "Context \($0)% left" } ?? "Context -- left",
            tokens.map { "Turn \(Self.formatTokenCount($0)) tok" } ?? "Turn -- tok",
        ]
        let cleanLines = lines.prefix(3).map { Self.truncateASCII($0.isEmpty ? "--" : $0, maxLength: 22) }
        guard cleanLines.count == 3 else { return nil }
        let mode = UInt8(clamping: obj["mode"] as? Int ?? 2)
        return Payload(lines: cleanLines, mode: mode, displayKey: cleanLines.joined(separator: "\n"))
    }

    private static func render(lines: [String]) -> Data {
        let width = AhaKeyCommand.oledWidth
        let height = AhaKeyCommand.oledHeight
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data(repeating: 0, count: width * height * 2)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        for (index, line) in lines.prefix(3).enumerated() {
            (line as NSString).draw(at: NSPoint(x: 6, y: 53 - index * 22), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        var data = Data(capacity: width * height * 2)
        for pixel in stride(from: 0, to: rgba.count, by: bytesPerPixel) {
            let red = UInt16(rgba[pixel])
            let green = UInt16(rgba[pixel + 1])
            let blue = UInt16(rgba[pixel + 2])
            let rgb565 = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
            data.append(UInt8((rgb565 >> 8) & 0xFF))
            data.append(UInt8(rgb565 & 0xFF))
        }
        return data
    }

    private static func truncateASCII(_ text: String, maxLength: Int) -> String {
        let ascii = text.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && !CharacterSet.controlCharacters.contains(scalar) ? Character(scalar) : "?"
        }
        let clean = String(ascii).trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maxLength else { return clean }
        return String(clean.prefix(max(1, maxLength - 1))) + "~"
    }

    private static func formatTokenCount(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    private func log(_ message: String) {
        let url = bridgeLogURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
