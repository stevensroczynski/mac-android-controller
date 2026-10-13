import AppKit
import SwiftUI
import ControlCore

final class Controller: ObservableObject {
    @Published var phones: [Phone] = []
    @Published var selected = ""
    @Published var status = "Connect your Android phone by USB, then refresh."
    @Published var connected = false
    @Published var busy = false
    @Published var androidActive = false
    @Published var edge: ControlCore.Edge = .right { didSet { defaults.set(edge.rawValue, forKey: "edge"); release() } }
    @Published var sensitivity = 1.0 { didSet { defaults.set(sensitivity, forKey: "sensitivity") } }
    @Published var region = 0.8 { didSet { defaults.set(region, forKey: "region") } }
    @Published var escapeKey = 53 { didSet { defaults.set(escapeKey, forKey: "escapeKey") } }
    @Published var pairingCode = ""
    @Published var requireReturn = true
    @Published var displayID = CGMainDisplayID()
    @Published var accessibility = AXIsProcessTrusted()
    @Published var inputMonitoring = CGPreflightListenEventAccess()
    var ownershipChanged: ((Bool) -> Void)?
    private let defaults = UserDefaults.standard
    private let transport = USBTransport()
    private let link = EdgeLink()
    private var handoff = Handoff()
    private var keyboard = Keyboard()
    private var swipe = SwipeCapture()
    private var macKeys = Set<UInt16>()
    private var buttons: UInt8 = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var edgeReady = false
    private var inputReady = false
    private var hidden = false
    private var returnPoint = CGPoint.zero
    private var fractionalX = 0.0, fractionalY = 0.0, wheelRemainder = 0.0, panRemainder = 0.0
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var attempt = UUID()

