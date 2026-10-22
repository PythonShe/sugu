// Renders Sugu's app icon artwork from one set of geometry:
//   Assets/svg/*.svg            flat icons (1024 canvas, 824 plate, no shadow)
//   Assets/png/*.png            flat icons at 1024 with the system-style shadow
//   Assets/svg/sugu-favicon-*.svg  favicons (plate fills the canvas, heavier marks for 16 px)
//   Assets/*.icon/Assets/*.svg  layers for Icon Composer (1024 canvas, artwork only)
//   Sugu/Resources/Assets.xcassets/AppIcon.appiconset/*.png   legacy sizes from the light stroke icon
// Usage: swift scripts/render-icon.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let fm = FileManager.default
func dir(_ p: String) -> URL { let u = root.appendingPathComponent(p); try! fm.createDirectory(at: u, withIntermediateDirectories: true); return u }

// MARK: geometry (all relative to a plate of side P)
let GRID: CGFloat = 1024
struct Color { let r, g, b, a: CGFloat
  var hex: String { String(format: "#%02X%02X%02X", Int(r * 255 + 0.5), Int(g * 255 + 0.5), Int(b * 255 + 0.5)) }
  var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) } }
func hex(_ s: String, _ a: CGFloat = 1) -> Color { let v = Int(s.dropFirst(), radix: 16)!
  return Color(r: CGFloat((v >> 16) & 255) / 255, g: CGFloat((v >> 8) & 255) / 255, b: CGFloat(v & 255) / 255, a: a) }
let ink = hex("#1D1D1F"), white = hex("#FFFFFF"), blue = hex("#0A84FF"), dotLight = hex("#C7C7CC"), dotDark = hex("#8E8E93")
struct Plate { let top: Color; let bottom: Color }
let paper = Plate(top: hex("#FFFFFF"), bottom: hex("#ECECF0"))
let graphite = Plate(top: hex("#3A3A3C"), bottom: hex("#1C1C1E"))

/// A shape in plate coordinates (side P), either a rounded rect or a glyph path.
enum Shape { case rrect(CGRect, CGFloat), path(CGPath, strokeWidth: CGFloat) }
struct Mark { let name: String; let color: Color; let shapes: [Shape] }

func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Shape { .rrect(CGRect(x: x, y: y, width: w, height: h), min(w, h) / 2) }

// 一 from Hiragino Mincho ProN W6, as a path in plate coordinates (y down).
func strokeGlyph(P: CGFloat, weight: CGFloat = 0.026) -> Shape {
  let em = 0.74 * P
  let font = CTFontCreateWithName("HiraMinProN-W6" as CFString, em, nil)
  var glyph: CGGlyph = 0; var ch = Array("一".utf16)
  CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1)
  let raw = CTFontCreatePathForGlyph(font, glyph, nil)!
  let left = 0.11 * P - 0.048 * em            // visual left edge of the stroke at 0.11 P
  let baseline = 0.512 * P + 0.388 * em        // body of the stroke centred slightly below middle
  var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: left, ty: baseline)
  return .path(raw.copy(using: &t)!, strokeWidth: weight * P)   // fatten the W6 outline to an icon weight
}

/// `small` thickens the stroke and caret so they survive 16 px.
func strokeMarks(P: CGFloat, inkColor: Color, small: Bool = false) -> [Mark] {
  let barH = (small ? 0.5 : 0.44) * P, barW = (small ? 0.1 : 0.065) * P
  return [Mark(name: "stroke", color: inkColor, shapes: [strokeGlyph(P: P, weight: small ? 0.075 : 0.026)]),
          Mark(name: "caret", color: blue, shapes: [rrect(0.82 * P, 0.5 * P - barH / 2, barW, barH)])]
}

func markedMarks(P: CGFloat, caret: Color, solid: Color, dot: Color) -> [Mark] {
  let cx = 0.5 * P, cy = 0.5 * P
  let barH = 0.40 * P, barW = 0.07 * P
  let uy = cy + barH / 2 - 0.02 * P, uh = 0.045 * P
  let w1 = 0.24 * P, w2 = 0.20 * P, gap = 0.035 * P
  let x0 = cx - (w1 + gap + w2 + gap + barW) / 2
  let step = w2 / 4
  return [Mark(name: "converted", color: solid, shapes: [rrect(x0, uy, w1, uh)]),
          Mark(name: "raw", color: dot, shapes: (0..<4).map { rrect(x0 + w1 + gap + CGFloat($0) * step + (step - uh) / 2, uy, uh, uh) }),
          Mark(name: "caret", color: caret, shapes: [rrect(x0 + w1 + gap + w2 + gap, uy + uh - barH, barW, barH)])]
}

