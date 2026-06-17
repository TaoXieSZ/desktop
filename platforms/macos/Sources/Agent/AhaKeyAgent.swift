@preconcurrency import CoreBluetooth
import Foundation
import os.log

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig.agent", category: "BLE")

/// 设备 8 字节状态解析结果。
///
/// 与 Sources/BLE/AhaKeyProtocol.swift 的 `AhaKeyDeviceStatus` 保持同构；
/// Agent 是独立 target，不共享源码，所以这里内联一份极简解析器。
struct AgentDeviceStatus {
    let battery: Int
    let signal: Int
    let firmwareMain: Int
    let firmwareSub: Int
    let workMode: Int
    let lightMode: Int
    let switchState: Int
}

private struct AgentCommandResponse {
    let cmd: UInt8
    let status: UInt8
    let payload: Data
}

private struct AgentCommandWaiter {
    let id: UUID
    let continuation: CheckedContinuation<AgentCommandResponse, Error>
}

private struct AgentDataWriteWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, Error>
}

private enum AgentOLEDUploadError: Error, LocalizedError {
    case channelNotReady
    case timeout(command: UInt8)
    case deviceRejected(command: UInt8, status: UInt8)

    var errorDescription: String? {
        switch self {
        case .channelNotReady:
            return "OLED 通道未就绪"
        case .timeout(let command):
            return "等待命令 0x\(String(format: "%02X", command)) 超时"
        case .deviceRejected(let command, let status):
            return "命令 0x\(String(format: "%02X", command)) 被设备拒绝 status=0x\(String(format: "%02X", status))"
        }
    }
}

