// Renders SF Symbols to PNG for Tools/make_screenshots.py.
//
// Pillow has no access to SF Symbols, and redrawing them by hand would drift
// from what the apps actually show, so the screenshot script shells out here.
//
//     swift Tools/render_symbols.swift <out-dir> <name>@<px>@<weight>@<RRGGBB> ...
//
// <px> is the symbol's point size in output pixels; <weight> is one of
// regular / medium / semibold / bold. Each symbol is written to
// <out-dir>/<name>@<px>@<weight>@<RRGGBB>.png, trimmed to its own bounds.

import AppKit

let args = CommandLine.arguments.dropFirst()
guard let outDir = args.first else {
    FileHandle.standardError.write("usage: render_symbols.swift <out-dir> <spec>...\n".data(using: .utf8)!)
    exit(2)
}

let weights: [String: NSFont.Weight] = [
    "regular": .regular, "medium": .medium, "semibold": .semibold, "bold": .bold,
]

for spec in args.dropFirst() {
    let parts = spec.split(separator: "@").map(String.init)
    guard parts.count == 4,
          let px = Double(parts[1]),
          let weight = weights[parts[2]],
          let rgb = Int(parts[3], radix: 16) else {
        FileHandle.standardError.write("bad spec: \(spec)\n".data(using: .utf8)!)
        exit(2)
    }
    let color = NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                        green: CGFloat((rgb >> 8) & 0xFF) / 255,
                        blue: CGFloat(rgb & 0xFF) / 255,
                        alpha: 1)
    let config = NSImage.SymbolConfiguration(pointSize: px, weight: weight)
        .applying(.init(paletteColors: [color]))
    guard let image = NSImage(systemSymbolName: parts[0], accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        FileHandle.standardError.write("unknown symbol: \(parts[0])\n".data(using: .utf8)!)
        exit(1)
    }

    // Drawn 1:1 — the caller already asked for output pixels.
    let size = NSSize(width: ceil(image.size.width), height: ceil(image.size.height))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec).png")
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
