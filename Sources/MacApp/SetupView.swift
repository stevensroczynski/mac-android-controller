import SwiftUI
import AppKit
import ControlCore

struct SetupView: View {
    @ObservedObject var model: Controller
    var body: some View {
        VStack(spacing: 16) {
            PermissionsPanel(model: model)
            TabView {
            CursorControls(model: model, display: model.extendedDisplay)
                .tabItem { Label("Cursor Only", systemImage: "cursorarrow") }
            ExtendedDisplayControls(model: model, display: model.extendedDisplay)
                .tabItem { Label("Extended Display", systemImage: "display") }
            }
        }.padding(16).frame(width: 620, height: 780)
    }
}

private struct PermissionsPanel: View {
    @ObservedObject var model: Controller
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Permissions", systemImage: "lock.shield").font(.headline)
                    Spacer()
                    Text("\(AppPermission.allCases.filter { model.allowed($0) }.count) of 3 allowed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(AppPermission.allCases, id: \.self) { permission in
                    HStack(spacing: 10) {
                        Image(systemName: model.allowed(permission) ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.allowed(permission) ? Color.green : Color.orange)
                            .font(.title3).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title).font(.callout.weight(.medium))
                            Text(permission.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.allowed(permission) ? "Allowed" : "Needs access")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(model.allowed(permission) ? "Settings…" : "Allow…") {
                            if model.allowed(permission) { model.openPermissionSettings(permission) }
                            else { model.requestPermission(permission) }
                        }.frame(width: 85)
                            .accessibilityLabel("\(model.allowed(permission) ? "Settings for" : "Allow") \(permission.title)")
                    }
                }
                if let message=model.permissionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(8)
        }
    }
}

private struct CursorControls: View {
    @ObservedObject var model: Controller
    @ObservedObject var display: ExtendedDisplay
    @State private var showCode = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "computermouse.fill").font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("One mouse. Two devices.").font(.title2.bold())
                    Text("Control Android with your Mac mouse and keyboard").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.androidActive ? "ANDROID" : "MAC").font(.caption.bold()).padding(8).background(model.androidActive ? Color.green.opacity(0.15) : Color.blue.opacity(0.12)).clipShape(Capsule())
            }
            Text(model.status).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.08)).cornerRadius(9)
            GroupBox("Connect your phone") {
                VStack(alignment: .leading, spacing: 10) {
                    PhoneConnectionControls(model: model, display: display)
                    Toggle("Automatic return with Android edge companion", isOn: $model.requireReturn).disabled(model.connected || model.busy)
                    if model.requireReturn {
                        DisclosureGroup("Companion code · automatic") {
                        HStack {
                            Group {
                                if showCode { TextField("Companion code (automatic)", text: $model.pairingCode) }
                                else { SecureField("Companion code (automatic)", text: $model.pairingCode) }
                            }.textFieldStyle(.roundedBorder).disabled(model.connected || model.busy)
                            Toggle("Show code", isOn: $showCode).toggleStyle(.checkbox)
                        }
                        Text("The updated companion supplies its code over your authorized connection. It is saved in macOS Keychain after connecting. Manual entry is available for older companions.").font(.caption).foregroundStyle(.secondary)
                        Button("Forget saved companion code") { model.forgetPairing() }.disabled(model.connected || model.busy)
                        }
                    } else {
                        Text("Manual return mode is incomplete: you must use the release shortcut to return to your Mac.").font(.caption).foregroundStyle(.orange)
                    }
                }.padding(6)
            }
            GroupBox("Arrange your devices") {
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
            if display.active {
                Text("Extended Display is running. Stop it in its tab to use Cursor Only.").foregroundStyle(.orange)
            }
            HStack {
                Button(model.connected ? "Disconnect" : "Connect") { model.connected ? model.disconnect() : model.connect() }.buttonStyle(.borderedProminent).disabled(display.active || model.busy || (!model.connected && model.selected.isEmpty))
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Back") { model.navigate("BACK") }.disabled(!model.connected || !model.requireReturn)
                Button("Home") { model.navigate("HOME") }.disabled(!model.connected || !model.requireReturn)
                Button("Recents") { model.navigate("RECENTS") }.disabled(!model.connected || !model.requireReturn)
            }
            Text("Move inside the Mac screen before crossing. Hold no keys or buttons during handoff. While on Android, swipe with three fingers for recent apps.").font(.caption).foregroundStyle(.secondary)
        }.padding(16) }
    }
}


