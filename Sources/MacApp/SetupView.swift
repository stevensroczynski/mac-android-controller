import SwiftUI
import AppKit
import ControlCore

private enum GlideTheme {
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.78)
    static let border = Color.primary.opacity(0.07)
}

struct SetupView: View {
    @ObservedObject var model: Controller
    var previewTab: Int? = nil
    var body: some View { GlideWindow(model: model, display: model.extendedDisplay, previewTab: previewTab) }
}

private struct GlideWindow: View {
    @ObservedObject var model: Controller
    @ObservedObject var display: ExtendedDisplay
    var previewTab: Int? = nil
    private var activeTab: Int {previewTab ?? selectedTab}
    @AppStorage("glideSelectedTab") private var selectedTab = 1
    private var connected: Bool { model.connected || display.active }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glide").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Your Mac and Android, together.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(display.paused ? Color.orange : (connected ? Color.green : Color.secondary)).frame(width: 6, height: 6)
                    Text(display.paused ? "Picture paused" : (connected ? "Connected" : "Not connected")).font(.caption.weight(.medium))
                }.padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.045), in: Capsule())
            }.padding(.horizontal, 26).padding(.top, 18).padding(.bottom, 22)
            HStack(spacing: 6) {
                modeTab(0, title: "Cursor Only", subtitle: "Mouse & keyboard", icon: "cursorarrow")
                modeTab(1, title: "Extended Display", subtitle: "Mac windows on your phone", icon: "display.2")
            }.padding(5).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 26).padding(.bottom, 8)
            Group {
                if activeTab == 0 { CursorControls(model: model, display: display) }
                else { ExtendedDisplayControls(model: model, display: display) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.5)
            PermissionsPanel(model: model).padding(.horizontal, 26).padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(GlideTheme.accent)
        .groupBoxStyle(GlideCardStyle())
        .frame(minWidth: 660, idealWidth: 720, minHeight: 700, idealHeight: 840)
    }
    private func modeTab(_ value: Int, title: String, subtitle: String, icon: String) -> some View {
        Button { selectedTab=value } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium)).frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).opacity(0.7)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 15).padding(.vertical, 13)
                .foregroundStyle(activeTab == value ? Color.white : Color.primary)
                .background(activeTab == value ? GlideTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityValue(activeTab == value ? "Selected" : "Not selected")
    }
}

private struct GlideCardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(GlideTheme.border, lineWidth: 1))
    }
}

