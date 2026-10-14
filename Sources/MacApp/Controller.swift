import AppKit
import SwiftUI
import ControlCore

final class Controller: ObservableObject {
    @Published var phones: [Phone] = []
    @Published var selected = ""
    @Published var wireless = false { didSet { defaults.set(wireless, forKey: "wireless"); selected = ""; refresh() } }
    @Published var wifiPairAddress = ""
    @Published var wifiPairCode = ""
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
    let extendedDisplay = ExtendedDisplay()
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
    private var discoveryTimer: Timer?
    private var credentials: CompanionCredentials?
    private var observers: [NSObjectProtocol] = []
    private var attempt = UUID()
    private var sessionActivity: NSObjectProtocol?

    init() {
        wireless = defaults.bool(forKey: "wireless")
        pairingCode = PairingStore.load()?.token ?? ""
        edge = ControlCore.Edge(rawValue: defaults.string(forKey: "edge") ?? "right") ?? .right
        sensitivity = defaults.object(forKey: "sensitivity") as? Double ?? 1
        region = defaults.object(forKey: "region") as? Double ?? 0.8
        escapeKey = defaults.object(forKey: "escapeKey") as? Int ?? 53
        transport.onFailure = { [weak self] reason in self?.disconnect(message: "Input disconnected: \(reason). Mac control restored.") }
        link.onReady = { [weak self] in guard let self = self, self.connected else { return }; self.edgeReady = true; self.status = "Ready. Move through the selected display edge."
            if let credentials = self.credentials, !PairingStore.save(credentials) {
                self.status = "Ready. Keychain save failed; the code will be fetched again next time."
            } }
        link.onReturn = { [weak self] section in
            guard let self = self, self.androidActive else { return }
            if let section = section {
                self.returnPoint = EdgeSections.landing(section: section, display: CGDisplayBounds(self.displayID), edge: self.edge)
            }
            self.release()
        }
        link.onAlignMove = { [weak self] x, y in
            guard let self = self, self.androidActive, !self.inputReady else { return }
            self.mouse(x: x, y: y)
        }
        link.onArmed = { [weak self] in
            guard let self = self, self.androidActive else { return }
            self.inputReady = true

        }
        link.onFailure = { [weak self] reason in
            guard let self = self, self.connected else { return }
            self.edgeReady = false; self.release()
            if self.requireReturn { self.disconnect(message: "Companion disconnected: \(reason). Unlock the phone before reconnecting.") }
            else { self.status = "Input ready. Manual return mode: use the emergency shortcut." }
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
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, self.wireless, !self.connected, !self.busy else { return }
            self.refresh(automatic: true)
        }
        refresh()
    }
    func refresh(automatic: Bool = false) {
        guard !busy, !connected else { return }; busy = true
        let useWireless = wireless
        DispatchQueue.global(qos: .userInitiated).async {
            let phones = useWireless ? Phone.scanWireless() : Phone.scan()
            DispatchQueue.main.async {
                self.phones = phones; self.busy = false
                if !phones.contains(where: { $0.id == self.selected }) { self.selected = phones.first?.id ?? "" }
                if !automatic { self.status = phones.isEmpty ? (useWireless ? "No wireless phone found. Enable Wireless debugging on the same Wi-Fi, then refresh." : "No AOA 2.0 phone found. Unlock the phone and check the data cable.") : "Select your phone and connect." }
            }
        }
    }
    func pairWireless() {
        guard !busy, !connected else { return }
        let address = wifiPairAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = wifiPairCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WirelessService.validEndpoint(address), code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
            status = "Enter the pairing IP:port and six-digit code shown on your phone."; return
        }
        busy = true; status = "Pairing with Android Wireless debugging…"; wifiPairCode = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = try? EdgeLink.runADB(["pair", address], input: code + "\n", timeout: 15)
            let ok = result?.contains("Successfully paired") == true
            let phones = ok ? Phone.scanWireless() : []
            DispatchQueue.main.async {
                self.busy = false
                if ok {
                    self.phones = phones
                    let host = address.split(separator: ":")[0]
                    self.selected = phones.first(where: { $0.name.contains("\(host):") })?.id ?? ""
                    self.status = "Paired. Select your Wi-Fi phone and Connect. The companion code is retrieved automatically."
                } else { self.status = "Pairing failed. Keep the pairing screen open and use its current IP:port and code." }
            }
        }
    }
    func forgetPairing() {
        guard !connected, !busy else { return }
        PairingStore.forget(); pairingCode = ""; credentials = nil
        status = "Cached code removed. Connect retrieves it again from the authorized phone."
    }
    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options); _ = CGRequestListenEventAccess()
    }
    func connect() {
        guard !extendedDisplay.active else { status = "Stop extended display before switching to Android input sharing."; return }
        guard !connected, !busy, let phone = phones.first(where: { $0.id == selected }) else { return }
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else { status = "Grant Accessibility and Input Monitoring, then restart this app."; requestPermissions(); return }
        guard installTap() else { status = "Could not capture input. Check permissions and restart."; return }
        sessionActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Sharing keyboard and mouse with Android")
        busy = true; status = wireless ? "Opening wireless input devices…" : "Opening USB input devices…"; let id = UUID(); attempt = id
        transport.connect(phone) { [weak self] ok in
            guard let self = self, self.attempt == id else { return }
            guard ok else { self.disconnect(message: "Could not open Android input. For Wi-Fi, pair first and check Wireless debugging. Close other control tools and retry."); return }
            self.status = "Getting companion credentials…"
            let manualCode = self.pairingCode
            let needsCompanion = self.requireReturn
            DispatchQueue.global(qos: .userInitiated).async {
                let output = needsCompanion ? (try? EdgeLink.runADB(["-s", phone.serial, "shell", "content", "query", "--uri", "content://org.openinput.uca.pairing/credentials"])) : nil
                let credentials = output.flatMap(CompanionCredentials.parse)
                DispatchQueue.main.async {
                    guard self.attempt == id else { return }
                    self.busy = false; self.credentials = credentials
                    if let credentials = credentials { self.pairingCode = credentials.token }
                    else { self.pairingCode = manualCode }
                    guard !needsCompanion || self.pairingCode.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else {
                        self.disconnect(message: "Update the Android companion for automatic setup, or enter its manual code."); return
                    }
                    self.connected = true; self.status = needsCompanion ? "Connecting the edge companion…" : "Input ready. Manual return mode: use the emergency shortcut."
                    if needsCompanion { self.link.connect(serial: phone.serial, token: self.pairingCode) }
                }
            }
        }
    }
    func disconnect(message: String = "Disconnected. Mac owns input.") {
        extendedDisplay.stop()
        attempt = UUID(); release(); connected = false; busy = false; edgeReady = false
        link.stop(); transport.disconnect(); removeTap(); status = message
        if let activity = sessionActivity { ProcessInfo.processInfo.endActivity(activity); sessionActivity = nil }
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
                if requireReturn { link.align(edge, section: EdgeSections.section(point: event.location, display: bounds, edge: edge)) }
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
