import AppKit
import ScreenCaptureKit
import CVirtualDisplay
import ControlCore

final class ExtendedDisplay: ObservableObject {
    @Published private(set) var active=false
    @Published private(set) var status="Use your phone as another Mac screen."
    @Published private(set) var frames=0
    @Published private(set) var paused=false
    private(set) var lastContentFrame=0
    static let supportedResolutions = ["1476×1638", "1638×1476", "1968×2184", "2184×1968", "984×1092", "1092×984", "1280×800", "1920×1080"]
    static let retinaResolutions: Set<String> = ["1476×1638", "1638×1476", "1968×2184", "2184×1968"]
    private let defaults: UserDefaults
    @Published var resolution: String {
        didSet { if Self.supportedResolutions.contains(resolution) { defaults.set(resolution, forKey: "extendedDisplayResolution") } }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "extendedDisplayResolution") ?? ""
        resolution = Self.supportedResolutions.contains(saved) ? saved : "1476×1638"
    }
    var displayID: CGDirectDisplayID? { virtual.map { uca_display_id($0) } }
    private var virtual: UnsafeMutableRawPointer?
    private var stream: DisplayStream?
    private var port: String?
    private var serial=""
    private var generation=UUID()
    private var activity: NSObjectProtocol?
    private var startup: Task<Void,Never>?
    private var reconnect: Task<Void,Never>?
    private var streamGeneration=UUID()
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
        active=true;paused=false;frames=0;lastContentFrame=0;status="Preparing your extended display…"
        let id=UUID();generation=id;serial=phone.serial
        let dimensions=resolution.split(separator:"×").compactMap {Int($0)}
        guard dimensions.count==2 else {stop(message:"Choose a display resolution.");return}
        let width=dimensions[0],height=dimensions[1]
        let retina = Self.retinaResolutions.contains(resolution)
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
                guard let display=uca_display_create(UInt32(width),UInt32(height), retina ? 1 : 0) else{throw DisplayError.message("Virtual displays are unavailable on this macOS version.")}
                self.virtual=display
                let displayID=uca_display_id(display)
                try await Task.sleep(nanoseconds:400_000_000)
                guard self.generation==id else{return}
                try await Task.sleep(nanoseconds:200_000_000)
                guard self.generation==id else{return}
                let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard self.generation==id else{return}
                guard let screen=content.displays.first(where:{$0.displayID==displayID}) else{throw DisplayError.message("The new display is not available for capture.")}
                self.attachStream(width:width,height:height,port:port,token:credentials.token,screen:screen,session:id)

            } catch {
                if self.generation==id {self.stop(message:(error as? DisplayError)?.description ?? "Could not start the display. Check Screen Recording permission and unlock your phone.")}
            }
        }
    }
    private func attachStream(width: Int, height: Int, port: UInt16, token: String, screen: SCDisplay, session: UUID) {
        let video=DisplayStream(width:width,height:height), videoID=UUID()
        streamGeneration=videoID;paused=false;frames=0;lastContentFrame=0
        video.onFailure={ [weak self] reason in
            guard let self=self,self.generation==session,self.streamGeneration==videoID else{return}
            self.stop(message:reason)
        }
        video.onConnectionLost={ [weak self] _ in
            guard let self=self,self.generation==session,self.streamGeneration==videoID else{return}
            self.waitForViewer(width:width,height:height,port:port,token:token,session:session)
        }
        video.onFrames={ [weak self] count,contentFrame in
            guard let self=self,self.generation==session,self.streamGeneration==videoID else{return}
            self.frames=count;self.lastContentFrame=contentFrame
            if count>0 {self.status="Extended display connected. Drag a Mac window onto your phone."}
        }
        stream=video;status="Starting the picture on your phone…"
        video.connect(port:port,token:token,display:screen)
    }
    private func waitForViewer(width: Int, height: Int, port: UInt16, token: String, session: UUID) {
        streamGeneration=UUID();stream?.stop();stream=nil;paused=true
        status="Picture paused. Reopen the phone’s display viewer to resume. Your Mac windows stay in place."
        let target=serial
        reconnect?.cancel()
        reconnect=Task { @MainActor [weak self] in
            guard let self=self else{return}
            var failures=0
            while self.generation==session && !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds:1_000_000_000)
                    // Query only. Never bring the viewer forward over another app.
                    let state=try await Self.adb(["-s",target,"shell","content","query","--uri","content://org.openinput.uca.pairing/display_status"])
                    guard self.generation==session,!Task.isCancelled else{return}
                    failures=0
                    guard state.contains("phase=listening") else{continue}
                    let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                    guard self.generation==session,!Task.isCancelled else{return}
                    guard let screen=content.displays.first(where:{$0.displayID==self.displayID}) else {
                        self.stop(message:"The Mac display is no longer available.");return
                    }
                    self.reconnect=nil
                    self.attachStream(width:width,height:height,port:port,token:token,screen:screen,session:session)
                    return
                } catch {
                    guard self.generation==session,!Task.isCancelled else{return}
                    failures+=1
                    if failures>=3 {self.stop(message:"Phone connection lost. Check Wi-Fi or USB and reconnect.");return}
                }
            }
        }
    }
    func stop(message: String="Extended display stopped.") {
        generation=UUID();streamGeneration=UUID();startup?.cancel();startup=nil;reconnect?.cancel();reconnect=nil
        stream?.stop();stream=nil
        if let display=virtual {uca_display_destroy(display)};virtual=nil
        if let port=port {
            let target=serial
            Task {_ = try? await Self.adb(["-s",target,"forward","--remove","tcp:\(port)"])}
        }
        port=nil;serial="";active=false;paused=false;status=message
        if let activity=activity {ProcessInfo.processInfo.endActivity(activity)};activity=nil
    }
}
private enum DisplayError: Error {case message(String)
    var description:String {switch self {case .message(let text):return text}}
}
