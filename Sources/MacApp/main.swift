import AppKit
import SwiftUI
import ControlCore

if CommandLine.arguments.contains("--keychain-check") {
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
    print("ADB installed: \(EdgeLink.adb != nil)")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    var item: NSStatusItem!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(); let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit UniversalControlAndroid", action: #selector(quit), keyEquivalent: "q").target = self
        applicationItem.submenu = applicationMenu; mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Android control")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Android Control…", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "Release to Mac", action: #selector(releaseInput), keyEquivalent: "")
        menu.addItem(withTitle: "Disconnect", action: #selector(disconnect), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        controller.ownershipChanged = { [weak self] active in self?.item.button?.image = NSImage(systemSymbolName: active ? "iphone" : "computermouse", accessibilityDescription: active ? "Android owns input" : "Mac owns input") }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 660), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "Universal Control · Android"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(model: controller)); window.center(); show()
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