private struct StatusBanner: View {
    let title: String, detail: String, icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(GlideTheme.accent).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(GlideTheme.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PermissionsPanel: View {
    @ObservedObject var model: Controller
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Permissions", systemImage: "lock.shield").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(AppPermission.allCases.allSatisfy {model.allowed($0)} ? "All set" : "\(AppPermission.allCases.filter {model.allowed($0)}.count) of 3 allowed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(AppPermission.allCases, id: \.self) { permission in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Image(systemName: model.allowed(permission) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(model.allowed(permission) ? Color.green : Color.orange)
                            Text(permission.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        }
                        Button {
                            if model.allowed(permission) {model.openPermissionSettings(permission)}
                            else {model.requestPermission(permission)}
                        } label: {
                            HStack {
                                Text(model.allowed(permission) ? "Allowed" : "Allow access")
                                Spacer()
                                Image(systemName: model.allowed(permission) ? "arrow.up.right" : "arrow.right")
                            }.font(.system(size: 11, weight: .medium))
                        }.buttonStyle(.plain).foregroundStyle(model.allowed(permission) ? Color.secondary : GlideTheme.accent)
                            .accessibilityLabel("\(model.allowed(permission) ? "Settings for" : "Allow") \(permission.title)")
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(GlideTheme.border, lineWidth: 1))
                        .help(permission.detail)
                }
            }
            if let message=model.permissionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
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
                    Text("Cursor Only").font(.title2.weight(.semibold))
                    Text("Control Android with your Mac mouse and keyboard").foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.androidActive ? "ANDROID" : "MAC").font(.caption.bold()).padding(8).background(model.androidActive ? Color.green.opacity(0.15) : Color.blue.opacity(0.12)).clipShape(Capsule())
            }
            StatusBanner(title: model.connected ? "Ready to move between devices" : "Connect your phone", detail: model.status, icon: model.connected ? "checkmark.circle" : "iphone")
            HStack {
                Button(model.connected ? "Disconnect" : "Connect") { model.connected ? model.disconnect() : model.connect() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(display.active || model.busy || (!model.connected && model.selected.isEmpty))
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Back") { model.navigate("BACK") }.disabled(!model.connected || !model.requireReturn)
                Button("Home") { model.navigate("HOME") }.disabled(!model.connected || !model.requireReturn)
                Button("Recents") { model.navigate("RECENTS") }.disabled(!model.connected || !model.requireReturn)
            }
            GroupBox("Connect your phone") {
                VStack(alignment: .leading, spacing: 10) {
                    PhoneConnectionControls(model: model, display: display)
                    Toggle("Return to Mac at the screen edge", isOn: $model.requireReturn).disabled(model.connected || model.busy)
                    if model.requireReturn {
                        DisclosureGroup("Manual pairing code") {
                        HStack {
                            Group {
                                if showCode { TextField("Companion code (automatic)", text: $model.pairingCode) }
                                else { SecureField("Companion code (automatic)", text: $model.pairingCode) }
                            }.textFieldStyle(.roundedBorder).disabled(model.connected || model.busy)
                            Toggle("Show code", isOn: $showCode).toggleStyle(.checkbox)
                        }
                        Text("The updated companion supplies its code over your authorized connection. It is cached in macOS Keychain when access is already allowed; Glide never asks for your Keychain password. Manual entry is available for older companions.").font(.caption).foregroundStyle(.secondary)
                        Button("Forget saved companion code") { model.forgetPairing() }.disabled(model.connected || model.busy)
                        }
                    } else {
                        Text("Manual return mode is incomplete: you must use the release shortcut to return to your Mac.").font(.caption).foregroundStyle(.orange)
                    }
                }
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
                    HStack { Text("Sensitivity").frame(width: 100, alignment: .leading); Slider(value: Binding(get: {model.sensitivity}, set: {model.sensitivity=($0*20).rounded()/20}), in: 0.25...3); Text(String(format: "%.2f×", model.sensitivity)).monospacedDigit() }
                    HStack { Text("Edge region").frame(width: 100, alignment: .leading); Slider(value: $model.region, in: 0.2...1, step: 0.1); Text("\(Int(model.region*100))%").monospacedDigit() }
                    Picker("Release: Control + Option + Command +", selection: $model.escapeKey) { Text("Escape").tag(53); Text("F12").tag(111) }
                }
            }
            if display.active {
                Text("Extended Display is running. Stop it in its tab to use Cursor Only.").foregroundStyle(.orange)
            }
            Text("Move inside the Mac screen before crossing. Hold no keys or buttons during handoff. While on Android, swipe with three fingers for recent apps.").font(.caption).foregroundStyle(.secondary)
        }.padding(26) }
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
                Text("Extended Display").font(.title2.weight(.semibold))
                Text("A second screen for your Mac, right on your phone.").foregroundStyle(.secondary)
                StatusBanner(title: display.paused ? "Your desktop is waiting" : (display.active ? "Your phone is a Mac display" : "Make room for your work"), detail: display.status, icon: display.paused ? "pause.circle" : "display.2")
                HStack {
                    Button(display.active ? "Stop display" : "Start display") {
                        if display.active { display.stop() }
                        else if let phone = model.phones.first(where: { $0.id == model.selected }) { display.start(phone: phone) }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!display.active && (model.selected.isEmpty || model.connected || model.busy))
                    Button("Arrange displays in macOS…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!) }
                }
                GroupBox("Connect your phone") {
                    PhoneConnectionControls(model: model, display: display)
                }
                GroupBox("Screen layout") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Display size", selection: $display.resolution) {
                            Text("Fold 7 · Larger text · Portrait").tag("1476×1638")
                            Text("Fold 7 · Larger text · Landscape").tag("1638×1476")
                            Text("Fold 7 · More space · Portrait").tag("1968×2184")
                            Text("Fold 7 · More space · Landscape").tag("2184×1968")
                            Text("Fold 7 · Fast · Portrait").tag("984×1092")
                            Text("Fold 7 · Fast · Landscape").tag("1092×984")
                            Text("Wide screen · 1280 × 800").tag("1280×800")
                            Text("Full HD · 1920 × 1080").tag("1920×1080")
                        }
                        Text("Larger text keeps a smaller workspace with Retina detail. More space fits more content with smaller text. Your last layout is remembered. Stop the display to change layouts.").font(.caption).foregroundStyle(.secondary)
                    }.disabled(display.active)
                }
                Label("Low latency · USB or Wi-Fi", systemImage: "bolt.fill").font(.caption).foregroundStyle(.secondary)
                if model.connected {
                    Text("Cursor Only is running. Stop it in its tab to start Extended Display.").foregroundStyle(.orange)
                }
                Text("Switch apps on your phone freely. Reopen the viewer to resume your Mac screen.").font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }
    }
}
