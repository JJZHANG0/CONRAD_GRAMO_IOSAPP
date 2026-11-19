import CoreBluetooth
import Foundation

@MainActor
final class SpoonRadio: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate, LEDTransport {
    private weak var store: AppStore?
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var selectedID: UUID?
    private var syncCharacteristic: CBCharacteristic?
    private var streams: [CBUUID: SpoonFrameBuffer] = [:]
    private var subscribed = Set<CBUUID>()
    private var receivedKnownPacket = false
    private var explicitDisconnect = false
    private var retryCount = 0
    private var timeout: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var waitingSync = false
    private var controlCharacteristic: CBCharacteristic?
    private var nomiInfo: NomiInfo?
    private var helloID: UUID?
    private var handshaken = false
    private var captureID: UUID?
    private var captureTimeout: Task<Void, Never>?
    private var imageAssembler: NomiImageAssembler?
    private var lastCaptureAttempt = Date.distantPast
    private var frameCapturedAt: Date?
    private var nextCapture: Task<Void, Never>?
    private var pendingStill = false
    private var captureIsPreview = false
    private var lastFrameReceivedAt: Date?
    private var cameraMetrics: [[String: Any]] = []
    private var lastCameraDiagnostic = Date.distantPast
    private var session = MealSessionSync()
    private(set) var diagnostics = "尚未发现 GATT"
    var deviceID: String { connected?.identifier.uuidString ?? "unknown" }
    var ready: Bool { handshaken || (receivedKnownPacket && subscribed.contains(SpoonLink.meal)) }
    var canCapture: Bool { handshaken && nomiInfo?.camera == true && subscribed.contains(NomiWire.image) }
    var canControlLED: Bool { handshaken && nomiInfo?.led == true }
    func attach(_ store: AppStore) { self.store = store }
    func start() {
        guard store?.isSimulation != true else { return }
        guard connected == nil else { return }
        explicitDisconnect = false
        retry?.cancel()
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else { apply(central!.state) }
    }
    func connect(id: UUID) {
        guard store?.isSimulation != true else { return }
        guard let central, central.state == .poweredOn, let peripheral = peripherals[id] else { return }
        if let previous = connected, previous.identifier != id { central.cancelPeripheralConnection(previous) }
        central.stopScan(); timeout?.cancel(); retry?.cancel()
        explicitDisconnect = false; selectedID = id; retryCount = 0
        establish(peripheral)
    }
    private func establish(_ peripheral: CBPeripheral) {
        resetNomi()
        connected = peripheral; syncCharacteristic = nil; streams = [:]; subscribed = []; receivedKnownPacket = false
        store?.radioConnecting(name: peripheral.name ?? "")
        peripheral.delegate = self
        central?.connect(peripheral)
        armTimeout("连接或协议数据等待超时；检查样机协议和通知。", seconds: 15)
    }
    func disconnect() {
        explicitDisconnect = true; selectedID = nil; retry?.cancel(); timeout?.cancel()
        central?.stopScan()
        if let connected { central?.cancelPeripheralConnection(connected) }
        clear()
    }
    @discardableResult func writeSync() -> Bool {
        // Existing UUIDs are not hardware-confirmed. Require a recognized read/notify first.
        guard receivedKnownPacket, let connected, connected.state == .connected,
              let syncCharacteristic, syncCharacteristic.properties.contains(.write), !waitingSync else { return false }
        waitingSync = true
        connected.writeValue(SpoonLink.syncRequest(), for: syncCharacteristic, type: .withResponse)
        armTimeout("同步请求超时：未收到可验证的数据回应。", seconds: 8)
        return true
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { if store?.isSimulation != true { apply(central.state) } }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard store?.isSimulation != true, !explicitDisconnect else { return }
        peripherals[peripheral.identifier] = peripheral
        store?.radioDiscovered(id: peripheral.identifier, name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "", rssi: RSSI.intValue,
                               services: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
                               manufacturer: (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.map { String(format: "%02X", $0) }.joined() ?? "",
                               connectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == selectedID else { return }
        peripheral.discoverServices(nil) // read-only inventory, including standard Device Information
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selectedID else { return }
        clear(); store?.radioConnectFailed(name: peripheral.name ?? ""); reconnect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard connected?.identifier == peripheral.identifier else { return }
        clear(); store?.radioDisconnected(); reconnect(peripheral)
    }
    private func reconnect(_ peripheral: CBPeripheral) {
        guard !explicitDisconnect, selectedID == peripheral.identifier, retryCount < 3, central?.state == .poweredOn else { return }
        retryCount += 1
        let delay = retryCount * 2
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.explicitDisconnect else { return }
            self.establish(peripheral)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == connected else { return }
        guard error == nil else { store?.radioNote("发现服务失败", failure: true); return }
        let services = peripheral.services ?? []
        diagnostics = services.map { $0.uuid.uuidString }.joined(separator: "\n")
        store?.gattDiagnostics = diagnostics
        if services.contains(where: { $0.uuid == SpoonLink.service }) {
            store?.radioFoundSpoonService(name: peripheral.name ?? "")
        } else {
            timeout?.cancel()
            store?.radioForeignDevice(name: peripheral.name ?? "")
        }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == connected, error == nil else { return }
        for c in service.characteristics ?? [] {
            diagnostics += "\n\(service.uuid)/\(c.uuid) properties=\(c.properties.rawValue)"
            if service.uuid == SpoonLink.service {
                if c.uuid == NomiWire.control, c.properties.contains(.write), c.properties.contains(.notify) {
                    controlCharacteristic = c; peripheral.setNotifyValue(true, for: c)
                }
                if c.uuid == NomiWire.info, c.properties.contains(.read) { peripheral.readValue(for: c) }
                if c.uuid == NomiWire.image, c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
                if c.uuid == NomiWire.events, c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
                if c.uuid == SpoonLink.sync, c.properties.contains(.write) { syncCharacteristic = c }
                if c.uuid == SpoonLink.status || c.uuid == SpoonLink.meal {
                    if c.properties.contains(.notify) || c.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: c) }
                    if c.properties.contains(.read) { peripheral.readValue(for: c) }
                }
            }
            // Bluetooth SIG Device Information characteristics; never write them.
            if service.uuid == CBUUID(string: "180A"), ["2A29", "2A24", "2A26"].contains(c.uuid.uuidString), c.properties.contains(.read) {
                peripheral.readValue(for: c)
            }
        }
        store?.gattDiagnostics = diagnostics
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == connected else { return }
        if error == nil && characteristic.isNotifying { subscribed.insert(characteristic.uuid) }
        else { subscribed.remove(characteristic.uuid); store?.radioNote("部分通知订阅失败，其他能力可继续使用。") }
        store?.radioReadiness(ready)
        tryHello()
        if canCapture && store?.spoonFrame == nil { store?.cameraMessage = "相机通道已就绪，等待真实画面" }
        if handshaken { syncSession(meal: store?.activeIntegrationMealID) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == connected, error == nil, let data = characteristic.value else { return }
        if characteristic.service?.uuid == SpoonLink.service {
            if characteristic.uuid == NomiWire.info {
                if let info = try? JSONDecoder().decode(NomiInfo.self, from: data), info.supported {
                    nomiInfo = info; store?.nomiCapabilities = info; tryHello()
                } else { store?.radioNote("设备信息版本不匹配，未发送命令。", failure: true) }
                return
            }
            if characteristic.uuid == NomiWire.control { receiveControl(data); return }
            if characteristic.uuid == NomiWire.image { receiveImage(data); return }
            if characteristic.uuid == NomiWire.events {
                guard handshaken, nomiInfo?.button == true, data.count <= 182,
                      let event = try? JSONDecoder().decode(NomiButtonEvent.self, from: data), event.device == nomiInfo?.device,
                      store?.receiveButton(event) == true else { return }
                try? command("ack_event", id: UUID(), extra: ["event": event.event])
                return
            }
        }
        if characteristic.service?.uuid == CBUUID(string: "180A") {
            store?.deviceInformation[characteristic.uuid.uuidString] = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
            return
        }
        guard characteristic.service?.uuid == SpoonLink.service,
              characteristic.uuid == SpoonLink.status || characteristic.uuid == SpoonLink.meal else { return }
        var stream = streams[characteristic.uuid] ?? SpoonFrameBuffer()
        let packets = stream.append(data)
        streams[characteristic.uuid] = stream
        for packet in packets {
            if case .ignored = packet { continue }
            // A packet must arrive on the role documented by v1.
            switch packet {
            case .battery, .head: guard characteristic.uuid == SpoonLink.status else { continue }
            default: guard characteristic.uuid == SpoonLink.meal else { continue }
            }
            receivedKnownPacket = true
            timeout?.cancel(); retryCount = 0
            store?.radioPacket(packet)
            store?.radioReadiness(ready)
            if waitingSync {
                // v1 has no sync command ID or completion marker: don't claim a completed sync.
                waitingSync = false
                store?.radioNote("请求后收到数据；v1 无同步完成回执，完整性待核实。")
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if peripheral == connected, characteristic.uuid == NomiWire.control, error != nil {
            store?.radioNote("设备命令写入失败；未确认实际应用。", failure: true); return
        }
        guard peripheral == connected, characteristic.uuid == SpoonLink.sync else { return }
        if error != nil { waitingSync = false; timeout?.cancel(); store?.radioNote("同步写入失败", failure: true) }
        else { store?.radioNote("同步请求已发送，等待设备数据；写入成功不代表同步完成。") }
    }
    private func armTimeout(_ text: String, seconds: Int) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.waitingSync = false
            self.store?.radioNote(text, failure: true)
            if let peripheral = self.connected, peripheral.state == .connecting { self.central?.cancelPeripheralConnection(peripheral) }
        }
    }
    private func clear() {
        resetNomi()
        connected = nil; syncCharacteristic = nil; streams = [:]; subscribed = []; receivedKnownPacket = false; waitingSync = false; timeout?.cancel()
        store?.radioReadiness(false)
    }
    private func resetNomi() {
        controlCharacteristic = nil; nomiInfo = nil; helloID = nil; handshaken = false
        captureID = nil; imageAssembler = nil; captureTimeout?.cancel()
        nextCapture?.cancel(); nextCapture = nil; pendingStill = false; frameCapturedAt = nil; lastFrameReceivedAt = nil
        session.reset(); store?.buttonSessionReady = false
        store?.nomiCapabilities = nil; store?.cameraBusy = false
        store?.buttonMessage = "实体按钮未连接 / 未同步"
        store?.cameraMessage = "相机连接已中断"
    }
    private func tryHello() {
        guard nomiInfo?.supported == true, subscribed.contains(NomiWire.control), controlCharacteristic != nil, helloID == nil else { return }
        let id = UUID(); helloID = id
        do { try command("hello", id: id) } catch { store?.radioNote("设备握手发送失败", failure: true) }
    }
    private func command(_ op: String, id: UUID, extra: [String: Any] = [:]) throws {
        guard nomiInfo?.supported == true, let connected, connected.state == .connected, let controlCharacteristic else { throw NomiImageError.invalid }
        var value = extra; value["v"] = 1; value["op"] = op; value["id"] = id.uuidString
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= 180, data.count <= connected.maximumWriteValueLength(for: .withResponse) else { throw NomiImageError.invalid }
        connected.writeValue(data, for: controlCharacteristic, type: .withResponse)
    }
    func send(color: GoalColor, commandID: UUID) throws {
        guard canControlLED else { throw NomiImageError.invalid }
        try command("led", id: commandID, extra: ["color": color.rawValue])
    }
    func captureFrame(preview: Bool = false) {
        guard canCapture else { return }
        guard captureID == nil else { if !preview { pendingStill = true }; return }
        nextCapture?.cancel(); nextCapture = nil
        lastCaptureAttempt = Date()
        captureIsPreview = preview && nomiInfo?.fastPreview == true
        frameCapturedAt = lastCaptureAttempt
        let id = UUID(); captureID = id; imageAssembler = nil
        store?.cameraBusy = true; store?.cameraMessage = "正在接收勺载关键帧…"
        do { try command("capture", id: id, extra: captureIsPreview ? ["preview": true] : [:]) }
        catch { finishCapture(error: "拍照命令发送失败"); return }
        captureTimeout?.cancel()
        let deadline = captureIsPreview ? 5 : 30
        captureTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard !Task.isCancelled, self?.captureID == id else { return }
            self?.finishCapture(error: "关键帧接收超时，请重新拍摄；未使用不完整图片。")
        }
    }
    func tick(now: Date, preview: Bool) {
        syncSession(meal: store?.activeIntegrationMealID, now: now)
        if preview && canCapture && captureID == nil && nextCapture == nil && now.timeIntervalSince(lastCaptureAttempt) >= 2 { captureFrame(preview: true) }
    }
    func syncSession(meal: String?, force: Bool = false, now: Date = Date()) {
        guard handshaken, nomiInfo?.button == true, subscribed.contains(NomiWire.events) else { return }
        guard let request = session.next(meal: meal, now: now, force: force) else { return }
        store?.buttonSessionReady = false
        store?.buttonMessage = "正在同步用餐与实体按键状态…"
        do { try command("session", id: request.id, extra: ["meal": request.meal, "unixMs": Int64(now.timeIntervalSince1970*1000)]) }
        catch { store?.buttonMessage = "实体按钮同步失败，正在重试" }
    }
    private func receiveControl(_ data: Data) {
        guard data.count <= 512, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["v"] as? Int == 1, let rawID = value["id"] as? String, let id = UUID(uuidString: rawID),
              let type = value["type"] as? String else { return }
        if type == "hello", id == helloID, value["fw"] as? String == nomiInfo?.fw {
            handshaken = true; timeout?.cancel(); retryCount = 0
            store?.nomiReady(name: nomiInfo?.name ?? "NOMI01")
            if canCapture { store?.cameraMessage = "相机通道已就绪，等待真实画面" }
            syncSession(meal: store?.activeIntegrationMealID)
            store?.recordHardwareEvidence()
        } else if type == "session", let active = value["active"] as? Bool, session.acknowledge(id: id, active: active, now: Date()) {
            store?.buttonSessionReady = session.ready(for: store?.activeIntegrationMealID)
            store?.buttonMessage = value["active"] as? Bool == true ? "实体短按已启用 · 吃完离口后短按一次" : "尚未开始用餐 · 短按不入账"
            store?.recordHardwareEvidence()
        } else if type == "led", value["applied"] as? Bool == true,
                  let raw = value["color"] as? String, let color = GoalColor(rawValue: raw) {
            store?.led.acknowledge(id, applied: color)
            store?.recordHardwareEvidence()
        } else if type == "frame", id == captureID,
                  let frame = value["frame"] as? UInt32, let size = value["size"] as? Int, let crc = value["crc"] as? UInt32 {
            if imageAssembler?.frameID == frame { return }
            do {
                frameCapturedAt = try NomiCameraTiming.capturedAt(requestedAt: lastCaptureAttempt, metadataReceivedAt: Date(), ageMilliseconds: value["age_ms"] as? Double)
                imageAssembler = try NomiImageAssembler(frameID: frame, size: size, crc: crc)
            }
            catch { finishCapture(error: "相机帧头无效") }
        } else if type == "error" {
            let message = "设备回应：\(value["error"] as? String ?? "unknown")"
            if id == captureID { finishCapture(error: message) } else { store?.radioNote(message, failure: true) }
        }
    }
    private func receiveImage(_ data: Data) {
        guard let id = captureID, imageAssembler != nil else { return }
        do {
            if let complete = try imageAssembler?.append(data) {
                let receivedAt = Date()
                let frame = SpoonCameraFrame(id: id, data: complete, timestamp: frameCapturedAt ?? lastCaptureAttempt, deviceID: nomiInfo?.device ?? deviceID)
                let decodeStart = Date()
                let accepted = store?.receiveFrame(frame) == true
                #if DEBUG
                cameraMetrics.append(["firmware": nomiInfo?.fw ?? "", "preview": captureIsPreview, "bytes": complete.count,
                    "requestToReceiveMs": receivedAt.timeIntervalSince(lastCaptureAttempt)*1000,
                    "approximateFrameAgeMs": receivedAt.timeIntervalSince(frame.timestamp)*1000,
                    "frameIntervalMs": lastFrameReceivedAt.map { receivedAt.timeIntervalSince($0)*1000 } ?? 0,
                    "decodeAndStoreMs": Date().timeIntervalSince(decodeStart)*1000, "accepted": accepted, "receivedAt": receivedAt.ISO8601Format()])
                cameraMetrics = Array(cameraMetrics.suffix(30))
                if let data = try? JSONSerialization.data(withJSONObject: cameraMetrics, options: [.prettyPrinted, .sortedKeys]), let root = store?.dataDirectory {
                    try? data.write(to: root.appendingPathComponent("CameraPerformance.json"), options: .atomic)
                }
                #endif
                lastFrameReceivedAt = receivedAt
                finishCapture(error: accepted ? nil : "图片无法解码，请重新拍摄")
            }
        } catch { finishCapture(error: "相机数据校验失败，请重新拍摄。") }
    }
    private func finishCapture(error: String?) {
        captureTimeout?.cancel(); captureID = nil; imageAssembler = nil
        store?.cameraBusy = false; store?.cameraMessage = error ?? "已收到并校验真实勺载相机关键帧"
        if Date().timeIntervalSince(lastCameraDiagnostic) >= 3 {
            lastCameraDiagnostic = Date(); store?.recordHardwareEvidence()
        }
        if nomiInfo?.fastPreview == true || pendingStill {
            nextCapture?.cancel()
            nextCapture = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(error == nil ? 100 : 1000))
                guard let self, !Task.isCancelled else { return }
                self.nextCapture = nil
                guard self.store?.appActive == true, self.canCapture else { return }
                if self.pendingStill { self.pendingStill = false; self.captureFrame() }
                else if self.nomiInfo?.fastPreview == true && (self.store?.previewOwners.isEmpty == false || self.store?.activeIntegrationMealID != nil) { self.captureFrame(preview: true) }
            }
        }
    }
    private func apply(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            guard connected == nil else { return }
            peripherals = [:]; store?.radioScanStarted()
            central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                self.central?.stopScan(); self.store?.radioNote("扫描结束，可重新扫描。")
            }
        case .unauthorized: clear(); store?.radioPermissionDenied()
        case .poweredOff: clear(); store?.radioPoweredOff()
        case .unsupported: clear(); store?.radioUnavailable()
        default: clear()
        }
    }
}
