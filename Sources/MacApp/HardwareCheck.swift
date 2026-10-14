import Foundation
import CAccessory
import ControlCore

// Explicit opt-in developer test. Run only while the companion's InputTestActivity is foreground.
func hardwareCheck(wireless: Bool = false) -> Int32 {
    let phones = wireless ? Phone.scanWireless() : Phone.scan()
    guard phones.count == 1, let phone = phones.first else { print("Test requires exactly one phone on the selected transport."); return 1 }
    if wireless {
        guard (try? EdgeLink.runADB(["connect", phone.serial])) != nil,
              (try? EdgeLink.runADB(["-s", phone.serial, "get-state"])) == "device" else {
            print("Pair with Wireless debugging first."); return 1
        }
    }
    let bridge = ADBInput()
    guard bridge.start(serial: phone.serial) else { print("ADB UHID initialization failed."); return 1 }
    defer { bridge.stop() }
    func send(_ id: UInt16, _ bytes: [UInt8]) -> Bool { bridge.send(UInt8(id),bytes) }
    defer { _ = send(1,Array(repeating: 0,count: 8)); _ = send(2,Array(repeating: 0,count: 5)) }
    Thread.sleep(forTimeInterval: 1)
    let start = ProcessInfo.processInfo.systemUptime
    var count = 0
    for report: [UInt8] in [[0,32,0,0,0],[0,0,32,0,0],[1,0,0,0,0],[0,0,0,0,0],[0,0,0,1,0],[0,0,0,0,1]] {
        guard send(2,report) else { print("Mouse transfer failed."); return 1 }; count += 1
        Thread.sleep(forTimeInterval: 0.05)
    }
    guard send(1,[0,0,4,0,0,0,0,0]) else { print("Key down failed."); return 1 }
    Thread.sleep(forTimeInterval: 0.05)
    guard send(1,Array(repeating: 0,count: 8)) else { print("Key up failed."); return 1 }
    print("HID registration and \(count+2) input transfers accepted. Test duration: \(Int((ProcessInfo.processInfo.systemUptime-start)*1000)) ms including deliberate pauses. Verify Android test counters separately; this is not an end-to-end latency measurement.")
    return 0
}

// No clicks, keys or pointer motion: compare transport throughput with neutral
// mouse reports on a separate UHID device. This is not end-to-end cursor latency.
func wirelessThroughputCheck() -> Int32 {
    let phones = Phone.scanWireless()
    guard phones.count == 1, let phone = phones.first else { print("Requires one discovered wireless phone."); return 1 }
    let bridge = ADBInput()
    guard bridge.start(serial: phone.serial) else { print("Wireless helper unavailable."); return 1 }
    defer { bridge.stop() }
    let neutral = InputReport(id: 2, bytes: [0,0,0,0,0])
    var start = ProcessInfo.processInfo.systemUptime
    for _ in 0..<64 { guard bridge.send(2, neutral.bytes) else { print("Sequential transfer failed."); return 1 } }
    let sequential = ProcessInfo.processInfo.systemUptime - start
    start = ProcessInfo.processInfo.systemUptime
    for _ in 0..<8 { guard bridge.sendBatch(Array(repeating: neutral, count: 8)) else { print("Batched transfer failed."); return 1 } }
    let batched = ProcessInfo.processInfo.systemUptime - start
    print("64 neutral reports: sequential \(Int(sequential*1000)) ms; batches of eight \(Int(batched*1000)) ms.")
    start = ProcessInfo.processInfo.systemUptime
    var frames = 0
    while ProcessInfo.processInfo.systemUptime - start < 15 {
        guard bridge.sendBatch(Array(repeating: neutral, count: 8)) else { print("Sustained batch transfer failed."); return 1 }
        frames += 8; Thread.sleep(forTimeInterval: 0.008)
    }
    print("15-second wireless batch check passed (\(frames) neutral reports).")
    return 0
}