private struct PhoneConnectionControls: View {
    @ObservedObject var model: Controller
    @ObservedObject var display: ExtendedDisplay
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Connection", selection: $model.wireless) {
                Text("USB").tag(false)
                Text("Wi-Fi").tag(true)
            }.pickerStyle(.segmented).disabled(model.connected || model.busy || display.active)
            if model.wireless {
                DisclosureGroup("Pair Wi-Fi phone (first time)") {
                    Text("Use the same Wi-Fi network. On Android: Developer options → Wireless debugging → Pair device with pairing code.").font(.caption)
                    TextField("Pairing IP:port", text: $model.wifiPairAddress).textFieldStyle(.roundedBorder)
                    HStack {
                        SecureField("Six-digit Wi-Fi pairing code", text: $model.wifiPairCode).textFieldStyle(.roundedBorder)
                        Button("Pair") { model.pairWireless() }
                    }
                    Text(model.status).font(.caption)
                    Text("Android remembers this pairing. The code is cleared after use.").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.connected || model.busy || display.active)
            }
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Picker("Phone", selection: $model.selected) {
                    if model.phones.isEmpty { Text("No phone detected").tag("") }
                    ForEach(model.phones) { Text($0.name).tag($0.id) }
                }.disabled(model.connected || model.busy || display.active)
                Button("Refresh") { model.refresh() }.disabled(model.busy || model.connected || display.active)
            }

        }
    }
}

private struct ExtendedDisplayControls: View {
    @ObservedObject var model: Controller
    @ObservedObject var display: ExtendedDisplay
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("More room for your Mac", systemImage: "display.2").font(.title2.bold())
                Text("Drag Mac windows onto your phone. Your mouse and keyboard work just like on another monitor.").foregroundStyle(.secondary)
                Text(display.status).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.08)).cornerRadius(9)
                GroupBox("Connect your phone") {
                    PhoneConnectionControls(model: model, display: display).padding(6)
                }
                GroupBox("Screen layout") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Display size", selection: $display.resolution) {
                            Text("Fold 7 unfolded · Portrait").tag("984×1092")
                            Text("Fold 7 unfolded · Landscape").tag("1092×984")
                            Text("Wide screen · 1280 × 800").tag("1280×800")
                            Text("Full HD · 1920 × 1080").tag("1920×1080")
                        }
                        Text("Fold 7 layouts use half the inner screen’s native resolution to reduce delay. Choose portrait or landscape before starting; stop to change layouts.").font(.caption).foregroundStyle(.secondary)
                    }.padding(6).disabled(display.active)
                }
                Label("Prioritize response time · up to 30 fps", systemImage: "bolt.fill").font(.callout)
                if model.connected {
                    Text("Cursor Only is running. Stop it in its tab to start Extended Display.").foregroundStyle(.orange)
                }
                HStack {
                    Button(display.active ? "Stop display" : "Start display") {
                        if display.active { display.stop() }
                        else if let phone = model.phones.first(where: { $0.id == model.selected }) { display.start(phone: phone) }
                    }.buttonStyle(.borderedProminent)
                        .disabled(!display.active && (model.selected.isEmpty || model.connected || model.busy))
                    Button("Arrange displays in macOS…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
                }
                Text("Experimental extended display · USB or paired Wi-Fi").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }
}
