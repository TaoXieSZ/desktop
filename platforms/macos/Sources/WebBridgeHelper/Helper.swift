@preconcurrency import CoreBluetooth
import Darwin
import Foundation

enum HelperError: Error, LocalizedError {
    case invalidCommand(String)
    case missingValue(String)
    case invalidValue(String)
    case bluetoothUnavailable(String)
    case deviceUnavailable
    case characteristicUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCommand(let command):
            return "unknown command: \(command)"
        case .missingValue(let name):
            return "missing value: \(name)"
        case .invalidValue(let detail):
            return "invalid value: \(detail)"
        case .bluetoothUnavailable(let detail):
            return "bluetooth unavailable: \(detail)"
        case .deviceUnavailable:
            return "AhaKey device unavailable"
        case .characteristicUnavailable:
            return "command characteristic unavailable"
        }
    }
}

private struct CommandIntent {
    let step: String
    let label: String
    let hex: String

    var json: [String: Any] {
        ["step": step, "label": label, "hex": hex]
    }
}

private struct HelperInput {
    var command: String
    var dryRun = false
    var mode: Int?
    var keyIndex: Int?
    var hidCodes: [UInt8] = []
    var label: String?
    var gifPath: String?
    var fps: Int = 8
    var maxFrames: Int?
    var startIndex: Int = 0
}

@main
struct AhaKeyWebBridgeHelper {
    static func main() {
        do {
            let input = try parseInput(Array(CommandLine.arguments.dropFirst()))
            switch input.command {
            case "status":
                try runStatus(input)
            case "apply-shortcut":
                try runApplyShortcut(input)
            case "upload-oled":
                try runUploadOLED(input)
            default:
                throw HelperError.invalidCommand(input.command)
            }
        } catch {
            writeJSON([
                "ok": false,
                "error": error.localizedDescription,
            ])
            Foundation.exit(2)
        }
    }

    private static func runStatus(_ input: HelperInput) throws {
        if input.dryRun {
            writeJSON([
                "ok": true,
                "dryRun": true,
                "connected": false,
                "device": NSNull(),
                "owner": currentOwner(),
            ])
            return
        }

        let client = HelperBLEClient()
        let status = try client.status()
        writeJSON([
            "ok": true,
            "dryRun": false,
            "connected": true,
            "device": status,
            "owner": currentOwner(),
        ])
    }

    private static func runApplyShortcut(_ input: HelperInput) throws {
        guard let mode = input.mode else { throw HelperError.missingValue("mode") }
        guard let keyIndex = input.keyIndex else { throw HelperError.missingValue("keyIndex") }
        try validate(mode: mode, keyIndex: keyIndex, hidCodes: input.hidCodes)
        let intents = makeShortcutIntents(
            mode: UInt8(mode),
            keyIndex: UInt8(keyIndex),
            hidCodes: input.hidCodes,
            label: input.label
        )

        if input.dryRun {
            writeJSON([
                "ok": true,
                "dryRun": true,
                "connected": false,
                "commands": intents.map(\.json),
                "saved": false,
                "returnedToAgent": false,
                "hardwareMutated": false,
            ])
            return
        }

        acquireWebEditOwnership()
        var didRestoreAgent = false
        defer {
            if !didRestoreAgent {
                _ = restoreAgentOwnership()
            }
        }

        let client = HelperBLEClient()
        try client.apply(commands: intents)
        let returnResult = restoreAgentOwnership()
        didRestoreAgent = true

        writeJSON([
            "ok": true,
            "dryRun": false,
            "connected": true,
            "commands": intents.map(\.json),
            "saved": true,
            "returnedToAgent": returnResult.ok,
            "returnReason": returnResult.reason ?? NSNull(),
            "hardwareMutated": true,
        ])
    }

    private static func runUploadOLED(_ input: HelperInput) throws {
        guard let modeInt = input.mode, (0...2).contains(modeInt) else { throw HelperError.invalidValue("mode must be 0...2") }
        guard let gifPath = input.gifPath else { throw HelperError.missingValue("gif") }
        let url = URL(fileURLWithPath: gifPath)
        let frames = try OLEDUploadEncoder.frames(fromGIFAt: url, mode: modeInt, maxFrames: input.maxFrames)

        if input.dryRun {
            writeJSON(["ok": true, "dryRun": true, "connected": false, "frames": frames.count,
                       "bytesPerFrame": frames.first?.count ?? 0, "mode": modeInt])
            return
        }

        acquireWebEditOwnership()
        var didRestoreAgent = false
        defer { if !didRestoreAgent { _ = restoreAgentOwnership() } }

        let client = HelperBLEClient()
        try client.uploadOLED(frames: frames, fps: input.fps, mode: UInt8(modeInt), startIndex: UInt16(input.startIndex))
        let returnResult = restoreAgentOwnership()
        didRestoreAgent = true

        writeJSON(["ok": true, "dryRun": false, "connected": true, "mode": modeInt,
                   "frames": frames.count, "fps": input.fps, "startIndex": input.startIndex,
                   "returnedToAgent": returnResult.ok, "hardwareMutated": true])
    }

