import Foundation
import CAccessory
import ControlCore

struct Phone: Identifiable {
    let bus: UInt8, address: UInt8, name: String, serial: String
    var wireless = false
    var id: String { wireless ? serial : "\(bus):\(address)" }
    static func scanWireless() -> [Phone] {
        guard let output = try? EdgeLink.runADB(["mdns", "services"]) else { return [] }
        return WirelessService.parse(output).map {
            Phone(bus: 0, address: 0, name: "Wi-Fi · " + $0.endpoint, serial: $0.target, wireless: true)
        }
    }
    static func scan() -> [Phone] {
        var entries = [UCDevice](repeating: UCDevice(), count: 32)
        let count = uc_list(&entries, 32)
        return entries.prefix(max(0, Int(count))).map { entry in
            var e = entry
            let name = withUnsafePointer(to: &e.name) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
            let serial = withUnsafePointer(to: &e.serial) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
            return Phone(bus: e.bus, address: e.address, name: name, serial: serial)
        }
    }
}

final class USBTransport {
    private let queue = DispatchQueue(label: "usb.reports", qos: .userInteractive)
    private let lock = NSLock()
    private var pending = 0
    private var generation = 0
    private var handle: OpaquePointer?
    private var bridge: ADBInput?
    private var active: Bool { handle != nil || bridge != nil }
    private var timer: DispatchSourceTimer?
    var onFailure: (() -> Void)?
    // Count and duration only; never retain report contents in diagnostics.
    private(set) var reportsSent = 0
    private(set) var maxTransferMS = 0.0

    func connect(_ phone: Phone, completion: @escaping (Bool) -> Void) {
        queue.async {
            self.closeOnQueue()
            if phone.wireless {
                // Resolve the TLS service by name; never open legacy adb tcpip.
                guard Phone.scanWireless().contains(where: { $0.serial == phone.serial }),
                      (try? EdgeLink.runADB(["connect", phone.serial])) != nil,
                      (try? EdgeLink.runADB(["-s", phone.serial, "get-state"])) == "device" else {
                    DispatchQueue.main.async { completion(false) }; return
                }
            } else {
                self.handle = phone.serial.withCString { uc_open(phone.bus, phone.address, $0) }
            }
            if let h = self.handle,
                  HID.keyboardDescriptor.withUnsafeBufferPointer({ uc_register(h, 1, $0.baseAddress, UInt16($0.count)) }) == 0,
                  HID.mouseDescriptor.withUnsafeBufferPointer({ uc_register(h, 2, $0.baseAddress, UInt16($0.count)) }) == 0 {
                // AOA path available.
            } else {
                self.closeOnQueue()
                let bridge = ADBInput()
                guard bridge.start(serial: phone.serial) else { DispatchQueue.main.async { completion(false) }; return }
                self.bridge = bridge
            }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now()+1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                let alive = self.bridge.map { $0.send(0) } ?? (uc_alive(self.handle) != 0)
                if !alive { self.failOnQueue() }
            }
            self.timer = timer; timer.resume()
            DispatchQueue.main.async { completion(true) }
        }
    }
    func send(id: UInt16, report: [UInt8]) {
        lock.lock()
        guard pending < 96 else { lock.unlock(); queue.async { self.failOnQueue() }; return }
        pending += 1; let token = generation; lock.unlock()
        queue.async {
            defer { self.lock.lock(); self.pending -= 1; self.lock.unlock() }
            self.lock.lock(); let valid = token == self.generation; self.lock.unlock()
            guard valid, self.active else { return }
            let start = ProcessInfo.processInfo.systemUptime
            let ok = self.bridge.map { $0.send(UInt8(id), report) ? 0 : -1 } ?? report.withUnsafeBufferPointer { Int(uc_send(self.handle, id, $0.baseAddress, UInt16($0.count))) }
            if ok != 0 { self.failOnQueue(); return }
            self.reportsSent += 1
            self.maxTransferMS = max(self.maxTransferMS, (ProcessInfo.processInfo.systemUptime-start)*1000)
        }
    }
    func release() {
        lock.lock(); generation += 1; lock.unlock()
        queue.async {
            guard self.active else { return }
            if let bridge = self.bridge { if !bridge.send(3) { self.failOnQueue() }; return }
            let keyboard = [UInt8](repeating: 0, count: 8), mouse = [UInt8](repeating: 0, count: 5)
            let k = keyboard.withUnsafeBufferPointer { uc_send(self.handle, 1, $0.baseAddress, 8) }
            let m = mouse.withUnsafeBufferPointer { uc_send(self.handle, 2, $0.baseAddress, 5) }
            if k != 0 || m != 0 { self.failOnQueue() }
        }
    }
    func disconnect() { release(); queue.async { self.closeOnQueue() } }
    func shutdown() { release(); queue.sync { self.closeOnQueue() } }
    private func closeOnQueue() { timer?.cancel(); timer = nil; uc_close(handle); handle = nil; bridge?.stop(); bridge = nil }
    private func failOnQueue() {
        guard active else { return }
        lock.lock(); generation += 1; lock.unlock()
        closeOnQueue(); DispatchQueue.main.async { self.onFailure?() }
    }
}
