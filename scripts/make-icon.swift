// Original vector artwork. Run: swift scripts/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o macos/Assets/AppIcon.icns
import AppKit
let folder = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat = 1) -> NSColor { NSColor(srgbRed:r,green:g,blue:b,alpha:a) }
// A generic earbud drawn from primitives, tilted mid-swing, with motion arcs on both sides.
func earbud() -> NSBezierPath {
    let shape = NSBezierPath(ovalIn:NSRect(x:-150,y:-20,width:300,height:250))
    shape.append(NSBezierPath(roundedRect:NSRect(x:10,y:-330,width:92,height:360),xRadius:46,yRadius:46))
    return shape
}
func arc(_ radius:CGFloat,_ from:CGFloat,_ to:CGFloat,_ alpha:CGFloat) {
    let path = NSBezierPath()
    path.appendArc(withCenter:NSPoint(x:512,y:500),radius:radius,startAngle:from,endAngle:to)
    path.lineWidth = 34; path.lineCapStyle = .round
    color(0.94,0.98,1,alpha).setStroke(); path.stroke()
}
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size*scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        let transform = NSAffineTransform(); transform.scale(by:CGFloat(pixels)/1024); transform.concat()
        let tile = NSBezierPath(roundedRect:NSRect(x:76,y:76,width:872,height:872),xRadius:196,yRadius:196)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width:0,height:-12); shadow.set()
        color(0.16,0.19,0.40).setFill(); tile.fill(); NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors:[color(0.035,0.06,0.16),color(0.15,0.21,0.51),color(0.22,0.48,0.68)])!.draw(in:tile,angle:50)
        color(1,1,1,0.16).setStroke(); tile.lineWidth = 3; tile.stroke()
        let halo = NSBezierPath(ovalIn:NSRect(x:205,y:245,width:614,height:534))
        NSGradient(colors:[color(0.15,0.85,0.88,0.24),color(0.25,0.36,0.88,0)])!.draw(in:halo,relativeCenterPosition:NSPoint(x:0,y:0))
        arc(300,-28,28,0.85); arc(370,-22,22,0.45)
        arc(300,152,208,0.85); arc(370,158,202,0.45)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = color(0.02,0.05,0.15,0.7); glow.shadowBlurRadius = 22; glow.shadowOffset = NSSize(width:0,height:-16); glow.set()
        let place = NSAffineTransform(); place.translateX(by:500,yBy:560); place.rotate(byDegrees:-18)
        let body = earbud(); body.transform(using:place as AffineTransform)
        color(0.94,0.98,1).setFill(); body.fill()
        NSGraphicsContext.restoreGraphicsState()
        let grille = NSBezierPath(ovalIn:NSRect(x:-118,y:70,width:120,height:92)); grille.transform(using:place as AffineTransform)
        color(0.12,0.16,0.27,0.9).setFill(); grille.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    }
}
