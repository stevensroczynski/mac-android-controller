/// Tracks one system swipe without sending Recents for every update (which would
/// toggle Android's overview repeatedly). A swipe belongs to the device on which
/// it began; releasing to Mac cancels its action but drains the intercepted tail.
public struct SwipeCapture {
    public private(set) var inProgress = false
    public private(set) var suppressing = false
    private var eligible = false
    private var moved = false
    public init() {}

    public mutating func cancelAction() { eligible = false }
    public mutating func reset() { self = Self() }

    public mutating func update(phase: Int64, progress: Double, velocity: Double,
                                android: Bool, ready: Bool) -> (suppress: Bool, recents: Bool) {
        if phase == 1 {
            inProgress = true; suppressing = android
            eligible = android && ready; moved = false
        }
        let suppress = inProgress ? suppressing : android
        if !android || !ready { eligible = false }
        if inProgress && progress.isFinite && abs(progress) >= 0.03 { moved = true }
        if phase == 8 { reset(); return (suppress, false) }
        if phase == 4 {
            let recents = inProgress && eligible && (moved || (velocity.isFinite && abs(velocity) > 0.01))
            reset(); return (suppress, recents)
        }
        return (suppress, false)
    }
}
