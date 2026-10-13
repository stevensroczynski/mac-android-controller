import Foundation

/// Only modern, encrypted Wireless Debugging advertisements are eligible.
public struct WirelessService: Equatable {
    public let target: String
    public let endpoint: String
    public static func parse(_ output: String) -> [Self] {
        var seen = Set<String>()
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count == 3, fields[1].trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "_adb-tls-connect._tcp",
                  fields[0].range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
                  validEndpoint(fields[2]) else { return nil }
            let target = fields[0] + "._adb-tls-connect._tcp"
            guard seen.insert(target).inserted else { return nil }
            return Self(target: target, endpoint: fields[2])
        }
    }
    public static func validEndpoint(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = UInt16(parts[1]), port > 0 else { return false }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && UInt8($0) != nil }
    }
}
