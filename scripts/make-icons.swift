// Renders Sugu's icons: the template input-source icon (PDF) and the app
// icon set (PNG). Run from the repo root:
//   swift scripts/make-icons.swift Sugu/Resources
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sugu/Resources")
let glyph = "す"

func font(size: CGFloat) -> NSFont {
    NSFont(name: "HiraginoSans-W6", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
}

func drawGlyph(in rect: NSRect, size: CGFloat, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font(size: size), .foregroundColor: color]
    let text = NSAttributedString(string: glyph, attributes: attributes)
    let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
    text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
}

// Input source icon: a glyph in a rounded frame, as macOS draws its own.
func inputSourceIcon() throws {
    let size = NSRect(x: 0, y: 0, width: 16, height: 16)
    let data = NSMutableData()
    var box = size
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
    context.beginPDFPage(nil)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let frame = NSBezierPath(roundedRect: size.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
    frame.lineWidth = 1.2
    NSColor.black.setStroke()
    frame.stroke()
    drawGlyph(in: size.offsetBy(dx: 0, dy: 0.5), size: 10.5, color: .black)
    NSGraphicsContext.current = nil
    context.endPDFPage()
    context.closePDF()
    try data.write(to: output.appendingPathComponent("InputSourceIcon.pdf"))
}

// App icon: the glyph on the macOS rounded-square grid (824 of 1024).
func appIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.56, blue: 0.98, alpha: 1), ending: NSColor(srgbRed: 0.13, green: 0.35, blue: 0.86, alpha: 1))?
        .draw(in: shape, angle: -90)
    drawGlyph(in: body.offsetBy(dx: 0, dy: 40), size: 520, color: .white)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func appIconSet() throws {
    let set = output.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try appIcon(pixels: points * scale)?.write(to: set.appendingPathComponent(name))
            images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: set.appendingPathComponent("Contents.json"))
    let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent("Assets.xcassets/Contents.json"))
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try inputSourceIcon()
try appIconSet()
print("icons -> \(output.path)")
