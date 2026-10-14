import Foundation
import ScreenCaptureKit
import VideoToolbox
import Network
import CoreMedia
import ControlCore

// All mutable pipeline state is serialized on queue. Only one encoded frame may
// be in flight. Keep only the newest pending image, preserving the final update.
final class DisplayStream: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "extended.display.video", qos: .userInteractive)
    private var connection: NWConnection?
    private var capture: SCStream?
    private var encoder: VTCompressionSession?
    private var timer: DispatchSourceTimer?
    private var busy = true, encoding = false, stopped = false
    private var deadline = 0.0
    private var frames = 0
    private var encodingContentUpdate = false
    private var lastContentFrame = 0
    private var latestImage: CVPixelBuffer?
    private var imagePending = false
    private var tailFrames = 0
    private var lastSubmit = 0.0
    private var lastMaintenance = 0.0
    var onFailure: ((String) -> Void)?
    var onConnectionLost: ((String) -> Void)?
    var onFrames: ((Int, Int) -> Void)?
    private let width: Int, height: Int
    init(width: Int, height: Int) { self.width=width; self.height=height; super.init() }

    func connect(port: UInt16, token: String, display: SCDisplay) {
        queue.async {
            let options = NWProtocolTCP.Options(); options.noDelay = true
            let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: nil,tcp: options))
            self.connection=c; self.deadline=ProcessInfo.processInfo.systemUptime+8
            c.stateUpdateHandler = { [weak self] state in
                guard let self=self, !self.stopped else { return }
                switch state {
                case .ready:
                    c.send(content: Data("AUTH \(token)\n".utf8), completion: .contentProcessed { error in
                        if error != nil { self.fail("Could not authenticate display connection.",recoverable:true); return }
                        c.receive(minimumIncompleteLength: 3,maximumLength: 3) { data,_,done,error in
                            guard !self.stopped else {return}
                            guard error == nil, !done, data == Data("OK\n".utf8) else { self.fail("Display unavailable. Unlock your phone, keep its viewer open, and retry.");return }
                            var header=Data("UCD1".utf8);header.append(contentsOf: [UInt8(self.width>>8),UInt8(self.width&255),UInt8(self.height>>8),UInt8(self.height&255)])
                            c.send(content: header, completion: .contentProcessed { error in
                                if error != nil {self.fail("Display connection closed.",recoverable:true);return}
                                self.startCapture(display)
                            })
                        }
                    })
                case .failed: self.fail("Display connection failed. Check the phone and cable or Wi-Fi.",recoverable:true)
                default: break
                }
            }
            let timer=DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now()+0.033,repeating:0.033)
            timer.setEventHandler { [weak self] in
                guard let self=self,!self.stopped else{return}
                if (self.busy || self.encoding) && ProcessInfo.processInfo.systemUptime>self.deadline {self.fail("Display stopped responding.",recoverable:true);return}
                self.submitLatest()
                let now=ProcessInfo.processInfo.systemUptime
                if now-self.lastMaintenance>=1 {
                    self.lastMaintenance=now
                    if !self.busy && !self.encoding {self.send(Data(),pts:0)}
                    let count=self.frames, contentFrame=self.lastContentFrame
                    DispatchQueue.main.async {self.onFrames?(count,contentFrame)}
                }
            }
            self.timer=timer;timer.resume();c.start(queue:self.queue)
        }
    }
    private func startCapture(_ display: SCDisplay) {
        guard !stopped else{return}
        var session: VTCompressionSession?
        let result=VTCompressionSessionCreate(allocator:kCFAllocatorDefault,width:Int32(width),height:Int32(height),codecType:kCMVideoCodecType_H264,encoderSpecification:[kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary,imageBufferAttributes:nil,compressedDataAllocator:nil,outputCallback:{ ref,_,status,flags,sample in
            guard let ref=ref else{return}
            let owner=Unmanaged<DisplayStream>.fromOpaque(ref).takeUnretainedValue()
            owner.queue.async { [weak owner] in
                guard let owner=owner,!owner.stopped else{return}
                owner.encoding=false
                if status==noErr && flags.contains(.frameDropped) {owner.imagePending=true;return}
                guard status==noErr,let sample=sample else{owner.fail("Video encoding failed.");return}
                owner.encoded(sample)
            }
        },refcon:Unmanaged.passUnretained(self).toOpaque(),compressionSessionOut:&session)
        guard result==noErr,let session=session else{fail("H.264 encoder unavailable.");return}
        encoder=session
        for (key,value) in [(kVTCompressionPropertyKey_RealTime,kCFBooleanTrue as CFTypeRef),
                            (kVTCompressionPropertyKey_AllowFrameReordering,kCFBooleanFalse as CFTypeRef),
                            (kVTCompressionPropertyKey_ProfileLevel,kVTProfileLevel_H264_Baseline_AutoLevel as CFTypeRef),
                            (kVTCompressionPropertyKey_AverageBitRate,(width * height > 3_000_000 ? 12_000_000 : (width * height > 2_300_000 ? 8_000_000 : 4_000_000)) as CFNumber),
                            (kVTCompressionPropertyKey_MaxKeyFrameInterval,60 as CFNumber),
                            (kVTCompressionPropertyKey_ExpectedFrameRate,30 as CFNumber)] {
            guard VTSessionSetProperty(session,key:key,value:value)==noErr else{fail("Could not configure video encoder.");return}
        }
        guard VTCompressionSessionPrepareToEncodeFrames(session)==noErr else{fail("Could not start encoder.");return}
        let config=SCStreamConfiguration();config.width=width;config.height=height
        config.minimumFrameInterval=CMTime(value:1,timescale:30);config.queueDepth=2
        config.capturesAudio=false
        config.pixelFormat=kCVPixelFormatType_32BGRA;config.showsCursor=true
        let stream=SCStream(filter:SCContentFilter(display:display,excludingWindows:[]),configuration:config,delegate:self)
        capture=stream
        do {try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue)} catch {fail("Could not attach display capture.");return}
        stream.startCapture { error in self.queue.async {
            guard !self.stopped else{return}
            if error != nil {self.fail("Screen capture failed. Allow Screen Recording in macOS settings.")}
            else {self.busy=false}
        }}
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped,type == .screen,sampleBuffer.isValid,
              let image=CMSampleBufferGetImageBuffer(sampleBuffer) else{return}
        if let items=CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
           let raw=items.first?[.status] as? Int, raw != SCFrameStatus.complete.rawValue {return}
        latestImage=image;imagePending=true;tailFrames=2
        submitLatest()
    }
    private func submitLatest() {
        guard !stopped,!busy,!encoding,let image=latestImage,let encoder=encoder else{return}
        let now=ProcessInfo.processInfo.systemUptime
        // Briefly repeat the last picture after changes stop. Some Android
        // decoders retain one picture until the following access unit arrives.
        guard imagePending || (tailFrames>0 && now-lastSubmit>=0.05) else{return}
        encodingContentUpdate=imagePending
        if imagePending {imagePending=false} else {tailFrames-=1}
        lastSubmit=now;encoding=true;deadline=now+5
        let result=VTCompressionSessionEncodeFrame(encoder,imageBuffer:image,presentationTimeStamp:CMClockGetTime(CMClockGetHostTimeClock()),duration:CMTime(value:1,timescale:30),frameProperties:nil,sourceFrameRefcon:nil,infoFlagsOut:nil)
        if result != noErr {encoding=false;fail("Could not encode display frame.")}
    }
    func stream(_ stream: SCStream,didStopWithError error: Error) { queue.async {self.fail("Screen capture stopped.")} }
    private func encoded(_ sample: CMSampleBuffer) {
        guard let block=CMSampleBufferGetDataBuffer(sample),let format=CMSampleBufferGetFormatDescription(sample) else{fail("Invalid encoded frame.");return}
        var parameterSets=[Data]()
        let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[CFString:Any]]
        let keyFrame=attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        if keyFrame {
            for i in 0..<2 {
                var pointer: UnsafePointer<UInt8>?,length=0,count=0
                guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,parameterSetIndex:i,parameterSetPointerOut:&pointer,parameterSetSizeOut:&length,parameterSetCountOut:&count,nalUnitHeaderLengthOut:nil)==noErr,let pointer=pointer else{fail("Invalid H.264 configuration.");return}
                parameterSets.append(Data(bytes:pointer,count:length))
            }
        }
        let length=CMBlockBufferGetDataLength(block)
        guard length>0,length<=4*1024*1024 else{fail("Video frame exceeds size limit.");return}
        var bytes=[UInt8](repeating:0,count:length)
        guard CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:&bytes)==noErr else{fail("Could not read video frame.");return}
        guard let packet=DisplayWire.annexB(bytes,parameterSets:parameterSets) else{fail("Invalid H.264 packet.");return}
        let seconds=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        guard seconds.isFinite,seconds>=0,seconds<1e12 else{fail("Invalid video timestamp.");return}
        if encodingContentUpdate {lastContentFrame=frames+1}
        send(packet,pts:UInt64(seconds*1_000_000))
    }
    private func send(_ payload: Data,pts: UInt64) {
        guard !stopped,let c=connection else{return}
        busy=true;deadline=ProcessInfo.processInfo.systemUptime+5
        guard let packet=DisplayWire.frame(payload,timestamp:pts) else{fail("Invalid video packet.");return}
        c.send(content:packet,completion:.contentProcessed { error in
            guard !self.stopped else{return}
            guard error==nil else{self.fail("Display connection closed.",recoverable:true);return}
            c.receive(minimumIncompleteLength:1,maximumLength:1) { data,_,done,error in
                guard !self.stopped else{return}
                guard error==nil,!done,data==Data([0]) else{self.fail("Phone stopped receiving video.",recoverable:true);return}
                self.busy=false;if !payload.isEmpty {self.frames+=1}
                self.submitLatest()
            }
        })
    }
    private func fail(_ reason: String, recoverable: Bool = false) {guard !stopped else{return};stopOnQueue();DispatchQueue.main.async {if recoverable {self.onConnectionLost?(reason)} else {self.onFailure?(reason)}}}
    func stop() {queue.async {self.stopOnQueue()}}
    private func stopOnQueue() {
        guard !stopped else{return};stopped=true;timer?.cancel();timer=nil
        capture?.stopCapture(completionHandler:{_ in});capture=nil
        latestImage=nil;imagePending=false;tailFrames=0
        if let encoder=encoder {VTCompressionSessionInvalidate(encoder)};encoder=nil
        connection?.stateUpdateHandler=nil;connection?.cancel();connection=nil
    }
}
