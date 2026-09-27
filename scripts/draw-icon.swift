// Erzeugt das App-Icon: swift scripts/draw-icon.swift docs/icon.png
// Ebenen fürs Icon-Composer-Icon (hell/dunkel): swift scripts/draw-icon.swift --layers TOM/AppIcon.icon/Assets

import AppKit
import CoreGraphics

// Zeichnet das TOM-Icon: Zeitblöcke in Projektfarben mit „Jetzt“-Linie, auf Tintenblau.
let size: CGFloat = 1024
// Einzelne Ebenen ohne Hintergrund. Hintergrund und Farbe der „Jetzt“-Linie legt `icon.json` je nach Modus fest.
let layersDir = CommandLine.arguments.firstIndex(of: "--layers").map { CommandLine.arguments[$0 + 1] }
let fullBleed = CommandLine.arguments.contains("--full") || layersDir != nil
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Apple-Raster: 824 × 824 Fläche mit 100 px Rand, Eckenradius ca. 185.
let inset: CGFloat = fullBleed ? 0 : 100
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius: CGFloat = fullBleed ? 0 : 185
let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

if !fullBleed {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x1C2233)); ctx.fillPath()
    ctx.restoreGState()
}
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let gradient = CGGradient(colorsSpace: cs, colors: [rgb(0x2A3350), rgb(0x161B29)] as CFArray, locations: [0, 1])!
if layersDir == nil { ctx.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: []) }

// Drei Zeitblöcke in Projektfarben, versetzt wie ein Tag im Kalender, dazu eine weiße „Jetzt“-Linie.
// Bewusst kein Ring mit Zeiger mehr, der sah aus wie ein Tacho.
let w = body.width
func pill(_ r: CGRect, _ c: CGColor) {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil))
    ctx.setFillColor(c); ctx.fillPath()
}
let barHeight = w * 0.13, barGap = w * 0.07
let span = w * 0.72
let rows: [(start: CGFloat, length: CGFloat, color: UInt32)] = [(0.0, 0.55, 0xD99A2B), (0.22, 0.60, 0x4F6FF0), (0.48, 0.40, 0x4C9A6A)]
let extent = rows.map { $0.start + $0.length }.max()!
let left = body.midX - span * extent / 2
let stackHeight = 3 * barHeight + 2 * barGap
var y = body.midY + stackHeight / 2 - barHeight
for row in rows {
    pill(CGRect(x: left + span * row.start, y: y, width: span * row.length, height: barHeight), rgb(row.color))
    y -= barHeight + barGap
}
if let layersDir {
    write(ctx.makeImage()!, to: layersDir + "/blocks.png")
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
}
let nowX = left + span * 0.74
let lineWidth = w * 0.028
let overhang = w * 0.07
ctx.setFillColor(rgb(0xF4F6FB))
ctx.fill(CGRect(x: nowX - lineWidth / 2, y: body.midY - stackHeight / 2 - overhang, width: lineWidth, height: stackHeight + 2 * overhang))
let knob = w * 0.045
ctx.fillEllipse(in: CGRect(x: nowX - knob, y: body.midY + stackHeight / 2 + overhang - knob, width: 2 * knob, height: 2 * knob))

if let layersDir {
    write(ctx.makeImage()!, to: layersDir + "/now.png")
    exit(0)
}

// Feiner Lichtrand oben für Tiefe.
ctx.addPath(shape)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(4); ctx.strokePath()
ctx.restoreGState()

write(ctx.makeImage()!, to: CommandLine.arguments[1])
