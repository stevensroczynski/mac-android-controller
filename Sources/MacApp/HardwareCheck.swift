import Foundation
import CAccessory
import ControlCore

// Explicit opt-in developer test. Run only while the companion's InputTestActivity is foreground.
func hardwareCheck() -> Int32 {
    let phones = Phone.scan()
    guard phones.count == 1, let phone = phones.first else { print("Test requires exactly one AOA phone."); return 1 }
    let bridge = ADBInput()
    guard bridge.start(serial: phone.serial) else { print("USB ADB UHID initialization failed."); return 1 }
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
