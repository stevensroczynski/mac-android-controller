import Foundation
import CoreGraphics

public enum Edge: String, CaseIterable, Codable { case right, left, top, bottom
    public var opposite: Edge { switch self { case .right: return .left; case .left: return .right; case .top: return .bottom; case .bottom: return .top } }
}
public enum Owner: Equatable { case mac, android }
public struct Handoff {
    public private(set) var owner = Owner.mac
    public private(set) var armed = false
    private var releasedAt = -Double.infinity
    public var edge = Edge.right
    public var region = 0.8
    public init() {}
    public mutating func update(point: CGPoint, delta: CGPoint, display: CGRect, now: Double, ready: Bool, buttonsDown: Bool) -> Bool {
        guard owner == .mac else { return false }
        let inset = display.insetBy(dx: 24, dy: 24)
        if inset.contains(point), now - releasedAt >= 0.5 { armed = true }
        guard ready, armed, !buttonsDown, now - releasedAt >= 0.5 else { return false }
        let vertical = edge == .left || edge == .right
        let t = vertical ? (point.y - display.minY) / display.height : (point.x - display.minX) / display.width
        guard t >= (1-region)/2, t <= (1+region)/2 else { return false }
        let crosses: Bool
        switch edge {
        case .right: crosses = point.x >= display.maxX-2 && delta.x > 0
        case .left: crosses = point.x <= display.minX+2 && delta.x < 0
        case .top: crosses = point.y <= display.minY+2 && delta.y < 0
        case .bottom: crosses = point.y >= display.maxY-2 && delta.y > 0
        }
        if crosses { owner = .android; armed = false }
        return crosses
    }
    public mutating func release(now: Double) { owner = .mac; armed = false; releasedAt = now }
}
