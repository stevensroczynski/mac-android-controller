/// A bounded mailbox. Adjacent mouse reports may combine only when their button
/// state matches and every signed HID axis still fits. Key/button boundaries
/// retain their order. Nothing is silently dropped on overload.
public struct InputReport: Equatable {
    public let id: UInt16
    public let bytes: [UInt8]
    public init(id: UInt16, bytes: [UInt8]) { self.id = id; self.bytes = bytes }
}
public struct ReportBuffer {
    private var reports: [InputReport] = []
    public var count: Int { reports.count }
    public init() {}
    public mutating func append(_ report: InputReport) -> Bool {
        if report.id == 2, report.bytes.count == 5,
           let last = reports.last, last.id == 2, last.bytes.count == 5,
           last.bytes[0] == report.bytes[0] {
            let axes = (1...4).map { Int(Int8(bitPattern: last.bytes[$0])) + Int(Int8(bitPattern: report.bytes[$0])) }
            if axes.allSatisfy({ (-127...127).contains($0) }) {
                reports[reports.count-1] = InputReport(id: 2, bytes: [report.bytes[0]] + axes.map { UInt8(bitPattern: Int8($0)) })
                return true
            }
        }
        guard reports.count < 192 else { return false }
        reports.append(report); return true
    }
    public mutating func take() -> [InputReport] {
        let batch = Array(reports.prefix(64)); reports.removeFirst(batch.count); return batch
    }
    public mutating func clear() { reports.removeAll(keepingCapacity: true) }
}
