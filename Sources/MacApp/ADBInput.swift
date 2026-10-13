import Foundation
import Darwin
import ControlCore

final class ADBInput {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var serial = ""
    private var remote = ""
    static var helper: URL? {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("uca-hid.jar"), URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/uca-hid.jar")]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    func start(serial: String) -> Bool {
        guard let adb = EdgeLink.adb, let helper = Self.helper, !serial.isEmpty else { return false }
        self.serial = serial; remote = "/data/local/tmp/uca-\(UUID().uuidString.lowercased()).jar"
        do {
            _ = try EdgeLink.runADB(["-s",serial,"push",helper.path,remote])
            _ = try EdgeLink.runADB(["-s",serial,"shell","chmod","600",remote])
            let p = Process(), incoming = Pipe(), outgoing = Pipe()
            p.executableURL = URL(fileURLWithPath: adb)
            p.arguments = ["-s",serial,"shell","-T","env","CLASSPATH=\(remote)","app_process","/","org.openinput.bridge.HIDBridge"]
            p.standardInput = incoming; p.standardOutput = outgoing; p.standardError = FileHandle.nullDevice
            try p.run(); process = p; input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
            var hello: [UInt8] = [85,67,65,49]
            for d in [HID.keyboardDescriptor,HID.mouseDescriptor] { hello += [UInt8(d.count >> 8),UInt8(d.count & 255)] + d }
            try input?.write(contentsOf: Data(hello))
            guard read(4, timeout: 3000) == Data([85,67,65,49]) else { stop(); return false }
            return true
        } catch { stop(); return false }
    }
    func send(_ id: UInt8, _ bytes: [UInt8] = []) -> Bool {
        guard let p = process, p.isRunning else { return false }
        do { try input?.write(contentsOf: Data([id]+bytes)) } catch { return false }
        return read(1, timeout: 500) == Data([0])
    }
    private func read(_ count: Int, timeout: Int32) -> Data? {
        guard let output = output else { return nil }
        var result = Data()
        let deadline = ProcessInfo.processInfo.systemUptime + Double(timeout)/1000
        while result.count < count {
            let remaining = Int32(max(0,(deadline-ProcessInfo.processInfo.systemUptime)*1000))
            if remaining == 0 { return nil }
            var fd = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&fd,1,remaining)>0, fd.revents & Int16(POLLIN) != 0 else { return nil }
            let data = output.readData(ofLength: count-result.count)
            guard !data.isEmpty else { return nil }; result.append(data)
        }
        return result
    }
    func stop() {
        try? input?.close(); input = nil
        if let p = process, p.isRunning { p.terminate() }
        try? output?.close(); output = nil; process = nil
        if !remote.isEmpty { _ = try? EdgeLink.runADB(["-s",serial,"shell","rm","-f",remote]); remote = "" }
    }
    deinit { stop() }
}
