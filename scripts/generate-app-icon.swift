import AppKit

// Generate a vector-based, resolution-independent app icon during packaging.
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let transform=AffineTransform(scale:CGFloat(pixels)/1024)
        (transform as NSAffineTransform).concat()
        let background=NSBezierPath(roundedRect:NSRect(x:88,y:88,width:848,height:848),xRadius:190,yRadius:190)
        NSGradient(starting:NSColor(red:0.08,green:0.70,blue:0.77,alpha:1),ending:NSColor(red:0.22,green:0.25,blue:0.75,alpha:1))!.draw(in:background,angle:-45)
        NSColor.white.setStroke()
        let monitor=NSBezierPath(roundedRect:NSRect(x:230,y:380,width:420,height:300),xRadius:32,yRadius:32)
        monitor.lineWidth=28;monitor.stroke()
        let stand=NSBezierPath();stand.move(to:NSPoint(x:440,y:380));stand.line(to:NSPoint(x:440,y:310));stand.move(to:NSPoint(x:340,y:310));stand.line(to:NSPoint(x:540,y:310));stand.lineWidth=28;stand.lineCapStyle = .round;stand.stroke()
        let phone=NSBezierPath(roundedRect:NSRect(x:624,y:280,width:172,height:300),xRadius:30,yRadius:30)
        NSColor(red:0.20,green:0.37,blue:0.73,alpha:1).setFill();phone.fill()
        NSColor.white.setStroke();phone.lineWidth=26;phone.stroke()
        let arrow=NSBezierPath();arrow.move(to:NSPoint(x:410,y:570));arrow.line(to:NSPoint(x:570,y:480));arrow.line(to:NSPoint(x:500,y:460));arrow.line(to:NSPoint(x:470,y:390));arrow.close()
        NSColor.white.setFill();arrow.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix=scale==2 ? "@2x" : ""
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
