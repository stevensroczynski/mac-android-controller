import CoreGraphics

/// Isolates undocumented WindowServer gesture routing from the public HID path.
/// Event types/fields are described by https://github.com/joshuarli/iss .
/// No private framework is loaded and no system preferences are changed.
/// These values require physical regression testing after macOS upgrades.
enum TrackpadGestures {
    static let mask: CGEventMask = (1 << 29) | (1 << 30)
    static func isGesture(_ type: CGEventType) -> Bool { type.rawValue == 29 || type.rawValue == 30 }
    static func integer(_ event: CGEvent, _ field: UInt32) -> Int64 {
        event.getIntegerValueField(CGEventField(rawValue: field)!)
    }
    static func number(_ event: CGEvent, _ field: UInt32) -> Double {
        event.getDoubleValueField(CGEventField(rawValue: field)!)
    }
    static func isDockSwipe(_ type: CGEventType, _ event: CGEvent) -> Bool {
        type.rawValue == 30 && integer(event, 110) == 23
    }
}