/// 轻量 BLE 守护进程：维持连接 + 接收 Unix socket 命令 → 发送 LED 状态 / 回传拨杆状态
final class AhaKeyAgent: NSObject, @unchecked Sendable, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let bleQueue = DispatchQueue(label: "lab.jawa.ahakeyconfig.agent.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var lastUUID: UUID?
    private let serviceUUID = CBUUID(string: "7340")
    private let dataCharUUID = CBUUID(string: "7341")
    private let commandCharUUID = CBUUID(string: "7343")
    private let notifyCharUUID = CBUUID(string: "7344")
    private let deviceNamePrefix = "vibe code"
    private let socketPath: String

    private let header: [UInt8] = [0xAA, 0xBB]
    private let trailer: [UInt8] = [0xCC, 0xDD]
    private let cmdPrepareWrite: UInt8 = 0x80
    private let cmdWriteResult: UInt8 = 0x81
    private let cmdUpdatePic: UInt8 = 0x82
    private let oledFrameSlotSize = 28_672
    private let oledChunkSize = 4096
    private let oledPacketSize = 180

    // MARK: 缓存（供 hook 查询使用）
    /// 最新 switchState（0=auto, 1=manual），未知时 nil
    private(set) var cachedSwitchState: UInt8?
    /// 最新 lightMode
    private(set) var cachedLightMode: UInt8?
    private(set) var cachedWorkMode: UInt8?

    /// 等待下一次 status 回包的回调队列（用于 querySwitchState）
    private var statusWaiters: [(AgentDeviceStatus?) -> Void] = []
    private var commandWaiters: [UInt8: AgentCommandWaiter] = [:]
    private var dataWriteResultWaiter: AgentDataWriteWaiter?
    private var oledUploadTask: Task<Void, Never>?
    private var oledUploadID: UUID?
    private var isUploadingOLEDStatus = false
    private var pendingOLEDStatus: CodexOLEDStatus?
    private var lastOLEDDisplayKey: String?
    private var lastOLEDUploadAt: Date?
    private let minOLEDUploadInterval: TimeInterval = 2.0
    private let codexHUDModes: [UInt8] = [0, 1, 2]
    /// HUD 帧写入的保留槽（共享帧缓冲尾部）。模式图占 0..~35，HUD 放高位，
    /// 这样推 HUD 不会销毁模式图数据 —— 之后再 updatePicture 指回各自区间即可恢复，无需重传。
    private let oledHUDStartIndex: UInt16 = 73

    var onLog: ((String) -> Void)?

    init(socketPath: String = "/tmp/ahakey.sock") {
        self.socketPath = socketPath
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        bleQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.emit("蓝牙初始状态探针: state=\(self.central.state.rawValue) auth=\(CBManager.authorization.rawValue)")
            if self.central.state == .poweredOn {
                self.connectAutomatically()
            }
        }
    }

    // MARK: - Public

    func sendState(_ state: UInt8) {
        guard let commandChar, let peripheral else {
            emit("LED 状态 \(state): 未连接")
            return
        }
        let data = Data(header + [0x90, state] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: wt)
        emit("→ LED 状态 \(state): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    /// 主动查询一次设备状态，等待下一个 notify 回包 (timeout 秒内)。
    /// 超时时用缓存兜底；仍然没有则返回 nil。完成回调在 main 队列。
    func querySwitchState(timeout: TimeInterval = 1.5,
                          completion: @escaping (AgentDeviceStatus?) -> Void) {
        guard let commandChar, let peripheral else {
            completion(nil)
            return
        }
        // 发设备状态查询命令 AA BB 00 CC DD
        let query = Data(header + [0x00] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(query, for: commandChar, type: wt)

        statusWaiters.append(completion)
        bleQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            // 把目前仍在队列里的 waiter 全部用缓存兜底 fire 掉
            guard !self.statusWaiters.isEmpty else { return }
            let waiters = self.statusWaiters
            self.statusWaiters.removeAll()
            let fallback = self.cachedStatus()
            for w in waiters { w(fallback) }
        }
    }

    private func cachedStatus() -> AgentDeviceStatus? {
        guard let sw = cachedSwitchState else { return nil }
        return AgentDeviceStatus(
            battery: -1, signal: -1, firmwareMain: -1, firmwareSub: -1,
            workMode: Int(cachedWorkMode ?? 0), lightMode: Int(cachedLightMode ?? 0), switchState: Int(sw)
        )
    }

    func startSocketListener() {
        // 清理旧 socket
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { emit("socket() 失败"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let buf = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                strcpy(buf, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { emit("bind() 失败: \(errno)"); close(fd); return }

        listen(fd, 5)
        emit("监听 Unix socket: \(socketPath)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let clientFd = accept(fd, nil, nil)
                guard clientFd >= 0 else { continue }
                self?.handleClient(clientFd)
            }
        }
    }

    // MARK: - Socket handling

    /// 单个客户端的处理：读一包请求，按 JSON 或旧版纯数字分发。
    ///
    /// 协议：
    /// - JSON 一行：`{"cmd":"state","value":3}` / `{"cmd":"permission","value":1}` / `{"cmd":"status"}`
    /// - 纯数字（兼容旧 `ahakey-state.sh`）：`3` → sendState(3)，不回包
    private func handleClient(_ clientFd: Int32) {
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = read(clientFd, &buf, buf.count)
        guard n > 0 else { close(clientFd); return }

        let line = String(bytes: buf[0 ..< Int(n)], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // JSON 请求
        if let lineData = line.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
           let cmd = obj["cmd"] as? String {
            bleQueue.async { [weak self] in
                self?.handleJsonCommand(cmd: cmd, obj: obj, clientFd: clientFd)
            }
            return // fd 在命令 handler 里最终关闭
        }

        // 旧协议：纯数字当作 state，fire-and-forget
        if let state = UInt8(line) {
            bleQueue.async { [weak self] in self?.sendState(state) }
        }
        close(clientFd)
    }

    /// 在主队列执行的 JSON 命令分发。回包由 `replyAndClose` 负责异步写入 + 关 fd。
    private func handleJsonCommand(cmd: String, obj: [String: Any], clientFd: Int32) {
        switch cmd {
        case "state":
            if let v = obj["value"] as? Int {
                sendState(UInt8(clamping: v))
            }
            Self.replyAndClose(clientFd, ["ok": true])

        case "permission":
            // 发 PermissionRequest 对应的 state（默认 1），同时主动查询拨杆
            let stateValue = obj["value"] as? Int ?? 1
            sendState(UInt8(clamping: stateValue))
            querySwitchState(timeout: 1.5) { status in
                let body = Self.statusReply(status, cachedSwitch: self.cachedSwitchState, cachedLight: self.cachedLightMode)
                self.emit("← permission 回包 switchState=\(String(describing: body["switchState"]))")
                if let s = body["switchState"] as? Int, s != 0 {
                    self.emit("（拨杆非 0：PermissionRequest 将交回终端手动确认）")
                } else if body["switchState"] is NSNull {
                    self.emit("（switchState 缺省：批准链可能仍交回手动；请把「蓝牙」交给 Agent 并连上键盘。）")
                }
                Self.replyAndClose(clientFd, body)
            }

        case "status":
            if cachedSwitchState != nil {
                Self.replyAndClose(clientFd, [
                    "switchState": cachedSwitchState.map { Int($0) } ?? NSNull(),
                    "lightMode": cachedLightMode.map { Int($0) } ?? NSNull(),
                ])
            } else {
                querySwitchState(timeout: 1.5) { status in
                    Self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.cachedSwitchState, cachedLight: self.cachedLightMode))
                }
            }

        case "codexOledStatus", "claudeOledStatus":
            // 两条 agent HUD 走同一渲染/上传链；claude 通过 overrideLines 传任意行。
            let result = enqueueCodexOLEDStatus(CodexOLEDStatus.fromSocketObject(obj))
            Self.replyAndClose(clientFd, result)

        default:
            Self.replyAndClose(clientFd, ["error": "unknown cmd: \(cmd)"])
        }
    }

    private func enqueueCodexOLEDStatus(_ status: CodexOLEDStatus) -> [String: Any] {
        guard peripheral != nil, commandChar != nil else {
            emit("OLED 状态跳过：BLE 未连接")
            return ["ok": false, "queued": false, "reason": "ble_not_connected"]
        }
        guard dataChar != nil else {
            emit("OLED 状态跳过：DATA(0x7341) 未就绪")
            return ["ok": false, "queued": false, "reason": "data_char_not_ready"]
        }
        let displayKey = status.displayKey
        if displayKey == lastOLEDDisplayKey, pendingOLEDStatus == nil, !isUploadingOLEDStatus {
            emit("OLED 状态跳过：内容未变化")
            return ["ok": true, "queued": false, "skipped": true, "reason": "unchanged", "displayKey": displayKey]
        }

        pendingOLEDStatus = status
        scheduleOLEDStatusDrain()
        return ["ok": true, "queued": true, "event": status.event ?? NSNull(), "mode": Int(status.mode), "displayKey": displayKey]
    }

    private static func statusReply(_ status: AgentDeviceStatus?,
                                    cachedSwitch: UInt8?,
                                    cachedLight: UInt8?) -> [String: Any] {
        if let s = status {
            return ["switchState": s.switchState, "lightMode": s.lightMode]
        }
        return [
            "switchState": cachedSwitch.map { Int($0) } ?? NSNull(),
            "lightMode": cachedLight.map { Int($0) } ?? NSNull(),
        ]
    }

    private static func replyAndClose(_ fd: Int32, _ dict: [String: Any]) {
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                var out = data
                out.append(0x0A) // \n 作为消息边界
                _ = out.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return write(fd, base, ptr.count)
                }
            }
            close(fd)
        }
    }

    private func scheduleOLEDStatusDrain() {
        guard !isUploadingOLEDStatus else { return }
        let delay: TimeInterval
        if let lastOLEDUploadAt {
            delay = max(0, minOLEDUploadInterval - Date().timeIntervalSince(lastOLEDUploadAt))
        } else {
            delay = 0
        }
        bleQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.drainOLEDStatusQueue()
        }
    }

    private func drainOLEDStatusQueue() {
        guard !isUploadingOLEDStatus, let status = pendingOLEDStatus else { return }
        pendingOLEDStatus = nil
        let displayKey = status.displayKey
        if displayKey == lastOLEDDisplayKey {
            emit("OLED 状态跳过：内容未变化")
            scheduleOLEDStatusDrain()
            return
        }

        isUploadingOLEDStatus = true
        let uploadID = UUID()
        oledUploadID = uploadID
        oledUploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frame = AgentOLEDTextRenderer.render(lines: status.displayLines)
                for mode in self.codexHUDModes {
                    try Task.checkCancellation()
                    try await self.uploadOLEDFrame(frame, mode: mode, startIndex: self.oledHUDStartIndex)
                }
                self.bleQueue.async {
                    guard self.oledUploadID == uploadID else { return }
                    self.oledUploadTask = nil
                    self.oledUploadID = nil
                    self.lastOLEDDisplayKey = displayKey
                    self.lastOLEDUploadAt = Date()
                    self.isUploadingOLEDStatus = false
                    self.emit("OLED Codex 状态已更新: modes=\(self.codexHUDModes.map(String.init).joined(separator: ",")) \(status.displayLines.joined(separator: " | "))")
                    self.scheduleOLEDStatusDrain()
                }
            } catch {
                self.bleQueue.async {
                    guard self.oledUploadID == uploadID else { return }
                    self.oledUploadTask = nil
                    self.oledUploadID = nil
                    self.lastOLEDUploadAt = Date()
                    self.isUploadingOLEDStatus = false
                    self.emit("OLED Codex 状态更新失败: \(error.localizedDescription)")
                    self.scheduleOLEDStatusDrain()
                }
            }
        }
    }

    private func uploadOLEDFrame(_ frame: Data, mode: UInt8, startIndex: UInt16) async throws {
        guard let peripheral, let dataChar, commandChar != nil else {
            throw AgentOLEDUploadError.channelNotReady
        }
        let writeType: CBCharacteristicWriteType =
            dataChar.properties.contains(.write) ? .withResponse : .withoutResponse
        let chunks = stride(from: 0, to: frame.count, by: oledChunkSize).map { offset in
            (offset: offset, data: Data(frame[offset ..< min(offset + oledChunkSize, frame.count)]))
        }

        for chunk in chunks {
            let address = UInt32(startIndex) * UInt32(oledFrameSlotSize) + UInt32(chunk.offset)
            let prepare = makePrepareWrite(chunkLength: chunk.data.count, address: address)
            _ = try await sendCommandAwaitingResponse(prepare, expectedCommand: cmdPrepareWrite)
            try await writeDataChunk(chunk.data, to: peripheral, characteristic: dataChar, type: writeType)
        }

        let update = makeUpdatePicture(mode: mode, startIndex: startIndex, frameCount: 1, timeDelayMs: 1000)
        _ = try await sendCommandAwaitingResponse(update, expectedCommand: cmdUpdatePic)
    }

    private func sendCommandAwaitingResponse(_ data: Data, expectedCommand: UInt8, timeoutSeconds: Double = 5.0) async throws -> AgentCommandResponse {
        let waiterID = UUID()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AgentCommandResponse, Error>) in
                bleQueue.async {
                    self.commandWaiters[expectedCommand] = AgentCommandWaiter(id: waiterID, continuation: continuation)
                    self.writeCommand(data)
                    self.bleQueue.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                        guard let self,
                              self.commandWaiters[expectedCommand]?.id == waiterID else { return }
                        self.commandWaiters.removeValue(forKey: expectedCommand)?.continuation.resume(throwing: AgentOLEDUploadError.timeout(command: expectedCommand))
                    }
                }
            }
        } onCancel: {
            bleQueue.async {
                guard self.commandWaiters[expectedCommand]?.id == waiterID else { return }
                self.commandWaiters.removeValue(forKey: expectedCommand)?.continuation.resume(throwing: CancellationError())
            }
        }
        guard result.status == 0 else {
            throw AgentOLEDUploadError.deviceRejected(command: result.cmd, status: result.status)
        }
        return result
    }

    private func writeCommand(_ data: Data) {
        guard let commandChar, let peripheral else { return }
        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: writeType)
        emit("→ CMD \(data.count)B: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    private func writeDataChunk(_ data: Data, to peripheral: CBPeripheral, characteristic: CBCharacteristic, type: CBCharacteristicWriteType, timeoutSeconds: Double = 5.0) async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                bleQueue.async {
                    self.dataWriteResultWaiter = AgentDataWriteWaiter(id: waiterID, continuation: continuation)
                    let negotiatedLength = max(1, peripheral.maximumWriteValueLength(for: type))
                    let maxPacketLength = min(negotiatedLength, self.oledPacketSize)
                    self.emit("→ DATA \(data.count)B, 分片 \(maxPacketLength)B")
                    self.sendDataPackets(data, waiterID: waiterID, to: peripheral, characteristic: characteristic, type: type, maxPacketLength: maxPacketLength, offset: 0)
                    self.bleQueue.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                        guard let self,
                              self.dataWriteResultWaiter?.id == waiterID else { return }
                        self.dataWriteResultWaiter = nil
                        continuation.resume(throwing: AgentOLEDUploadError.timeout(command: self.cmdWriteResult))
                    }
                }
            }
        } onCancel: {
            bleQueue.async {
                guard self.dataWriteResultWaiter?.id == waiterID else { return }
                let waiter = self.dataWriteResultWaiter
                self.dataWriteResultWaiter = nil
                waiter?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func sendDataPackets(_ data: Data, waiterID: UUID, to peripheral: CBPeripheral, characteristic: CBCharacteristic, type: CBCharacteristicWriteType, maxPacketLength: Int, offset: Int) {
        guard dataWriteResultWaiter?.id == waiterID, offset < data.count else { return }
        let end = min(offset + maxPacketLength, data.count)
        peripheral.writeValue(Data(data[offset ..< end]), for: characteristic, type: type)
        guard end < data.count else { return }
        bleQueue.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            self?.sendDataPackets(data, waiterID: waiterID, to: peripheral, characteristic: characteristic, type: type, maxPacketLength: maxPacketLength, offset: end)
        }
    }

    private func makePrepareWrite(chunkLength: Int, address: UInt32) -> Data {
        let payload: [UInt8] = [
            0x00,
            UInt8(chunkLength & 0xFF),
            UInt8((chunkLength >> 8) & 0xFF),
            UInt8(address & 0xFF),
            UInt8((address >> 8) & 0xFF),
            UInt8((address >> 16) & 0xFF),
            UInt8((address >> 24) & 0xFF),
        ]
        return Data(header + [cmdPrepareWrite] + payload + trailer)
    }

    private func makeUpdatePicture(mode: UInt8, startIndex: UInt16, frameCount: UInt16, timeDelayMs: UInt16) -> Data {
        let payload: [UInt8] = [
            mode,
            UInt8(startIndex & 0xFF),
            UInt8((startIndex >> 8) & 0xFF),
            UInt8(frameCount & 0xFF),
            UInt8((frameCount >> 8) & 0xFF),
            UInt8(timeDelayMs & 0xFF),
            UInt8((timeDelayMs >> 8) & 0xFF),
        ]
        return Data(header + [cmdUpdatePic] + payload + trailer)
    }

    // MARK: - Connection

    private func connectAutomatically() {
        // 1. 用已知 UUID
        if let uuid = lastUUID {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                emit("直连已知设备: \(uuid.uuidString.prefix(8))…")
                peripheral = p
                p.delegate = self
                central.connect(p, options: nil)
                return
            }
        }

        // 2. 系统已连接
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let p = connected.first(where: { ($0.name ?? "").lowercased().hasPrefix(deviceNamePrefix) }) {
            emit("系统已连接: \(p.name ?? "?")")
            peripheral = p
            p.delegate = self
            central.connect(p, options: nil)
            return
        }

        // 3. 扫描
        // 设备广播包只含 1812(HID)/180F(电量)，不含私有服务 7340 —— 按 7340 过滤会永远扫不到。
        // 改为全量扫描，由 didDiscover 的名字前缀("vibe code")筛选。
        emit("开始扫描…")
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func emit(_ msg: String) {
        log.info("\(msg)")
        Self.appendAgentLog(msg)
        onLog?(msg)
    }

    private static func appendAgentLog(_ msg: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("AhaKeyConfig/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        let url = dir.appendingPathComponent("agent.log")
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            emit("蓝牙就绪")
            connectAutomatically()
        } else {
            emit("蓝牙状态: state=\(central.state.rawValue) auth=\(CBManager.authorization.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.lowercased().hasPrefix(deviceNamePrefix) else { return }
        central.stopScan()
        emit("发现: \(name)")
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lastUUID = peripheral.identifier
        emit("已连接: \(peripheral.name ?? "?")")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        dataChar = nil
        commandChar = nil
        notifyChar = nil
        self.peripheral = nil
        cachedSwitchState = nil
        cachedLightMode = nil
        cachedWorkMode = nil
        pendingOLEDStatus = nil
        isUploadingOLEDStatus = false
        oledUploadTask?.cancel()
        oledUploadTask = nil
        oledUploadID = nil
        // 把 pending 的 waiter 全部通知为 nil（避免 hook 客户端一直等）
        if !statusWaiters.isEmpty {
            let waiters = statusWaiters
            statusWaiters.removeAll()
            for w in waiters { w(nil) }
        }
        for waiter in commandWaiters.values {
            waiter.continuation.resume(throwing: AgentOLEDUploadError.channelNotReady)
        }
        commandWaiters.removeAll()
        dataWriteResultWaiter?.continuation.resume(throwing: AgentOLEDUploadError.channelNotReady)
        dataWriteResultWaiter = nil
        emit("已断开，2s 后重连")
        bleQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectAutomatically()
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([dataCharUUID, commandCharUUID, notifyCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == dataCharUUID {
                dataChar = char
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
                emit("数据通道就绪")
            } else if char.uuid == commandCharUUID {
                commandChar = char
                emit("命令通道就绪")
            } else if char.uuid == notifyCharUUID {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
                emit("通知通道已订阅")
            }
        }
        // 两个特征都就绪后发一次初始状态查询
        if commandChar != nil, notifyChar != nil {
            let query = Data(header + [0x00] + trailer)
            let wt: CBCharacteristicWriteType =
                commandChar!.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(query, for: commandChar!, type: wt)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == dataCharUUID || characteristic.uuid == commandCharUUID || characteristic.uuid == notifyCharUUID,
              let data = characteristic.value else { return }
        if let response = Self.parseCommandResponse(data) {
            commandWaiters.removeValue(forKey: response.cmd)?.continuation.resume(returning: response)
            if response.cmd == cmdWriteResult {
                let waiter = dataWriteResultWaiter
                dataWriteResultWaiter = nil
                if response.status == 0 {
                    waiter?.continuation.resume()
                } else {
                    waiter?.continuation.resume(throwing: AgentOLEDUploadError.deviceRejected(command: response.cmd, status: response.status))
                }
            }
            emit("← rsp cmd=0x\(String(format: "%02X", response.cmd)) status=0x\(String(format: "%02X", response.status))")
            return
        }
        guard characteristic.uuid == commandCharUUID || characteristic.uuid == notifyCharUUID else { return }
        guard let status = Self.parseDeviceStatus(data) else { return }

        cachedSwitchState = UInt8(clamping: status.switchState)
        cachedLightMode = UInt8(clamping: status.lightMode)
        cachedWorkMode = UInt8(clamping: status.workMode)
        emit("← status battery=\(status.battery) light=\(status.lightMode) switch=\(status.switchState)")

        guard !statusWaiters.isEmpty else { return }
        let waiters = statusWaiters
        statusWaiters.removeAll()
        for w in waiters { w(status) }
    }

    // MARK: - 协议内联解析

    private static func parseCommandResponse(_ data: Data) -> AgentCommandResponse? {
        guard data.count >= 6,
              data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else {
            return nil
        }
        let cmd = data[2]
        guard cmd != 0x00 else { return nil }
        let status = data[3]
        let payload = data.count > 6 ? Data(data[4 ..< data.count - 2]) : Data()
        return AgentCommandResponse(cmd: cmd, status: status, payload: payload)
    }

    /// 解析 AA BB 00 [battery][signal][fw_main][fw_sub][work][light][switch][reserve] CC DD
    /// 与 Sources/BLE/AhaKeyProtocol.swift:parseDeviceStatus 等价
    private static func parseDeviceStatus(_ data: Data) -> AgentDeviceStatus? {
        guard data.count >= 12,
              data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else {
            return nil
        }
        let payload = data[2 ..< data.count - 2]
        guard payload.count >= 8, payload[payload.startIndex] == 0x00 else { return nil }
        let base = payload.startIndex + 1 // 跳过 cmd echo
        return AgentDeviceStatus(
            battery: Int(payload[base]),
            signal: Int(Int8(bitPattern: payload[base + 1])),
            firmwareMain: Int(payload[base + 2]),
            firmwareSub: Int(payload[base + 3]),
            workMode: Int(payload[base + 4]),
            lightMode: Int(payload[base + 5]),
            switchState: Int(payload[base + 6])
        )
    }
}
