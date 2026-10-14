import AppKit
import SwiftUI
import ControlCore
import CVirtualDisplay

if CommandLine.arguments.contains("--extended-display-check") || CommandLine.arguments.contains("--display-tail-check") {
    let checkTail=CommandLine.arguments.contains("--display-tail-check")
    _ = NSApplication.shared
    let phones = CommandLine.arguments.contains("--usb") ? Phone.scan() : Phone.scanWireless()
    guard phones.count == 1, let phone=phones.first else {print("Select one authorized phone for the test.");exit(1)}
    let display=ExtendedDisplay();display.start(phone:phone)
    let started=ProcessInfo.processInfo.systemUptime
    var testWindow:NSWindow?, updates=0
    let timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { _ in
        guard let id=display.displayID else{return}
        if testWindow==nil {
            let b=CGDisplayBounds(id), main=CGDisplayBounds(CGMainDisplayID())
            let window=NSWindow(contentRect:NSRect(x:b.minX+30,y:main.height-b.minY-330,width:500,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
            let label=NSTextField(labelWithString:"Android extended display\nLive video test")
            label.font=NSFont.systemFont(ofSize:32);label.frame=NSRect(x:30,y:50,width:440,height:180)
            window.contentView?.addSubview(label);window.orderFrontRegardless();testWindow=window
        }
        if checkTail && updates>=20 {return}
        updates+=1
        if checkTail && updates==20,let label=testWindow?.contentView?.subviews.first as? NSTextField {label.stringValue="Final update: Z"}
        testWindow?.backgroundColor=updates % 2 == 0 ? .systemBlue : .systemTeal
    }
    while display.active && ProcessInfo.processInfo.systemUptime-started<25 {
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
    }
    var tailPassed = !checkTail
    if checkTail,let status=try? EdgeLink.runADB(["-s",phone.serial,"shell","content","query","--uri","content://org.openinput.uca.pairing/display_status"]),
       let range=status.range(of:"rendered=[0-9]+",options:.regularExpression),
       let rendered=Int(status[range].dropFirst("rendered=".count)) {
        tailPassed=display.lastContentFrame>0 && rendered>=display.lastContentFrame
        print("Final content frame: \(display.lastContentFrame); decoded frames after idle: \(rendered); tail check: \(tailPassed ? "passed" : "failed").")
    }
    timer.invalidate();testWindow?.close()
    let frames=display.frames, active=display.active
    print("Extended display active: \(active); transmitted frames: \(frames).")
    print(display.status)
    display.stop()
    // Fixed counters only. Do not print the credentials provider response.
    if let status=try? EdgeLink.runADB(["-s",phone.serial,"shell","content","query","--uri","content://org.openinput.uca.pairing/display_status"]) {print(status)}
    RunLoop.current.run(until:Date().addingTimeInterval(0.5))
    exit(active && frames>10 && tailPassed ? 0 : 1)
}

if CommandLine.arguments.contains("--virtual-display-check") {
    _ = NSApplication.shared
    for (width,height) in [(1092,984),(984,1092),(1280,800),(1920,1080),(1968,2184),(2184,1968)] {
        let retina = width * height > 3_000_000
        guard let display = uca_display_create(UInt32(width), UInt32(height), retina ? 1 : 0) else { print("Virtual display unavailable."); exit(1) }
        RunLoop.current.run(until:Date().addingTimeInterval(0.4))
        RunLoop.current.run(until:Date().addingTimeInterval(0.2))
        let id = uca_display_id(display)
        let bounds = CGDisplayBounds(id)
        let ratio = bounds.width / bounds.height
        // These virtual displays can return nil from CGDisplayCopyDisplayMode.
        // Check the effective desktop size instead: Retina must preserve the
        // old preset's logical workspace while capture uses native pixels.
        let retinaMatches = !retina || (bounds.width == Double(width / 2) && bounds.height == Double(height / 2))
        let matches = retinaMatches && abs(ratio - Double(width)/Double(height)) < 0.005 && CGDisplayIsActive(id) != 0
        print("Virtual display \(width)×\(height): \(matches ? "passed" : "failed")")
        uca_display_destroy(display)
        RunLoop.current.run(until:Date().addingTimeInterval(0.5))
        guard matches else {exit(1)}
    }
    print("All virtual displays released.")
    exit(0)
}

if CommandLine.arguments.contains("--keychain-check") {
    // Exercise any legacy ACL on the real cache without printing credentials
    // or changing it. This must return even when its access requires a prompt.
    _ = PairingStore.load()
    print("Existing cache check returned without interaction.")
    let account = "check-" + UUID().uuidString
    let sample = CompanionCredentials.parse("Row: 0 device_id=00000000-0000-4000-8000-000000000001, token=\(String(repeating: "0", count: 32))")!
    let ok = PairingStore.save(sample, account: account) && PairingStore.load(account: account) == sample
    PairingStore.forget(account: account)
    let removed = PairingStore.load(account: account) == nil
    print("Keychain save/read/delete: \(ok && removed ? "passed" : "failed")")
    exit(ok && removed ? 0 : 1)
}

if CommandLine.arguments.contains("--usb-smoke") { exit(hardwareCheck()) }
if CommandLine.arguments.contains("--alignment-check") { exit(alignmentCheck()) }
if CommandLine.arguments.contains("--wireless-session") { exit(wirelessSessionCheck()) }
if CommandLine.arguments.contains("--wireless-throughput") { exit(wirelessThroughputCheck()) }
if CommandLine.arguments.contains("--wireless-smoke") { exit(hardwareCheck(wireless: true)) }

if CommandLine.arguments.contains("--diagnose") {
    print("USB AOA phones: \(Phone.scan().count)")
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Input Monitoring: \(CGPreflightListenEventAccess())")
    print("Screen Recording: \(CGPreflightScreenCaptureAccess())")
    print("ADB installed: \(EdgeLink.adb != nil)")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    var item: NSStatusItem!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(); let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Glide", action: #selector(quit), keyEquivalent: "q").target = self
        applicationItem.submenu = applicationMenu; mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Android control")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Glide…", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "Release to Mac", action: #selector(releaseInput), keyEquivalent: "")
        menu.addItem(withTitle: "Disconnect", action: #selector(disconnect), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        controller.ownershipChanged = { [weak self] active in self?.item.button?.image = NSImage(systemSymbolName: active ? "iphone" : "computermouse", accessibilityDescription: active ? "Android owns input" : "Mac owns input") }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 780), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Glide"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(model: controller)); window.center(); show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(); return true
    }
    @objc func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func releaseInput() { controller.release() }
    @objc func disconnect() { controller.disconnect() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller.shutdown() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
