import Foundation
import Network
import ControlCore

// ADB is used only for edge notifications and navigation, never input injection.
final class EdgeLink {
    private let queue = DispatchQueue(label: "edge.link")
    private var connection: NWConnection?
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var lastReply = 0.0
    private var port: String?
    private var serial = ""
    private var generation = UUID()
    var onReady: (() -> Void)?
    var onReturn: (() -> Void)?
    var onFailure: (() -> Void)?
    var onArmed: (() -> Void)?
    static var adb: String? {
        ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func runADB(_ args: [String]) throws -> String {
        guard let adb = adb else { throw NSError(domain: "ADB unavailable", code: 1) }
        let p = Process(), output = Pipe()
        p.executableURL = URL(fileURLWithPath: adb); p.arguments = args
        p.standardOutput = output; p.standardError = FileHandle.nullDevice
        try p.run()
        let deadline = Date().addingTimeInterval(5)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning { p.terminate(); throw NSError(domain: "ADB timeout", code: 2) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else { throw NSError(domain: "ADB failed", code: 3) }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func connect(serial: String, token: String) {
        queue.async {
            self.stopOnQueue(); self.serial = serial
            guard !serial.isEmpty, token.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else { self.fail(); return }
            do {
                // Select the same physical USB device. No network ADB fallback.
                let p = try Self.runADB(["-s", serial, "forward", "tcp:0", "localabstract:uca-edge-v1"])
                guard let value = UInt16(p), value > 0 else { self.fail(); return }
                self.port = p
                let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: value)!, using: .tcp)
                self.connection = c
                let generation = self.generation
                c.stateUpdateHandler = { [weak self] state in
                    guard let self = self, self.generation == generation else { return }
                    switch state {
                    case .ready: self.write("AUTH \(token.lowercased())"); self.read(generation)
                    case .failed: self.fail()
                    default: break
                    }
                }
                self.lastReply = ProcessInfo.processInfo.systemUptime
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now()+1, repeating: 1)
                timer.setEventHandler { [weak self] in
                    guard let self = self else { return }
                    if ProcessInfo.processInfo.systemUptime - self.lastReply > 3 { self.fail() }
                    else { self.write("PING") }
                }
                self.timer = timer; timer.resume(); c.start(queue: self.queue)
            } catch { self.fail() }
        }
    }
    func arm(_ edge: Edge) { queue.async { self.write("ARM \(edge.opposite.rawValue.uppercased())") } }
    func disarm() { queue.async { self.write("DISARM") } }
    func navigation(_ action: String) { guard ["BACK","HOME","RECENTS"].contains(action) else { return }; queue.async { self.write(action) } }
    func stop() { queue.async { self.stopOnQueue() } }
    private func write(_ line: String) {
        connection?.send(content: Data((line+"\n").utf8), completion: .contentProcessed({ _ in }))
    }
    private func read(_ generation: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, done, error in
            guard let self = self, self.generation == generation else { return }
            if let data = data { self.buffer.append(data) }
            guard self.buffer.count <= 1024 else { self.fail(); return }
            while let end = self.buffer.firstIndex(of: 10) {
                let line = String(decoding: self.buffer[..<end], as: UTF8.self)
                self.buffer.removeSubrange(...end)
                self.lastReply = ProcessInfo.processInfo.systemUptime
                switch line {
                case "OK": DispatchQueue.main.async { self.onReady?() }
                case "RETURN": DispatchQueue.main.async { self.onReturn?() }
                case "ARMED": DispatchQueue.main.async { self.onArmed?() }
                case "PONG": break
                default: self.fail(); return
                }
            }
            if done || error != nil { self.fail() } else { self.read(generation) }
        }
    }
    private func fail() { stopOnQueue(); DispatchQueue.main.async { self.onFailure?() } }
    private func stopOnQueue() {
        generation = UUID(); timer?.cancel(); timer = nil
        connection?.cancel(); connection = nil; buffer.removeAll()
        if let p = port { _ = try? Self.runADB(["-s",serial,"forward","--remove","tcp:\(p)"]) }
        port = nil
    }
}