    init() {
        edge = ControlCore.Edge(rawValue: defaults.string(forKey: "edge") ?? "right") ?? .right
        sensitivity = defaults.object(forKey: "sensitivity") as? Double ?? 1
        region = defaults.object(forKey: "region") as? Double ?? 0.8
        escapeKey = defaults.object(forKey: "escapeKey") as? Int ?? 53
        transport.onFailure = { [weak self] in self?.disconnect(message: "USB interrupted. Mac control restored. Reconnect to continue.") }
        link.onReady = { [weak self] in guard let self = self, self.connected else { return }; self.edgeReady = true; self.status = "Ready. Move through the selected display edge." }
        link.onReturn = { [weak self] in self?.release() }
        link.onArmed = { [weak self] in
            guard let self = self, self.androidActive else { return }
            self.inputReady = true
            // Nudge away from the phone's return strip; do not pretend to know its coordinates.
            let x = self.edge == .right ? 24 : self.edge == .left ? -24 : 0
            let y = self.edge == .bottom ? 24 : self.edge == .top ? -24 : 0
            self.mouse(x: x, y: y)
        }
        link.onFailure = { [weak self] in
            guard let self = self, self.connected else { return }
            self.edgeReady = false; self.release()
            if self.requireReturn { self.disconnect(message: "Edge companion unavailable. Check USB debugging, Accessibility, and the pairing code.") }
            else { self.status = "USB ready. Manual return mode: use the emergency shortcut." }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.disconnect(message: "Sharing stopped for sleep or session change.") })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.release() })
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.accessibility = AXIsProcessTrusted(); self.inputMonitoring = CGPreflightListenEventAccess()
            if self.connected && (!self.accessibility || !self.inputMonitoring) { self.disconnect(message: "Permission changed. Mac control restored.") }
        }
        refresh()
    }
    func refresh() {
        guard !busy, !connected else { return }; busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let phones = Phone.scan()
            DispatchQueue.main.async {
                self.phones = phones; self.busy = false
                if !phones.contains(where: { $0.id == self.selected }) { self.selected = phones.first?.id ?? "" }
                self.status = phones.isEmpty ? "No AOA 2.0 phone found. Unlock the phone and check the data cable." : "Select your phone and connect."
            }
        }
    }
    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options); _ = CGRequestListenEventAccess()
    }
    func connect() {
        guard !connected, !busy, let phone = phones.first(where: { $0.id == selected }) else { return }
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else { status = "Grant Accessibility and Input Monitoring, then restart this app."; requestPermissions(); return }
        guard !requireReturn || pairingCode.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else { status = "Enter the 32-character code from the Android edge companion."; return }
        guard installTap() else { status = "Could not capture input. Check permissions and restart."; return }
        busy = true; status = "Opening USB input devices…"; let id = UUID(); attempt = id
        transport.connect(phone) { [weak self] ok in
            guard let self = self, self.attempt == id else { return }
            self.busy = false
            guard ok else { self.disconnect(message: "Could not register Android HID devices. Close other USB control tools and retry."); return }
            self.connected = true; self.status = self.requireReturn ? "Connecting the edge companion…" : "USB ready. Manual return mode: use the emergency shortcut."
            if self.requireReturn { self.link.connect(serial: phone.serial, token: self.pairingCode) }
        }
    }
    func disconnect(message: String = "Disconnected. Mac owns input.") {
        attempt = UUID(); release(); connected = false; busy = false; edgeReady = false
        link.stop(); transport.disconnect(); removeTap(); status = message
    }
    func release() {
        let wasActive = androidActive
        handoff.release(now: ProcessInfo.processInfo.systemUptime)
        androidActive = false; inputReady = false; keyboard.release(); buttons = 0
        swipe.cancelAction()
        fractionalX = 0; fractionalY = 0; wheelRemainder = 0; panRemainder = 0
        if wasActive { transport.release(); link.disarm(); CGWarpMouseCursorPosition(returnPoint) }
        if hidden { CGDisplayShowCursor(CGMainDisplayID()); hidden = false }
        ownershipChanged?(false)
    }
    func shutdown() { disconnect(); transport.shutdown() }
    func navigate(_ action: String) { link.navigation(action) }

    private func installTap() -> Bool {
        removeTap()
        let types: [CGEventType] = [.mouseMoved,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.scrollWheel,.keyDown,.keyUp,.flagsChanged]
        let mask = types.reduce(TrackpadGestures.mask) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<Controller>.fromOpaque(info).takeUnretainedValue()
            return controller.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true); return true
    }
    private func removeTap() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; macKeys.removeAll(); swipe.reset()
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            release(); if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false
        }
        if TrackpadGestures.isGesture(type) {
            if TrackpadGestures.isDockSwipe(type, event) {
                let result = swipe.update(
                    phase: TrackpadGestures.integer(event, 132),
                    progress: TrackpadGestures.number(event, 124),
                    velocity: max(abs(TrackpadGestures.number(event, 129)), abs(TrackpadGestures.number(event, 130))),
                    android: androidActive, ready: inputReady && edgeReady)
                if result.recents { link.navigation("RECENTS") }
                return result.suppress
            }
            // Suppress companion markers and other system gestures while captured.
            return androidActive || swipe.suppressing
        }
        let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown && key == escapeKey && event.flags.contains([.maskControl,.maskAlternate,.maskCommand]) {
            release(); return true
        }
        if !androidActive {
            if type == .keyDown { macKeys.insert(key) }; if type == .keyUp { macKeys.remove(key) }
            guard type == .mouseMoved else { return false }
            let bounds = CGDisplayBounds(displayID)
            let delta = CGPoint(x: event.getDoubleValueField(.mouseEventDeltaX), y: event.getDoubleValueField(.mouseEventDeltaY))
            handoff.edge = edge; handoff.region = region
            // Do not take a seam shared with another Mac display.
            var probe = event.location
            switch edge { case .right: probe.x += 4; case .left: probe.x -= 4; case .top: probe.y -= 4; case .bottom: probe.y += 4 }
            let neighbor = NSScreen.screens.contains { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32, id != displayID else { return false }
                return CGDisplayBounds(id).contains(probe)
            }
            let modifiers = event.flags.intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand])
            let ready = connected && (!requireReturn || edgeReady) && !neighbor && !swipe.inProgress && macKeys.isEmpty && modifiers.isEmpty
            if handoff.update(point: event.location, delta: delta, display: bounds, now: ProcessInfo.processInfo.systemUptime, ready: ready, buttonsDown: NSEvent.pressedMouseButtons != 0) {
                returnPoint = CGPoint(x: min(bounds.maxX-32,max(bounds.minX+32,event.location.x)), y: min(bounds.maxY-32,max(bounds.minY+32,event.location.y)))
                androidActive = true; inputReady = !requireReturn
                CGDisplayHideCursor(CGMainDisplayID()); hidden = true
                CGWarpMouseCursorPosition(returnPoint); ownershipChanged?(true)
                if requireReturn { link.arm(edge) }
                return true
            }
            return false
        }
        guard inputReady else { return true }
        switch type {
        case .mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged:
            fractionalX += event.getDoubleValueField(.mouseEventDeltaX)*sensitivity
            fractionalY += event.getDoubleValueField(.mouseEventDeltaY)*sensitivity
            let x = Int(fractionalX), y = Int(fractionalY); fractionalX -= Double(x); fractionalY -= Double(y)
            mouse(x: x, y: y); CGWarpMouseCursorPosition(returnPoint)
        case .leftMouseDown,.rightMouseDown,.otherMouseDown,.leftMouseUp,.rightMouseUp,.otherMouseUp:
            let button = min(4, max(0, Int(event.getIntegerValueField(.mouseEventButtonNumber))))
            let bit: UInt8 = 1 << button
            if [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type) { buttons |= bit } else { buttons &= ~bit }
            mouse(x: 0, y: 0)
        case .scrollWheel:
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            wheelRemainder += event.getDoubleValueField(continuous ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1)/(continuous ? 12 : 1)
            panRemainder += event.getDoubleValueField(continuous ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2)/(continuous ? 12 : 1)
            let w = Int(wheelRemainder), p = Int(panRemainder); wheelRemainder -= Double(w); panRemainder -= Double(p)
            for r in HID.mouse(buttons: buttons, x: 0, y: 0, wheel: w, pan: p) { transport.send(id: 2, report: r) }
        case .keyDown,.keyUp:
            // Android generates repeat from held HID state; do not release/repress.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                keyboard.key(key, down: type == .keyDown); transport.send(id: 1, report: keyboard.report)
            }
        case .flagsChanged:
            keyboard.modifiers = HID.modifiers(macFlags: event.flags.rawValue)
            if key == 57 { keyboard.key(57, down: true); transport.send(id: 1, report: keyboard.report); keyboard.key(57, down: false) }
            transport.send(id: 1, report: keyboard.report)
        default: break
        }
        return true
    }
    private func mouse(x: Int, y: Int) { for r in HID.mouse(buttons: buttons, x: x, y: y) { transport.send(id: 2, report: r) } }
}
