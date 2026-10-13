import Foundation

// Standard USB HID boot keyboard and five-button relative mouse descriptors.
public enum HID {
    public static func modifiers(macFlags: UInt64) -> UInt8 {
        // Device-dependent NX flags preserve right Option / AltGr and independent sides.
        let mapping: [(UInt64, UInt8)] = [(1,1),(2,2),(0x20,4),(8,8),(0x2000,16),(4,32),(0x40,64),(0x10,128)]
        return mapping.reduce(0) { $0 | ((macFlags & $1.0) != 0 ? $1.1 : 0) }
    }
    public static let keyboardDescriptor: [UInt8] = [
        0x05,1,0x09,6,0xa1,1,0x05,7,0x19,0xe0,0x29,0xe7,0x15,0,0x25,1,
        0x75,1,0x95,8,0x81,2,0x95,1,0x75,8,0x81,1,
        0x95,6,0x75,8,0x15,0,0x25,0x65,0x05,7,0x19,0,0x29,0x65,0x81,0,0xc0]
    public static let mouseDescriptor: [UInt8] = [
        0x05,1,0x09,2,0xa1,1,0x09,1,0xa1,0,0x05,9,0x19,1,0x29,5,
        0x15,0,0x25,1,0x95,5,0x75,1,0x81,2,0x95,1,0x75,3,0x81,1,
        0x05,1,0x09,0x30,0x09,0x31,0x09,0x38,0x15,0x81,0x25,0x7f,
        0x75,8,0x95,3,0x81,6,0x05,0x0c,0x0a,0x38,2,0x15,0x81,0x25,0x7f,
        0x75,8,0x95,1,0x81,6,0xc0,0xc0]
    public static func mouse(buttons: UInt8, x: Int, y: Int, wheel: Int = 0, pan: Int = 0) -> [[UInt8]] {
        var values = [x,y,wheel,pan].map { max(-8192, min(8192, $0)) }; var reports: [[UInt8]] = []
        repeat {
            let chunk = values.map { max(-127,min(127,$0)) }
            reports.append([buttons & 31] + chunk.map { UInt8(bitPattern: Int8($0)) })
            for i in 0..<4 { values[i] -= chunk[i] }
        } while values.contains(where: { $0 != 0 })
        return reports
    }
    // macOS physical virtual key codes → USB usage IDs. Android selects the layout.
    public static let keys: [UInt16: UInt8] = [
        0:4,1:22,2:7,3:9,4:11,5:10,6:29,7:27,8:6,9:25,10:100,11:5,
        12:20,13:26,14:8,15:21,16:28,17:23,18:30,19:31,20:32,21:33,22:35,23:34,
        24:46,25:38,26:36,27:45,28:37,29:39,30:48,31:18,32:24,33:47,34:12,35:19,
        36:40,37:15,38:13,39:52,40:14,41:51,42:49,43:54,44:56,45:17,46:16,47:55,
        48:43,49:44,50:53,51:42,53:41,57:57,65:99,67:85,69:87,71:83,75:84,76:88,
        78:86,81:103,82:98,83:89,84:90,85:91,86:92,87:93,88:94,89:95,91:96,92:97,
        96:62,97:63,98:64,99:60,100:65,101:66,103:68,105:70,106:107,107:71,
        109:67,111:69,113:72,114:73,115:74,116:75,117:76,118:61,119:77,120:59,
        121:78,122:58,123:80,124:79,125:81,126:82]
}
public struct Keyboard {
    private var held = Set<UInt8>()
    public var modifiers: UInt8 = 0
    public init() {}
    public mutating func key(_ code: UInt16, down: Bool) {
        guard let usage = HID.keys[code] else { return }
        if down { held.insert(usage) } else { held.remove(usage) }
    }
    public var report: [UInt8] {
        let keys = held.count > 6 ? Array(repeating: UInt8(1), count: 6) : held.sorted()
        return [modifiers, 0] + keys + Array(repeating: 0, count: 6-keys.count)
    }
    public mutating func release() { held.removeAll(); modifiers = 0 }
}