    private static func parseInput(_ args: [String]) throws -> HelperInput {
        guard let command = args.first else { throw HelperError.missingValue("command") }
        var input = HelperInput(command: command)
        var index = 1
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--dry-run":
                input.dryRun = true
                index += 1
            case "--mode":
                input.mode = try intArg(args, index: &index, name: "mode")
            case "--key-index":
                input.keyIndex = try intArg(args, index: &index, name: "key-index")
            case "--hid-codes":
                input.hidCodes = try hidCodesArg(args, index: &index)
            case "--label":
                input.label = try stringArg(args, index: &index, name: "label")
            case "--gif":
                input.gifPath = try stringArg(args, index: &index, name: "gif")
            case "--fps":
                input.fps = try intArg(args, index: &index, name: "fps")
            case "--max-frames":
                input.maxFrames = try intArg(args, index: &index, name: "max-frames")
            case "--start-index":
                input.startIndex = try intArg(args, index: &index, name: "start-index")
            default:
                throw HelperError.invalidValue(arg)
            }
        }
        return input
    }

    private static func intArg(_ args: [String], index: inout Int, name: String) throws -> Int {
        let value = try stringArg(args, index: &index, name: name)
        guard let intValue = Int(value) else { throw HelperError.invalidValue("\(name)=\(value)") }
        return intValue
    }

    private static func stringArg(_ args: [String], index: inout Int, name: String) throws -> String {
        let next = index + 1
        guard next < args.count else { throw HelperError.missingValue(name) }
        index += 2
        return args[next]
    }

    private static func hidCodesArg(_ args: [String], index: inout Int) throws -> [UInt8] {
        let value = try stringArg(args, index: &index, name: "hid-codes")
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try value.split(separator: ",").map { part in
            let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let intValue: Int?
            if text.lowercased().hasPrefix("0x") {
                intValue = Int(text.dropFirst(2), radix: 16)
            } else {
                intValue = Int(text)
            }
            guard let intValue, (0...255).contains(intValue) else {
                throw HelperError.invalidValue("hid-codes=\(value)")
            }
            return UInt8(intValue)
        }
    }

    private static func validate(mode: Int, keyIndex: Int, hidCodes: [UInt8]) throws {
        guard (0...2).contains(mode) else { throw HelperError.invalidValue("mode must be 0...2") }
        guard (0...3).contains(keyIndex) else { throw HelperError.invalidValue("keyIndex must be 0...3") }
        guard hidCodes.count <= 98 else { throw HelperError.invalidValue("hidCodes exceeds firmware limit") }
    }

    private static func makeShortcutIntents(mode: UInt8, keyIndex: UInt8, hidCodes: [UInt8], label: String?) -> [CommandIntent] {
        var intents: [CommandIntent] = [
            CommandIntent(step: "acquire-edit-ownership", label: "Acquire web edit ownership", hex: ""),
            CommandIntent(step: "clear-macro-layer", label: "Clear Mode\(mode) Key\(keyIndex + 1) macro layer", hex: AhaKeyPacket.setKeyMacro(mode: mode, keyIndex: keyIndex, macroData: []).hexString),
            CommandIntent(step: "write-shortcut", label: "Write Mode\(mode) Key\(keyIndex + 1) shortcut", hex: AhaKeyPacket.setKeyMapping(mode: mode, keyIndex: keyIndex, hidCodes: hidCodes).hexString),
        ]
        if let label, !label.isEmpty {
            intents.append(CommandIntent(step: "write-description", label: "Write Mode\(mode) Key\(keyIndex + 1) description", hex: AhaKeyPacket.setKeyDescription(mode: mode, keyIndex: keyIndex, text: label).hexString))
        }
        intents.append(CommandIntent(step: "save-config", label: "Save config to device", hex: AhaKeyPacket.saveConfig().hexString))
        intents.append(CommandIntent(step: "return-agent-ownership", label: "Return control to Agent", hex: ""))
        return intents
    }

    private static func currentOwner() -> String {
        UserDefaults.standard.string(forKey: "lab.jawa.ahakeyconfig.bluetoothConnectionOwner") ?? "unknown"
    }

    private static func acquireWebEditOwnership() {
        UserDefaults.standard.set("ahaKeyStudio", forKey: "lab.jawa.ahakeyconfig.bluetoothConnectionOwner")
        runLaunchctl(["unload", launchAgentPath()])
        try? FileManager.default.removeItem(atPath: "/tmp/ahakey.sock")
    }

    private static func restoreAgentOwnership() -> (ok: Bool, reason: String?) {
        UserDefaults.standard.set("agentDaemon", forKey: "lab.jawa.ahakeyconfig.bluetoothConnectionOwner")
        let plist = launchAgentPath()
        guard FileManager.default.fileExists(atPath: plist) else {
            return (false, "agent_launch_agent_not_installed")
        }
        _ = runLaunchctl(["load", plist])
        _ = runLaunchctl(["start", "lab.jawa.ahakeyconfig.agent"])
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: "/tmp/ahakey.sock") {
                return (true, nil)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return (false, "agent_socket_not_ready")
    }

    private static func launchAgentPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.plist")
            .path
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func writeJSON(_ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

enum AhaKeyPacket {
    static let header: [UInt8] = [0xAA, 0xBB]
    static let trailer: [UInt8] = [0xCC, 0xDD]
    static let serviceUUID = CBUUID(string: "7340")
    static let dataCharUUID = CBUUID(string: "7341")
    static let commandCharUUID = CBUUID(string: "7343")
    static let notifyCharUUID = CBUUID(string: "7344")
    static let deviceNamePrefix = "vibe code"
    static let cmdSaveConfig: UInt8 = 0x04
    static let cmdUpdateCustomKey: UInt8 = 0x73
    static let subShortcut: UInt8 = 0x73
    static let subMacro: UInt8 = 0x74
    static let subDescription: UInt8 = 0x75

    // OLED upload (mirrors AhaKeyConfig/AhaKeyProtocol)
    static let cmdPrepareWrite: UInt8 = 0x80
    static let cmdWriteResult: UInt8 = 0x81
    static let cmdUpdatePic: UInt8 = 0x82
    static let oledWidth = 160
    static let oledHeight = 80
    static let oledFrameSlotSize = 28_672
    static let oledMaxFrames = 74
    static let oledChunkSize = 4096
    static let oledPacketSize = 180

    static func queryDeviceStatus() -> Data {
        Data(header + [0x00] + trailer)
    }

    static func prepareWrite(flag: UInt8 = 0x00, chunkLength: Int, address: UInt32) -> Data {
        let payload: [UInt8] = [
            flag,
            UInt8(chunkLength & 0xFF), UInt8((chunkLength >> 8) & 0xFF),
            UInt8(address & 0xFF), UInt8((address >> 8) & 0xFF),
            UInt8((address >> 16) & 0xFF), UInt8((address >> 24) & 0xFF),
        ]
        return Data(header + [cmdPrepareWrite] + payload + trailer)
    }

    static func updatePicture(mode: UInt8, startIndex: UInt16, frameCount: UInt16, timeDelayMs: UInt16) -> Data {
        let payload: [UInt8] = [
            mode,
            UInt8(startIndex & 0xFF), UInt8((startIndex >> 8) & 0xFF),
            UInt8(frameCount & 0xFF), UInt8((frameCount >> 8) & 0xFF),
            UInt8(timeDelayMs & 0xFF), UInt8((timeDelayMs >> 8) & 0xFF),
        ]
        return Data(header + [cmdUpdatePic] + payload + trailer)
    }

    /// ack 帧 `AA BB [cmd] [status] [payload] CC DD`，status==0 表示成功。
    static func parseCommandResponse(_ data: Data) -> (cmd: UInt8, status: UInt8)? {
        guard data.count >= 6, data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else { return nil }
        return (data[2], data[3])
    }

    static func saveConfig() -> Data {
        Data(header + [cmdSaveConfig] + trailer)
    }

    static func setKeyMapping(mode: UInt8, keyIndex: UInt8, hidCodes: [UInt8]) -> Data {
        Data(header + [cmdUpdateCustomKey, subShortcut, mode, keyIndex] + hidCodes + trailer)
    }

    static func setKeyMacro(mode: UInt8, keyIndex: UInt8, macroData: [UInt8]) -> Data {
        Data(header + [cmdUpdateCustomKey, subMacro, mode, keyIndex] + macroData + trailer)
    }

    static func setKeyDescription(mode: UInt8, keyIndex: UInt8, text: String) -> Data {
        Data(header + [cmdUpdateCustomKey, subDescription, mode, keyIndex] + Array(text.sanitizedASCII(maxLength: 20).utf8) + trailer)
    }
}

private final class HelperBLEClient: NSObject, @unchecked Sendable, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let queue = DispatchQueue(label: "lab.jawa.ahakeyconfig.webbridgehelper.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var dataChar: CBCharacteristic?
    private let ackSem = DispatchSemaphore(value: 0)
    private var lastAck: (cmd: UInt8, status: UInt8)?
    private let stateSem = DispatchSemaphore(value: 0)
    private let foundSem = DispatchSemaphore(value: 0)
    private let connectedSem = DispatchSemaphore(value: 0)
    private let serviceSem = DispatchSemaphore(value: 0)
    private let charSem = DispatchSemaphore(value: 0)
    private let statusSem = DispatchSemaphore(value: 0)
    private var latestStatus: [String: Any]?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    func status() throws -> [String: Any] {
        try connect()
        write(AhaKeyPacket.queryDeviceStatus())
        guard statusSem.wait(timeout: .now() + 2) == .success, let latestStatus else {
            return ["connected": true, "statusAvailable": false]
        }
        return latestStatus
    }

    func apply(commands: [CommandIntent]) throws {
        try connect()
        for command in commands where !command.hex.isEmpty {
            guard let data = Data(hexString: command.hex) else { continue }
            write(data)
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    func uploadOLED(frames: [Data], fps: Int, mode: UInt8, startIndex: UInt16) throws {
        try connect()
        guard let peripheral, dataChar != nil else { throw HelperError.characteristicUnavailable }
        let dch = dataChar!
        let writeType: CBCharacteristicWriteType = dch.properties.contains(.write) ? .withResponse : .withoutResponse
        let subSize = min(max(1, peripheral.maximumWriteValueLength(for: writeType)), AhaKeyPacket.oledPacketSize)

        for (i, frame) in frames.enumerated() {
            let frameAddr = UInt32(Int(startIndex) + i) * UInt32(AhaKeyPacket.oledFrameSlotSize)
            var off = 0
            while off < frame.count {
                let end = min(off + AhaKeyPacket.oledChunkSize, frame.count)
                let chunk = Data(frame[off ..< end])
                try sendAwaitingAck(AhaKeyPacket.prepareWrite(chunkLength: chunk.count, address: frameAddr + UInt32(off)),
                                    expect: AhaKeyPacket.cmdPrepareWrite)
                var p = 0
                while p < chunk.count {
                    let e = min(p + subSize, chunk.count)
                    peripheral.writeValue(Data(chunk[p ..< e]), for: dch, type: writeType)
                    Thread.sleep(forTimeInterval: 0.012)
                    p = e
                }
                try waitAck(expect: AhaKeyPacket.cmdWriteResult, timeout: 6)
                off = end
            }
            FileHandle.standardError.write(Data("  frame \(i + 1)/\(frames.count) ok\n".utf8))
        }
        let delay = UInt16(max(1, 1000 / max(1, fps)))
        try sendAwaitingAck(AhaKeyPacket.updatePicture(mode: mode, startIndex: startIndex,
                                                       frameCount: UInt16(frames.count), timeDelayMs: delay),
                            expect: AhaKeyPacket.cmdUpdatePic)
    }

    private func sendAwaitingAck(_ data: Data, expect: UInt8, timeout: Double = 5) throws {
        while ackSem.wait(timeout: DispatchTime.now()) == .success {} // drain stale
        lastAck = nil
        write(data)
        try waitAck(expect: expect, timeout: timeout)
    }

    private func waitAck(expect: UInt8, timeout: Double) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            guard ackSem.wait(timeout: .now() + remaining) == .success else { break }
            guard let ack = lastAck, ack.cmd == expect else { continue }
            guard ack.status == 0 else {
                throw HelperError.invalidValue("device rejected cmd 0x\(String(expect, radix: 16)) status \(ack.status)")
            }
            return
        }
        throw HelperError.invalidValue("timeout waiting ack 0x\(String(expect, radix: 16))")
    }

    private func connect() throws {
        guard stateSem.wait(timeout: .now() + 10) == .success else {
            throw HelperError.bluetoothUnavailable("state timeout")
        }
        guard central.state == .poweredOn else {
            throw HelperError.bluetoothUnavailable("state=\(central.state.rawValue)")
        }
        if let connected = central.retrieveConnectedPeripherals(withServices: [AhaKeyPacket.serviceUUID])
            .first(where: { ($0.name ?? "").lowercased().hasPrefix(AhaKeyPacket.deviceNamePrefix) }) {
            peripheral = connected
            connected.delegate = self
            central.connect(connected, options: nil)
            guard connectedSem.wait(timeout: .now() + 8) == .success else {
                throw HelperError.deviceUnavailable
            }
            connected.discoverServices([AhaKeyPacket.serviceUUID])
            guard serviceSem.wait(timeout: .now() + 5) == .success else {
                throw HelperError.deviceUnavailable
            }
            guard charSem.wait(timeout: .now() + 5) == .success, commandChar != nil else {
                throw HelperError.characteristicUnavailable
            }
            return
        }
        // 设备广播包只含 1812(HID)/180F(电量),不含私有服务 7340 —— 7340 仅在连接后于 GATT 暴露。
        // 因此扫描不能按 7340 过滤(会永远扫不到),改为全量扫描,由 didDiscover 的名字前缀("vibe code")筛选。
        central.scanForPeripherals(withServices: nil, options: nil)
        guard foundSem.wait(timeout: .now() + 10) == .success, let peripheral else {
            central.stopScan()
            throw HelperError.deviceUnavailable
        }
        central.stopScan()
        central.connect(peripheral, options: nil)
        guard connectedSem.wait(timeout: .now() + 8) == .success else {
            throw HelperError.deviceUnavailable
        }
        peripheral.delegate = self
        peripheral.discoverServices([AhaKeyPacket.serviceUUID])
        guard serviceSem.wait(timeout: .now() + 5) == .success else {
            throw HelperError.deviceUnavailable
        }
        guard charSem.wait(timeout: .now() + 5) == .success, commandChar != nil else {
            throw HelperError.characteristicUnavailable
        }
    }

    private func write(_ data: Data) {
        guard let peripheral, let commandChar else { return }
        let type: CBCharacteristicWriteType = commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: type)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.lowercased().hasPrefix(AhaKeyPacket.deviceNamePrefix) else { return }
        self.peripheral = peripheral
        foundSem.signal()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == AhaKeyPacket.serviceUUID }) else { return }
        serviceSem.signal()
        peripheral.discoverCharacteristics([AhaKeyPacket.dataCharUUID, AhaKeyPacket.commandCharUUID, AhaKeyPacket.notifyCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case AhaKeyPacket.commandCharUUID:
                commandChar = char
            case AhaKeyPacket.notifyCharUUID:
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            case AhaKeyPacket.dataCharUUID:
                dataChar = char
                peripheral.setNotifyValue(true, for: char) // ack 帧(0x80/0x81/0x82)可能从数据特征回
            default:
                break
            }
        }
        charSem.signal()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if let status = parseDeviceStatus(data) {
            latestStatus = status
            statusSem.signal()
            return
        }
        if let ack = AhaKeyPacket.parseCommandResponse(data) {
            lastAck = ack
            ackSem.signal()
        }
    }

    private func parseDeviceStatus(_ data: Data) -> [String: Any]? {
        guard data.count >= 12,
              data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else {
            return nil
        }
        let payload = data[2 ..< data.count - 2]
        guard payload.count >= 8, payload[payload.startIndex] == 0x00 else { return nil }
        let base = payload.startIndex + 1
        return [
            "battery": Int(payload[base]),
            "signal": Int(Int8(bitPattern: payload[base + 1])),
            "firmwareMain": Int(payload[base + 2]),
            "firmwareSub": Int(payload[base + 3]),
            "workMode": Int(payload[base + 4]),
            "lightMode": Int(payload[base + 5]),
            "switchState": Int(payload[base + 6]),
        ]
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    init?(hexString: String) {
        var bytes: [UInt8] = []
        for part in hexString.split(separator: " ") {
            guard let byte = UInt8(part, radix: 16) else { return nil }
            bytes.append(byte)
        }
        self = Data(bytes)
    }
}

private extension String {
    func sanitizedASCII(maxLength: Int) -> String {
        var result = String()
        result.reserveCapacity(min(maxLength, count))
        for scalar in unicodeScalars where scalar.isASCII {
            guard result.utf8.count < maxLength else { break }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
