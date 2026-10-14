import Foundation

public enum DisplayWire {
    public static let maxFrameBytes = 4 * 1024 * 1024
    /// Convert 4-byte length-prefixed H.264 NALs to a bounded Annex B access unit.
    public static func annexB(_ avcc: [UInt8], parameterSets: [Data] = []) -> Data? {
        guard !avcc.isEmpty, avcc.count <= maxFrameBytes else { return nil }
        var packet = Data()
        for set in parameterSets {
            guard !set.isEmpty, set.count <= maxFrameBytes - packet.count - 4 else { return nil }
            packet.append(contentsOf: [0,0,0,1]); packet.append(set)
        }
        var offset = 0
        while offset + 4 <= avcc.count {
            let n = Int(avcc[offset]) << 24 | Int(avcc[offset+1]) << 16 | Int(avcc[offset+2]) << 8 | Int(avcc[offset+3])
            offset += 4
            guard n > 0, n <= avcc.count-offset, n <= maxFrameBytes-packet.count-4 else { return nil }
            packet.append(contentsOf: [0,0,0,1]); packet.append(contentsOf: avcc[offset..<offset+n]); offset += n
        }
        return offset == avcc.count ? packet : nil
    }
    public static func frame(_ payload: Data, timestamp: UInt64) -> Data? {
        guard payload.count <= maxFrameBytes, timestamp <= UInt64(Int64.max) else { return nil }
        var length = UInt32(payload.count).bigEndian, time = timestamp.bigEndian
        var packet = withUnsafeBytes(of: &length) { Data($0) }
        packet.append(withUnsafeBytes(of: &time) { Data($0) }); packet.append(payload)
        return packet
    }
}
