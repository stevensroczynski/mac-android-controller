import AppKit
import ScreenCaptureKit
import CVirtualDisplay
import ControlCore

final class ExtendedDisplay: ObservableObject {
    @Published private(set) var active=false
    @Published private(set) var status="Use your phone as another Mac screen."
    @Published private(set) var frames=0
    private(set) var lastContentFrame=0
    @Published var resolution="984×1092"
    var displayID: CGDirectDisplayID? { virtual.map { uca_display_id($0) } }
    private var virtual: UnsafeMutableRawPointer?
    private var stream: DisplayStream?
    private var port: String?
    private var serial=""
    private var generation=UUID()
    private var activity: NSObjectProtocol?
    private var startup: Task<Void,Never>?
    static func adb(_ args: [String]) async throws -> String {
        try await Task.detached(priority:.userInitiated) {try EdgeLink.runADB(args,timeout:8)}.value
    }
    func start(phone: Phone) {
        guard !active else{return}
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            status="Allow Screen Recording for this app in macOS settings, then quit and reopen it."
            return
        }
        active=true;frames=0;lastContentFrame=0;status="Preparing your extended display…"
        let id=UUID();generation=id;serial=phone.serial
        let dimensions=resolution.split(separator:"×").compactMap {Int($0)}
        guard dimensions.count==2 else {stop(message:"Choose a display resolution.");return}
        let width=dimensions[0],height=dimensions[1]
        activity=ProcessInfo.processInfo.beginActivity(options:[.userInitiated,.latencyCritical],reason:"Android extended display")
        startup=Task { @MainActor [weak self] in
            guard let self=self else{return}
            do {
                if phone.wireless {_ = try await Self.adb(["connect",phone.serial])}
                guard self.generation==id else{return}
                let row=try await Self.adb(["-s",phone.serial,"shell","content","query","--uri","content://org.openinput.uca.pairing/credentials"])
                guard self.generation==id else{return}
                guard let credentials=CompanionCredentials.parse(row) else {throw DisplayError.message("Update the Android companion first.")}
                _ = try await Self.adb(["-s",phone.serial,"shell","am","start","--activity-clear-top","--activity-single-top","--es","orientation",width > height ? "landscape" : "portrait","-n","org.openinput.uca/.DisplayActivity"])
                guard self.generation==id else{return}
                var viewerReady=false
                for _ in 0..<15 {
                    let state=try await Self.adb(["-s",phone.serial,"shell","content","query","--uri","content://org.openinput.uca.pairing/display_status"])
                    guard self.generation==id else{return}
                    if state.contains("phase=listening") {viewerReady=true;break}
                    try await Task.sleep(nanoseconds:200_000_000)
                }
                guard viewerReady else{throw DisplayError.message("Unlock the phone and keep the display viewer open, then retry.")}
                let forwarded=try await Self.adb(["-s",phone.serial,"forward","tcp:0","localabstract:uca-display-v1"])
                guard self.generation==id else {
                    _ = try? await Self.adb(["-s",phone.serial,"forward","--remove","tcp:\(forwarded)"]);return
                }
                self.port=forwarded
                guard let port=UInt16(forwarded),port>0 else{throw DisplayError.message("Could not open the display connection.")}
                guard let display=uca_display_create(UInt32(width),UInt32(height)) else{throw DisplayError.message("Virtual displays are unavailable on this macOS version.")}
                self.virtual=display
                let displayID=uca_display_id(display)
                try await Task.sleep(nanoseconds:400_000_000)
                guard self.generation==id else{return}
                try await Task.sleep(nanoseconds:200_000_000)
                guard self.generation==id else{return}
                let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard self.generation==id else{return}
                guard let screen=content.displays.first(where:{$0.displayID==displayID}) else{throw DisplayError.message("The new display is not available for capture.")}
                let stream=DisplayStream(width:width,height:height)
                stream.onFailure={ [weak self] reason in guard let self=self,self.generation==id else{return};self.stop(message:reason) }
                stream.onFrames={ [weak self] count,contentFrame in guard let self=self,self.generation==id else{return};self.frames=count;self.lastContentFrame=contentFrame;if count>0 {self.status="Extended display connected. Drag a Mac window onto your phone."} }
                self.stream=stream;self.status="Starting the picture on your phone…"
                stream.connect(port:port,token:credentials.token,display:screen)
            } catch {
                if self.generation==id {self.stop(message:(error as? DisplayError)?.description ?? "Could not start the display. Check Screen Recording permission and unlock your phone.")}
            }
        }
    }
    func stop(message: String="Extended display stopped.") {
        generation=UUID();startup?.cancel();startup=nil
        stream?.stop();stream=nil
        if let display=virtual {uca_display_destroy(display)};virtual=nil
        if let port=port {
            let target=serial
            Task {_ = try? await Self.adb(["-s",target,"forward","--remove","tcp:\(port)"])}
        }
        port=nil;serial="";active=false;status=message
        if let activity=activity {ProcessInfo.processInfo.endActivity(activity)};activity=nil
    }
}
private enum DisplayError: Error {case message(String)
    var description:String {switch self {case .message(let text):return text}}
}
