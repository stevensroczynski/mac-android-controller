import Foundation
import CoreGraphics
import ControlCore

final class ControlCoreTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    func testEdgeSectionRoundTrips() {
        for bounds in [screen, CGRect(x: -1600,y: -900,width: 1600,height: 900)] {
            for edge in Edge.allCases {
                for section in 0..<10 {
                    let point = EdgeSections.landing(section: section, display: bounds, edge: edge)
                    check(bounds.contains(point))
                    checkEqual(EdgeSections.section(point: point, display: bounds, edge: edge), section)
                }
            }
        }
        checkEqual(EdgeSections.section(point: CGPoint(x: 0,y: -100), display: screen, edge: .right), 0)
        checkEqual(EdgeSections.section(point: CGPoint(x: 0,y: 900), display: screen, edge: .right), 9)
    }
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
    func testSwipeOwnershipAndSingleAction() {
        var g = SwipeCapture()
        checkFalse(g.update(phase: 1, progress: 0, velocity: 0, android: false, ready: true).suppress)
        checkFalse(g.update(phase: 4, progress: 0.5, velocity: 1, android: true, ready: true).recents)
        check(g.update(phase: 1, progress: 0, velocity: 0, android: true, ready: true).suppress)
        for _ in 0..<10 {
            let update = g.update(phase: 2, progress: -0.2, velocity: 0, android: true, ready: true)
            check(update.suppress); checkFalse(update.recents)
        }
        let end = g.update(phase: 4, progress: 0, velocity: 0, android: true, ready: true)
        check(end.suppress); check(end.recents)
        checkFalse(g.update(phase: 4, progress: 0.2, velocity: 1, android: true, ready: true).recents)
        checkFalse(g.inProgress)
    }
    func testSwipeCancellationAndRelease() {
        var g = SwipeCapture()
        for phase: Int64 in [4, 8] {
            _ = g.update(phase: 1, progress: 0, velocity: 0, android: true, ready: true)
            _ = g.update(phase: 2, progress: 0.5, velocity: 0, android: true, ready: true)
            g.cancelAction()
            let end = g.update(phase: phase, progress: 0.5, velocity: 1, android: false, ready: true)
            check(end.suppress); checkFalse(end.recents); checkFalse(g.suppressing)
        }
        _ = g.update(phase: 1, progress: 0, velocity: 0, android: true, ready: true)
        checkFalse(g.update(phase: 8, progress: 0.5, velocity: 1, android: true, ready: true).recents)
        _ = g.update(phase: 1, progress: 0, velocity: 0, android: true, ready: true)
        checkFalse(g.update(phase: 4, progress: 0.001, velocity: 0, android: true, ready: true).recents)
        _ = g.update(phase: 1, progress: 0, velocity: 0, android: true, ready: false)
        checkFalse(g.update(phase: 4, progress: 0.5, velocity: 1, android: true, ready: true).recents)
        _ = g.update(phase: 1, progress: 0, velocity: 0, android: true, ready: true)
        check(g.update(phase: 4, progress: 0, velocity: 1, android: true, ready: true).recents)
    }

    func testWirelessDiscoveryExcludesLegacyAndInvalidTargets() {
        let services = WirelessService.parse("""
        List of discovered mdns services
        legacy _adb._tcp 192.0.2.1:5555
        pairing _adb-tls-pairing._tcp 192.0.2.1:12345
        adb-example _adb-tls-connect._tcp 192.0.2.1:34567
        adb-example _adb-tls-connect._tcp 192.0.2.1:34567
        bad;command _adb-tls-connect._tcp 192.0.2.1:34567
        invalid _adb-tls-connect._tcp 192.0.2.1:0
        """)
        checkEqual(services.count, 1)
        checkEqual(services.first?.target, "adb-example._adb-tls-connect._tcp")
        checkEqual(services.first?.endpoint, "192.0.2.1:34567")
        for invalid in ["", "-s", "example.com:123", "192.0.2.1:65536", "192.0.2.1:0", "256.0.2.1:123", "192.0.2.1:123\nextra"] {
            checkFalse(WirelessService.validEndpoint(invalid))
        }
        check(WirelessService.validEndpoint("192.0.2.1:65535"))
    }

    func testReportBatchingPreservesBoundariesAndMotion() {
        var b = ReportBuffer()
        for _ in 0..<100 { check(b.append(InputReport(id: 2, bytes: [0,1,255,0,0]))) }
        checkEqual(b.count, 1)
        checkEqual(b.take(), [InputReport(id: 2, bytes: [0,100,156,0,0])])
        let sequence = [InputReport(id: 2, bytes: [0,127,0,0,0]),
                        InputReport(id: 2, bytes: [1,0,0,0,0]),
                        InputReport(id: 1, bytes: [0,0,4,0,0,0,0,0]),
                        InputReport(id: 2, bytes: [0,0,0,0,0]),
                        InputReport(id: 1, bytes: [0,0,0,0,0,0,0,0])]
        for report in sequence { check(b.append(report)) }
        checkEqual(b.take(), sequence)
        for _ in 0..<2 { check(b.append(InputReport(id: 2, bytes: [0,127,0,0,0]))) }
        checkEqual(b.take().count, 2)
        for _ in 0..<192 { check(b.append(InputReport(id: 1, bytes: Array(repeating: 0, count: 8)))) }
        checkFalse(b.append(InputReport(id: 1, bytes: Array(repeating: 0, count: 8))))
        checkEqual(b.take().count, 64); checkEqual(b.count, 128)
        b.clear(); check(b.take().isEmpty)
    }

    func testCompanionCredentialsRequireExactProviderResponse() {
        let row = "Row: 0 device_id=00000000-0000-4000-8000-000000000001, token=\(String(repeating: "0", count: 32))"
        check(CompanionCredentials.parse(row) != nil)
        checkEqual(CompanionCredentials.parse(row)?.deviceID, "00000000-0000-4000-8000-000000000001")
        checkEqual(CompanionCredentials.parse(row)?.token, String(repeating: "0", count: 32))
        for invalid in ["", "Permission denial", row + "\nRow: 1 token=bad", row.replacingOccurrences(of: "device_id=", with: "device_id=bad"), row.replacingOccurrences(of: "token=", with: "token=bad")] {
            check(CompanionCredentials.parse(invalid) == nil)
        }
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
suite.testSwipeOwnershipAndSingleAction()
suite.testSwipeCancellationAndRelease()
suite.testWirelessDiscoveryExcludesLegacyAndInvalidTargets()
suite.testReportBatchingPreservesBoundariesAndMotion()
suite.testCompanionCredentialsRequireExactProviderResponse()
suite.testEdgeSectionRoundTrips()
print("13 test scenarios passed (\(assertions) assertions).")
