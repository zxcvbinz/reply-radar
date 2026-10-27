// Disegna l'icona dell'app (1024×1024) e genera Resources/AppIcon.icns.
// Uso: swift scripts/make-icon.swift && scripts/make-icns.sh
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// Sfondo: squircle della griglia icone macOS (824 pt, margine 100) con ombra leggera.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
NSColor(red: 0.04, green: 0.36, blue: 0.30, alpha: 1).setFill()
tilePath.fill()
context.restoreGState()
NSGradient(colors: [
    NSColor(red: 0.13, green: 0.80, blue: 0.55, alpha: 1),
    NSColor(red: 0.03, green: 0.42, blue: 0.40, alpha: 1),
])!.draw(in: tilePath, angle: -90)

// Fumetto bianco con la coda in basso a sinistra.
let bubble = NSBezierPath(roundedRect: NSRect(x: 230, y: 330, width: 564, height: 440), xRadius: 120, yRadius: 120)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 300, y: 380))
tail.curve(to: NSPoint(x: 240, y: 250), controlPoint1: NSPoint(x: 300, y: 320), controlPoint2: NSPoint(x: 280, y: 270))
tail.curve(to: NSPoint(x: 420, y: 340), controlPoint1: NSPoint(x: 320, y: 255), controlPoint2: NSPoint(x: 390, y: 290))
tail.close()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.18).cgColor)
NSColor.white.setFill()
// Un solo tracciato: due riempimenti separati lascerebbero la riga dell'ombra fra fumetto e coda.
bubble.append(tail)
bubble.windingRule = .nonZero
bubble.fill()
context.restoreGState()

// Tre barre crescenti: le statistiche.
let barColor = NSColor(red: 0.05, green: 0.55, blue: 0.45, alpha: 1)
for (index, height) in [120.0, 200.0, 290.0].enumerated() {
    let bar = NSRect(x: 350 + Double(index) * 118, y: 400, width: 84, height: height)
    barColor.withAlphaComponent(0.55 + 0.2 * Double(index)).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 22, yRadius: 22).fill()
}
image.unlockFocus()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
// Ridisegna a 1024 pixel esatti (lockFocus su schermi Retina produce 2048).
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "icon-1024.png"))
print("scritto \(out.path)/icon-1024.png")
