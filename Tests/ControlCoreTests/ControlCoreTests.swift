import Foundation
import CoreGraphics
import ControlCore

final class ControlCoreTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    func testRequiresReadyAndInteriorArming() {
        var h = Handoff()
        checkFalse(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 1, ready: true, buttonsDown: false))
        _ = h.update(point: CGPoint(x: 500,y: 400), delta: .zero, display: screen, now: 2, ready: false, buttonsDown: false)
        checkFalse(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 3, ready: false, buttonsDown: false))
        check(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 4, ready: true, buttonsDown: false))
        checkEqual(h.owner, .android)
    }
    func testAllEdgesAndNegativeDisplayOrigin() {
        let bounds = CGRect(x: -1000,y: -800,width: 1000,height: 800)
        for (edge,p,d) in [(Edge.right,CGPoint(x: -1,y: -400),CGPoint(x: 1,y: 0)),(.left,CGPoint(x: -999,y: -400),CGPoint(x: -1,y: 0)),(.top,CGPoint(x: -500,y: -799),CGPoint(x: 0,y: -1)),(.bottom,CGPoint(x: -500,y: -1),CGPoint(x: 0,y: 1))] {
            var h = Handoff(); h.edge = edge
            _ = h.update(point: CGPoint(x: -500,y: -400), delta: .zero, display: bounds, now: 1, ready: true, buttonsDown: false)
            check(h.update(point: p, delta: d, display: bounds, now: 2, ready: true, buttonsDown: false))
        }
    }
    func testDraggingWrongDirectionAndRegionDoNotCross() {
        var h = Handoff()
        _ = h.update(point: CGPoint(x: 500,y: 400), delta: .zero, display: screen, now: 1, ready: true, buttonsDown: false)
        checkFalse(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 2, ready: true, buttonsDown: true))
        checkFalse(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: -2,y: 0), display: screen, now: 2, ready: true, buttonsDown: false))
        checkFalse(h.update(point: CGPoint(x: 999,y: 1), delta: CGPoint(x: 2,y: 0), display: screen, now: 2, ready: true, buttonsDown: false))
    }
    func testReleaseHysteresisAndNoDuplicateEntry() {
        var h = Handoff()
        _ = h.update(point: CGPoint(x: 500,y: 400), delta: .zero, display: screen, now: 1, ready: true, buttonsDown: false)
        check(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 2, ready: true, buttonsDown: false))
        checkFalse(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 3, ready: true, buttonsDown: false))
        h.release(now: 4); checkEqual(h.owner, .mac)
        _ = h.update(point: CGPoint(x: 500,y: 400), delta: .zero, display: screen, now: 4.1, ready: true, buttonsDown: false)
        checkFalse(h.armed)
        checkFalse(h.update(point: CGPoint(x: 999,y: 400), delta: CGPoint(x: 2,y: 0), display: screen, now: 5, ready: true, buttonsDown: false))
    }
    func testMouseChunkingPreservesMotionAndButtons() {
        let reports = HID.mouse(buttons: 3, x: 1000, y: -500, wheel: 3, pan: -2)
        check(reports.allSatisfy { $0.count == 5 && $0[0] == 3 })
        for (i,expected) in [(1,1000),(2,-500),(3,3),(4,-2)] {
            checkEqual(reports.reduce(0) { $0 + Int(Int8(bitPattern: $1[i])) }, expected)
        }
        checkEqual(HID.mouse(buttons: 0,x: 0,y: 0), [[0,0,0,0,0]])
    }
    func testKeyboardRepeatModifiersReleaseAndRollover() {
        var k = Keyboard(); k.modifiers = 3; k.key(0,down: true); k.key(0,down: true)
        checkEqual(k.report, [3,0,4,0,0,0,0,0])
        k.key(0,down: false); checkEqual(k.report, [3,0,0,0,0,0,0,0])
        for code: UInt16 in [0,1,2,3,4,5,6] { k.key(code,down: true) }
        checkEqual(k.report, [3,0,1,1,1,1,1,1])
        k.release(); checkEqual(k.report, Array(repeating: 0,count: 8))
    }
    func testSpecialKeysAndUnknownKey() {
        var k = Keyboard(); k.key(65535,down: true); checkEqual(k.report, Array(repeating: 0,count: 8))
        checkEqual(HID.keys[117],76); checkEqual(HID.keys[51],42)
        checkEqual(HID.keys[123],80); checkEqual(HID.keys[36],40)
        for edge in Edge.allCases { checkEqual(edge.opposite.opposite,edge) }
        checkEqual(HID.modifiers(macFlags: 0x40),64)
        checkEqual(HID.modifiers(macFlags: 0x60),68)
        checkEqual(HID.modifiers(macFlags: 0x201f),187)
    }
}

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    guard condition() else { fatalError("Check failed at \(file):\(line)") }
}
func checkFalse(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    check(!condition(), file: file, line: line)
}
func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    check(lhs == rhs, file: file, line: line)
}
let suite = ControlCoreTests()
suite.testRequiresReadyAndInteriorArming()
suite.testAllEdgesAndNegativeDisplayOrigin()
suite.testDraggingWrongDirectionAndRegionDoNotCross()
suite.testReleaseHysteresisAndNoDuplicateEntry()
suite.testMouseChunkingPreservesMotionAndButtons()
suite.testKeyboardRepeatModifiersReleaseAndRollover()
suite.testSpecialKeysAndUnknownKey()
print("7 test scenarios passed (\(assertions) assertions).")
