// Draws the app icon (1024×1024 PNG): a caption bubble with one finished (white) and one
// in-progress (dimmer) line of text, echoing the caption bar.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let pixels = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Couldn't create bitmap") }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body centered on a 1024pt canvas.
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
color(0x111318).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x2A2F3D), ending: color(0x0C0E14))!.draw(in: body, angle: -90)

// Speech bubble with a tail at the bottom left.
let bubble = NSBezierPath(roundedRect: NSRect(x: 196, y: 372, width: 632, height: 340), xRadius: 80, yRadius: 80)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 300, y: 400))
tail.line(to: NSPoint(x: 280, y: 268))
tail.line(to: NSPoint(x: 420, y: 380))
tail.close()
bubble.append(tail)
NSGradient(starting: color(0x3CCBA9), ending: color(0x2483E0))!.draw(in: bubble, angle: -35)

// Caption lines: the first is finished, the second is still being recognized.
func capsule(x: CGFloat, y: CGFloat, width: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 56), xRadius: 28, yRadius: 28).fill()
}
capsule(x: 276, y: 576, width: 472, fill: .white)
capsule(x: 276, y: 470, width: 276, fill: .white)
capsule(x: 582, y: 470, width: 166, fill: color(0xFFFFFF, 0.5))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Couldn't encode PNG") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
