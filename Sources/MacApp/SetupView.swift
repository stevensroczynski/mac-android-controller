import SwiftUI
import AppKit
import ControlCore

struct SetupView: View {
    @ObservedObject var model: Controller
    @State private var showCode = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "computermouse.fill").font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("One mouse. Two devices.").font(.title2.bold())
                    Text("USB or Wi-Fi · input sharing or extended display").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.androidActive ? "ANDROID" : "MAC").font(.caption.bold()).padding(8).background(model.androidActive ? Color.green.opacity(0.15) : Color.blue.opacity(0.12)).clipShape(Capsule())
            }
            Text(model.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.08)).cornerRadius(9)
            GroupBox("1 · Allow input sharing") {
                HStack {
                    Label("Accessibility", systemImage: model.accessibility ? "checkmark.circle.fill" : "circle")
                    Label("Input Monitoring", systemImage: model.inputMonitoring ? "checkmark.circle.fill" : "circle")
                    Spacer(); Button("Grant…") { model.requestPermissions() }
                }.padding(6)
                Button("Open Input Monitoring settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }.buttonStyle(.link)
            }
            GroupBox("2 · Connect your phone") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Connection", selection: $model.wireless) {
                        Text("USB").tag(false)
                        Text("Wi-Fi").tag(true)
                    }.pickerStyle(.segmented).disabled(model.connected || model.busy)
                    if model.wireless {
                        DisclosureGroup("Pair Wi-Fi phone (first time)") {
                            Text("Use the same Wi-Fi network. On Android: Developer options → Wireless debugging → Pair device with pairing code.").font(.caption)
                            TextField("Pairing IP:port", text: $model.wifiPairAddress).textFieldStyle(.roundedBorder)
                            HStack {
                                SecureField("Six-digit Wi-Fi pairing code", text: $model.wifiPairCode).textFieldStyle(.roundedBorder)
                                Button("Pair") { model.pairWireless() }
                            }
                            Text("This six-digit code is separate from the companion code below. Android saves the pairing; the app clears this code after use.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(model.connected || model.busy)
                    }
                    HStack {
                        Picker("Phone", selection: $model.selected) {
                            if model.phones.isEmpty { Text("No phone detected").tag("") }
                            ForEach(model.phones) { Text($0.name).tag($0.id) }
                        }.disabled(model.connected || model.busy)
                        Button("Refresh") { model.refresh() }.disabled(model.busy || model.connected)
                    }
                    Toggle("Automatic return with Android edge companion", isOn: $model.requireReturn).disabled(model.connected || model.busy)
                    if model.requireReturn {
                        HStack {
                            Group {
                                if showCode { TextField("Companion code (automatic)", text: $model.pairingCode) }
                                else { SecureField("Companion code (automatic)", text: $model.pairingCode) }
                            }.textFieldStyle(.roundedBorder).disabled(model.connected || model.busy)
                            Toggle("Show code", isOn: $showCode).toggleStyle(.checkbox)
                        }
                        Text("The updated companion supplies its code over your authorized connection. It is saved in macOS Keychain after connecting. Manual entry is available for older companions.").font(.caption).foregroundStyle(.secondary)
                        Button("Forget saved companion code") { model.forgetPairing() }.disabled(model.connected || model.busy)
                    } else {
                        Text("Manual return mode is incomplete: you must use the release shortcut to return to your Mac.").font(.caption).foregroundStyle(.orange)
                    }
                }.padding(6)
            }
            ExtendedDisplayControls(display: model.extendedDisplay, phone: model.phones.first(where: { $0.id == model.selected }), edge: model.edge, prepare: { model.disconnect() })
            GroupBox("3 · Arrange your devices") {
                VStack(spacing: 10) {
                    HStack {
                        Picker("Phone is", selection: $model.edge) { ForEach(ControlCore.Edge.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        Picker("Mac screen", selection: $model.displayID) {
                            ForEach(NSScreen.screens, id: \.localizedName) { s in
                                Text(s.localizedName).tag((s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? CGMainDisplayID())
                            }
                        }
                    }
                    HStack { Text("Sensitivity").frame(width: 100, alignment: .leading); Slider(value: $model.sensitivity, in: 0.25...3, step: 0.05); Text(String(format: "%.2f×", model.sensitivity)).monospacedDigit() }
                    HStack { Text("Edge region").frame(width: 100, alignment: .leading); Slider(value: $model.region, in: 0.2...1, step: 0.1); Text("\(Int(model.region*100))%").monospacedDigit() }
                    Picker("Release: Control + Option + Command +", selection: $model.escapeKey) { Text("Escape").tag(53); Text("F12").tag(111) }
                }.padding(6)
            }
            HStack {
                Button(model.connected ? "Disconnect" : "Connect") { model.connected ? model.disconnect() : model.connect() }.buttonStyle(.borderedProminent).disabled(model.busy || (!model.connected && model.selected.isEmpty))
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Back") { model.navigate("BACK") }.disabled(!model.connected || !model.requireReturn)
                Button("Home") { model.navigate("HOME") }.disabled(!model.connected || !model.requireReturn)
                Button("Recents") { model.navigate("RECENTS") }.disabled(!model.connected || !model.requireReturn)
            }
            Text("Move inside the Mac screen before crossing. Hold no keys or buttons during handoff. While on Android, swipe with three fingers for recent apps.").font(.caption).foregroundStyle(.secondary)
        }.padding(24) }.frame(width: 550, height: 660)
    }
}


private struct ExtendedDisplayControls: View {
    @ObservedObject var display: ExtendedDisplay
    let phone: Phone?
    let edge: ControlCore.Edge
    let prepare: () -> Void
    var body: some View {
        GroupBox("Use phone as a Mac display · Experimental") {
            VStack(alignment: .leading, spacing: 8) {
                Text(display.status).font(.callout)
                Picker("Resolution", selection: $display.resolution) {
                    Text("1280 × 800").tag("1280×800")
                    Text("1920 × 1080").tag("1920×1080")
                    Text("1080 × 1920 · Portrait").tag("1080×1920")
                }.disabled(display.active)
                HStack {
                    Button(display.active ? "Stop extended display" : "Start extended display") {
                        if display.active { display.stop() }
                        else if let phone=phone { prepare();display.start(phone:phone,edge:edge) }
                    }.disabled(phone == nil && !display.active)
                    Button("Arrange displays…") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
                }
                Text("Moves Mac windows onto your phone. Mouse and keyboard stay with macOS. Stop this mode before using Android input sharing. Screen Recording permission is required.").font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }
}
