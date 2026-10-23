// Generates the AppIcon.iconset PNGs. Usage:
//   swift tools/make_icon.swift && iconutil -c icns AppIcon.iconset && rm -rf AppIcon.iconset
import AppKit
let set = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for mult in [1, 2] {
        let px = base * mult
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(px), r = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
        NSGradient(starting: NSColor(srgbRed: 0.62, green: 0.35, blue: 0.95, alpha: 1),
                   ending: NSColor(srgbRed: 0.35, green: 0.15, blue: 0.75, alpha: 1))!
            .draw(in: NSBezierPath(roundedRect: r, xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let sym = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let sz = sym.size
            sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = mult == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(set)/\(name)"))
    }
}