// MARK: squircle (Apple's continuous corner, as bezier corners)
func squircle(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> CGPath {
  let r = w * 0.2237, c = r * (1.5283 - 1), h = w
  let p = CGMutablePath()
  p.move(to: CGPoint(x: x + r, y: y)); p.addLine(to: CGPoint(x: x + w - r, y: y))
  p.addCurve(to: CGPoint(x: x + w, y: y + r), control1: CGPoint(x: x + w - r + c, y: y), control2: CGPoint(x: x + w, y: y + r - c))
  p.addLine(to: CGPoint(x: x + w, y: y + h - r))
  p.addCurve(to: CGPoint(x: x + w - r, y: y + h), control1: CGPoint(x: x + w, y: y + h - r + c), control2: CGPoint(x: x + w - r + c, y: y + h))
  p.addLine(to: CGPoint(x: x + r, y: y + h))
  p.addCurve(to: CGPoint(x: x, y: y + h - r), control1: CGPoint(x: x + r - c, y: y + h), control2: CGPoint(x: x, y: y + h - r + c))
  p.addLine(to: CGPoint(x: x, y: y + r))
  p.addCurve(to: CGPoint(x: x + r, y: y), control1: CGPoint(x: x, y: y + r - c), control2: CGPoint(x: x + r - c, y: y))
  p.closeSubpath(); return p
}

// MARK: SVG
func svgPath(_ path: CGPath, dx: CGFloat, dy: CGFloat) -> String {
  var d = ""; func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
  path.applyWithBlock { e in let p = e.pointee.points
    switch e.pointee.type {
    case .moveToPoint: d += "M\(f(p[0].x + dx)) \(f(p[0].y + dy))"
    case .addLineToPoint: d += "L\(f(p[0].x + dx)) \(f(p[0].y + dy))"
    case .addQuadCurveToPoint: d += "Q\(f(p[0].x + dx)) \(f(p[0].y + dy)) \(f(p[1].x + dx)) \(f(p[1].y + dy))"
    case .addCurveToPoint: d += "C\(f(p[0].x + dx)) \(f(p[0].y + dy)) \(f(p[1].x + dx)) \(f(p[1].y + dy)) \(f(p[2].x + dx)) \(f(p[2].y + dy))"
    case .closeSubpath: d += "Z"
    @unknown default: break } }
  return d
}
func svgMarks(_ marks: [Mark], dx: CGFloat, dy: CGFloat) -> String {
  marks.map { m in
    "  <g id=\"\(m.name)\" fill=\"\(m.color.hex)\">\n" + m.shapes.map { s in
      switch s {
      case .rrect(let r, let rad): return String(format: "    <rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\"/>", r.minX + dx, r.minY + dy, r.width, r.height, rad)
      case .path(let p, let sw): return String(format: "    <path d=\"%@\" stroke=\"%@\" stroke-width=\"%.2f\" stroke-linejoin=\"round\"/>", svgPath(p, dx: dx, dy: dy), m.color.hex, sw)
      } }.joined(separator: "\n") + "\n  </g>" }.joined(separator: "\n")
}
func svgDocument(_ body: String) -> String {
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n\(body)\n</svg>\n"
}
func flatSVG(plate: Plate, marks: [Mark], id: String, side: CGFloat = 824) -> String {
  let inset = (GRID - side) / 2
  let sq = svgPath(squircle(inset, inset, side), dx: 0, dy: 0)
  return svgDocument("""
  <defs><linearGradient id="plate-\(id)" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\(plate.top.hex)"/><stop offset="1" stop-color="\(plate.bottom.hex)"/></linearGradient></defs>
  <path d="\(sq)" fill="url(#plate-\(id))"/>
\(svgMarks(marks, dx: inset, dy: inset))
""")
}

// MARK: PNG via CoreGraphics
func render(size: Int, plate: Plate, marks: [Mark]) -> Data {
  let s = CGFloat(size) / GRID
  let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: s, y: -s)   // y down, 1024 grid
  let inset = (GRID - 824) / 2
  let sq = squircle(inset, inset, 824)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
  ctx.addPath(sq); ctx.setFillColor(plate.bottom.cg); ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState(); ctx.addPath(sq); ctx.clip()
  let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [plate.top.cg, plate.bottom.cg] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: inset + 824), options: [])
  ctx.translateBy(x: inset, y: inset)
  for m in marks { ctx.setFillColor(m.color.cg); ctx.setStrokeColor(m.color.cg)
    for sh in m.shapes { switch sh {
      case .rrect(let r, let rad): ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)); ctx.fillPath()
      case .path(let p, let sw): ctx.addPath(p); ctx.fillPath(); ctx.setLineWidth(sw); ctx.setLineJoin(.round); ctx.addPath(p); ctx.strokePath() } } }
  ctx.restoreGState()
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  return rep.representation(using: .png, properties: [:])!
}

