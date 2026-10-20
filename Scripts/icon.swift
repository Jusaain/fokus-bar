import AppKit
import Foundation
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let background = NSBezierPath(roundedRect: NSRect(x: p*0.06, y: p*0.06, width: p*0.88, height: p*0.88), xRadius: p*0.2, yRadius: p*0.2)
        NSGradient(starting: NSColor(srgbRed: 0.26, green: 0.53, blue: 1.0, alpha: 1), ending: NSColor(srgbRed: 0.09, green: 0.24, blue: 0.70, alpha: 1))!.draw(in: background, angle: -60)
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: p*0.24,y:p*0.24,width:p*0.52,height:p*0.52)); ring.lineWidth = p*0.045; ring.stroke()
        let tick = NSBezierPath(); tick.move(to:NSPoint(x:p*0.35,y:p*0.49)); tick.line(to:NSPoint(x:p*0.46,y:p*0.39)); tick.line(to:NSPoint(x:p*0.66,y:p*0.62)); tick.lineWidth=p*0.055; tick.lineCapStyle = .round; tick.lineJoinStyle = .round; tick.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
