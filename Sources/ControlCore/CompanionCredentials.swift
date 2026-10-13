import Foundation

public struct CompanionCredentials: Codable, Equatable {
    public let deviceID: String
    public let token: String
    public static func parse(_ output: String) -> Self? {
        let pattern = "^Row: 0 device_id=([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}), token=([a-fA-F0-9]{32})$"
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let id = Range(match.range(at: 1), in: value), let token = Range(match.range(at: 2), in: value) else { return nil }
        return Self(deviceID: String(value[id]).lowercased(), token: String(value[token]).lowercased())
    }
}
