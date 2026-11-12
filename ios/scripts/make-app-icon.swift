// Icône provisoire : couverts SF Symbols blancs sur dégradé vert.
// Usage : swift ios/scripts/make-app-icon.swift ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(
    starting: NSColor(srgbRed: 0.24, green: 0.72, blue: 0.47, alpha: 1),
    ending: NSColor(srgbRed: 0.10, green: 0.45, blue: 0.32, alpha: 1)
)?.draw(in: rect, angle: -60)
let config = NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let symbolSize = symbol.size
    symbol.draw(in: NSRect(
        x: (CGFloat(size) - symbolSize.width) / 2, y: (CGFloat(size) - symbolSize.height) / 2,
        width: symbolSize.width, height: symbolSize.height
    ))
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Icône écrite : \(output)")