// Exercises BOTH live channels concurrently without typing, clicking or moving
// the pointer. Run with the controller disconnected and phone unlocked.
func wirelessSessionCheck() -> Int32 {
    let phones = Phone.scanWireless()
    guard phones.count == 1, let phone = phones.first,
          let row = try? EdgeLink.runADB(["-s", phone.serial, "shell", "content", "query", "--uri", "content://org.openinput.uca.pairing/credentials"]),
          let credentials = CompanionCredentials.parse(row) else { print("One authorized companion is required."); return 1 }
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Wireless session diagnostic")
    defer { ProcessInfo.processInfo.endActivity(activity) }
    let transport = USBTransport(), link = EdgeLink()
    var failure: String?, ready = false, readyAt = 0.0
    transport.onFailure = { failure = "Input: " + $0 }
    link.onFailure = { failure = "Companion: " + $0 }
    link.onReady = { ready = true; readyAt = ProcessInfo.processInfo.systemUptime; print("Both channels ready; testing for 70 seconds.") }
    transport.connect(phone) { ok in
        if ok { link.connect(serial: phone.serial, token: credentials.token) }
        else { failure = "Input connection failed" }
    }
    let timer = Timer.scheduledTimer(withTimeInterval: 1.0/120, repeats: true) { _ in
        if ready { transport.send(id: 2, report: [0,0,0,0,0]) }
    }
    let started = ProcessInfo.processInfo.systemUptime
    while failure == nil {
        let now = ProcessInfo.processInfo.systemUptime
        if ready && now - readyAt >= 70 { break }
        if !ready && now - started > 20 { failure = "Connection setup timed out"; break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    timer.invalidate()
    // Read only fixed status fields; never print the credentials response.
    let status = try? EdgeLink.runADB(["-s", phone.serial, "shell", "content", "query", "--uri", "content://org.openinput.uca.pairing/status"])
    let awake = status?.contains("awake=1") == true
    link.stop(); transport.shutdown()
    if let failure = failure { print(failure); if let status = status { print(status) }; return 1 }
    print("70-second concurrent wireless session passed. Screen-awake hold: \(awake).")
    return awake ? 0 : 1
}

// Opt-in: moves the real Android pointer, but sends no clicks or keys.
func alignmentCheck() -> Int32 {
    let phones = Phone.scanWireless()
    guard phones.count == 1, let phone = phones.first,
          let row = try? EdgeLink.runADB(["-s", phone.serial, "shell", "content", "query", "--uri", "content://org.openinput.uca.pairing/credentials"]),
          let credentials = CompanionCredentials.parse(row) else { print("One authorized companion is required."); return 1 }
    let transport = USBTransport(), link = EdgeLink()
    let cases = Edge.allCases.flatMap { edge in [0,5,9].map { (edge,$0) } }
    var index = 0, failure: String?
    let next: () -> Void = {
        if index < cases.count { link.align(cases[index].0, section: cases[index].1) }
    }
    link.onReady = next
    link.onAlignMove = { x,y in for report in HID.mouse(buttons: 0,x: x,y: y) { transport.send(id: 2,report: report) } }
    link.onArmed = {
        let current = index
        print("Aligned edge \(cases[index].0.rawValue), section \(cases[index].1).")
        _ = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            guard failure == nil, index == current else { return }
            let edge = cases[index].0
            let x = edge == .right ? -500 : edge == .left ? 500 : 0
            let y = edge == .bottom ? -500 : edge == .top ? 500 : 0
            for report in HID.mouse(buttons: 0,x: x,y: y) { transport.send(id: 2,report: report) }
        }
    }
    link.onReturn = { section in
        guard let section = section, section == cases[index].1 else { failure = "Return section mismatch or alignment timeout"; return }
        print("Returned through matching section \(section).")
        index += 1; next()
    }
    link.onFailure = { failure = $0 }; transport.onFailure = { failure = $0 }
    transport.connect(phone) { ok in if ok { link.connect(serial: phone.serial, token: credentials.token) } else { failure = "Input unavailable" } }
    let start = ProcessInfo.processInfo.systemUptime
    while index < cases.count && failure == nil && ProcessInfo.processInfo.systemUptime-start < 45 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    link.stop(); transport.shutdown()
    if index == cases.count { print("All 12 physical entry/return section checks passed."); return 0 }
    print(failure ?? "Diagnostic timed out"); return 1
}