// MARK: Icon Composer packages
func iconJSON(fillLight: String, fillDark: String, layers: [(name: String, light: Color, dark: Color)]) -> String {
  func c(_ k: Color) -> String { String(format: "srgb:%.5f,%.5f,%.5f,1.00000", k.r, k.g, k.b) }
  let layerJSON = layers.map { l in """
        {
          "fill-specializations" : [
            { "value" : { "solid" : "\(c(l.light))" } },
            { "appearance" : "dark", "value" : { "solid" : "\(c(l.dark))" } }
          ],
          "glass" : true,
          "hidden" : false,
          "image-name" : "\(l.name).svg",
          "name" : "\(l.name)",
          "position" : { "scale" : 1, "translation-in-points" : [ 0, 0 ] }
        }
""" }.joined(separator: ",\n")
  return """
{
  "fill" : { "automatic-gradient" : "\(fillLight)" },
  "fill-specializations" : [
    { "value" : { "automatic-gradient" : "\(fillLight)" } },
    { "appearance" : "dark", "value" : { "automatic-gradient" : "\(fillDark)" } }
  ],
  "groups" : [
    {
      "layers" : [
\(layerJSON)
      ],
      "lighting" : "individual",
      "shadow" : { "kind" : "neutral", "opacity" : 0.4 },
      "specular" : true,
      "translucency" : { "enabled" : true, "value" : 0.2 }
    }
  ],
  "supported-platforms" : { "circles" : [ "watchOS" ], "squares" : "shared" }
}

"""
}
func writeIcon(_ name: String, fillLight: Color, fillDark: Color, light: [Mark], dark: [Mark]) {
  let pkg = dir("Assets/\(name).icon"); let assets = dir("Assets/\(name).icon/Assets")
  for m in light { try! svgDocument(svgMarks([Mark(name: m.name, color: ink, shapes: m.shapes)], dx: 0, dy: 0))
    .write(to: assets.appendingPathComponent("\(m.name).svg"), atomically: true, encoding: .utf8) }
  func c(_ k: Color) -> String { String(format: "srgb:%.5f,%.5f,%.5f,1.00000", k.r, k.g, k.b) }
  let json = iconJSON(fillLight: c(fillLight), fillDark: c(fillDark),
                      layers: zip(light, dark).map { ($0.name, $0.color, $1.color) })
  try! json.write(to: pkg.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
}

// MARK: outputs
let svgDir = dir("Assets/svg"), pngDir = dir("Assets/png")
let flat: [(String, Plate, [Mark])] = [
  ("sugu-icon-stroke-light", paper, strokeMarks(P: 824, inkColor: ink)),
  ("sugu-icon-stroke-dark", graphite, strokeMarks(P: 824, inkColor: white)),
  ("sugu-icon-marked-text-light", paper, markedMarks(P: 824, caret: ink, solid: blue, dot: dotLight)),
  ("sugu-icon-marked-text-dark", graphite, markedMarks(P: 824, caret: white, solid: blue, dot: dotDark)),
]
for (name, plate, marks) in flat {
  try! flatSVG(plate: plate, marks: marks, id: name).write(to: svgDir.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
  try! render(size: 1024, plate: plate, marks: marks).write(to: pngDir.appendingPathComponent("\(name).png"))
}
// Favicons: the plate fills the canvas, and each contrasts with the browser chrome
// it is shown in (graphite on light tab bars, paper on dark ones).
for (name, plate, color) in [("sugu-favicon-graphite", graphite, white), ("sugu-favicon-paper", paper, ink)] {
  try! flatSVG(plate: plate, marks: strokeMarks(P: GRID, inkColor: color, small: true), id: name, side: GRID)
    .write(to: svgDir.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
}
// Icon Composer layers span the full 1024 canvas (the system supplies the plate).
writeIcon("AppIcon", fillLight: hex("#F2F2F4"), fillDark: hex("#2A2A2C"),
          light: strokeMarks(P: 1024, inkColor: ink), dark: strokeMarks(P: 1024, inkColor: white))
writeIcon("AppIcon-MarkedText", fillLight: hex("#F2F2F4"), fillDark: hex("#2A2A2C"),
          light: markedMarks(P: 1024, caret: ink, solid: blue, dot: dotLight),
          dark: markedMarks(P: 1024, caret: white, solid: blue, dot: dotDark))
// Legacy sizes for macOS before 26, from the light stroke icon.
let set = dir("Sugu/Resources/Assets.xcassets/AppIcon.appiconset")
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
  let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
  try! render(size: pt * scale, plate: paper, marks: strokeMarks(P: 824, inkColor: ink)).write(to: set.appendingPathComponent(name))
}
print("rendered")
