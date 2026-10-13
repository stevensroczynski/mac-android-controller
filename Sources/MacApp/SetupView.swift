import SwiftUI
import AppKit
import ControlCore

struct SetupView: View {
    @ObservedObject var model: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "computermouse.fill").font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("One mouse. Two devices.").font(.title2.bold())
                    Text("USB input sharing · no screen mirroring").foregroundStyle(.secondary)
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
                    HStack {
                        Picker("USB device", selection: $model.selected) {
                            if model.phones.isEmpty { Text("No phone detected").tag("") }
                            ForEach(model.phones) { Text($0.name).tag($0.id) }
                        }.disabled(model.connected || model.busy)
                        Button("Refresh") { model.refresh() }.disabled(model.busy || model.connected)
                    }
                    Toggle("Automatic return with Android edge companion", isOn: $model.requireReturn).disabled(model.connected || model.busy)
                    if model.requireReturn {
                        SecureField("32-character companion code", text: $model.pairingCode).textFieldStyle(.roundedBorder).disabled(model.connected || model.busy)
                        Text("Install the companion, enable its Accessibility service, and authorize USB debugging. The code stays in memory on this Mac.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Manual return mode is incomplete: you must use the release shortcut to return to your Mac.").font(.caption).foregroundStyle(.orange)
                    }
                }.padding(6)
            }
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
            Text("Move inside the Mac screen before crossing. Hold no keys or buttons during handoff. Wi-Fi is not included in this USB preview.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 550)
    }
}
