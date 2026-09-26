// Erzeugt das App-Icon: swift scripts/draw-icon.swift docs/icon.png

import AppKit
import CoreGraphics

// Zeichnet das TOM-Icon: Ring aus drei Projektfarben mit Uhrzeiger, auf Tintenblau.
let size: CGFloat = 1024
let fullBleed = CommandLine.arguments.contains("--full")
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

if !fullBleed {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x1C2233)); ctx.fillPath()
    ctx.restoreGState()
}
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let gradient = CGGradient(colorsSpace: cs, colors: [rgb(0x2A3350), rgb(0x161B29)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])

// Ring: Segmente im Uhrzeigersinn ab 12 Uhr, mit Lücken und runden Enden.
let center = CGPoint(x: size / 2, y: size / 2)
let ringRadius = body.width * 0.30
let lineWidth = body.width * 0.125
let segments: [(UInt32, CGFloat)] = [(0xD99A2B, 0.46), (0x3B5BDB, 0.32), (0x4C9A6A, 0.22)]
let gap: CGFloat = 0.035 // im Bogenmaß, Platz für die runden Enden
var start = CGFloat.pi / 2 // 12 Uhr in CoreGraphics (y nach oben)
ctx.setLineCap(.round)
ctx.setLineWidth(lineWidth)
for (color, share) in segments {
    let sweep = share * 2 * .pi
    let a0 = start - gap - lineWidth / ringRadius / 2
    let a1 = start - sweep + gap + lineWidth / ringRadius / 2
    ctx.setStrokeColor(rgb(color))
    ctx.addArc(center: center, radius: ringRadius, startAngle: a0, endAngle: a1, clockwise: true)
    ctx.strokePath()
    start -= sweep
}

// Uhrzeiger mit Nabe, zeigt auf ca. 2 Uhr.
let handAngle = CGFloat.pi / 2 - 0.95
let handLength = ringRadius * 0.62
let tip = CGPoint(x: center.x + cos(handAngle) * handLength, y: center.y + sin(handAngle) * handLength)
ctx.setStrokeColor(rgb(0xF4F6FB))
ctx.setLineWidth(body.width * 0.052)
ctx.move(to: center); ctx.addLine(to: tip); ctx.strokePath()
let hub = body.width * 0.062
ctx.setFillColor(rgb(0xF4F6FB))
ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: 2 * hub, height: 2 * hub))
ctx.setFillColor(rgb(0x1C2233))
let dot = hub * 0.38
ctx.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: 2 * dot, height: 2 * dot))

// Feiner Lichtrand oben für Tiefe.
ctx.addPath(shape)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(4); ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
