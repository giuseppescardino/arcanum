// Draws the app icon; run generate.sh rather than this directly.
// Usage: draw <mode> <size> <out.png>
// modes: full (square, full bleed), mac (rounded tile with margin and
// shadow), fg (transparent Android adaptive foreground), bg (gradient only)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let mode = args[1]
let size = Int(args[2])!
let out = URL(fileURLWithPath: args[3])
let s = CGFloat(size)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like the design coordinates below.
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

let gradient = CGGradient(
    colorsSpace: space, colors: [rgb(0x5C6BC0), rgb(0x283593)] as CFArray,
    locations: [0, 1])!

func fillBackground(in rect: CGRect) {
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: rect.minX, y: rect.minY),
        end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    ctx.restoreGState()
}

/// Shield centered at (cx, cy) with the given width.
func shieldPath(cx: CGFloat, cy: CGFloat, w: CGFloat) -> CGPath {
    let h = w * 1.18
    let x0 = cx - w / 2, y0 = cy - h / 2
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * w, y: y0 + y * h) }
    let path = CGMutablePath()
    path.move(to: p(0.5, 0))
    path.addCurve(to: p(1, 0.15), control1: p(0.66, 0.1), control2: p(0.84, 0.14))
    path.addLine(to: p(1, 0.46))
    path.addCurve(to: p(0.5, 1), control1: p(1, 0.76), control2: p(0.78, 0.9))
    path.addCurve(to: p(0, 0.46), control1: p(0.22, 0.9), control2: p(0, 0.76))
    path.addLine(to: p(0, 0.15))
    path.addCurve(to: p(0.5, 0), control1: p(0.16, 0.14), control2: p(0.34, 0.1))
    path.closeSubpath()
    return path
}

func drawShield(cx: CGFloat, cy: CGFloat, w: CGFloat) {
    let shield = shieldPath(cx: cx, cy: cy, w: w)
    // Soft drop shadow under the shield.
    ctx.saveGState()
    if mode != "mono" {
        ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.03), blur: w * 0.08,
                      color: rgb(0x1A237E, 0.45))
    }
    ctx.addPath(shield)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    // Right half slightly tinted for depth.
    ctx.saveGState()
    ctx.addPath(shield)
    ctx.clip()
    ctx.setFillColor(rgb(0xE8EAF6))
    ctx.fill(CGRect(x: cx, y: 0, width: s, height: s))
    ctx.restoreGState()
    // Keyhole.
    let h = w * 1.18
    let kcy = cy - h * 0.06
    let r = w * 0.13
    ctx.setFillColor(rgb(0x303F9F))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: kcy - r, width: 2 * r, height: 2 * r))
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: cx - r * 0.42, y: kcy + r * 0.4))
    slot.addLine(to: CGPoint(x: cx + r * 0.42, y: kcy + r * 0.4))
    slot.addLine(to: CGPoint(x: cx + r * 0.7, y: kcy + r * 2.5))
    slot.addLine(to: CGPoint(x: cx - r * 0.7, y: kcy + r * 2.5))
    slot.closeSubpath()
    ctx.addPath(slot)
    ctx.fillPath()
}

switch mode {
case "full":
    fillBackground(in: CGRect(x: 0, y: 0, width: s, height: s))
    drawShield(cx: s / 2, cy: s * 0.5, w: s * 0.5)
case "mac":
    // Apple's macOS grid: 824pt tile in a 1024pt canvas, ~185pt corners.
    let tile = CGRect(x: s * 100 / 1024, y: s * 100 / 1024,
                      width: s * 824 / 1024, height: s * 824 / 1024)
    let rounded = CGPath(roundedRect: tile, cornerWidth: s * 185 / 1024,
                         cornerHeight: s * 185 / 1024, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025,
                  color: rgb(0x000000, 0.35))
    ctx.addPath(rounded)
    ctx.setFillColor(rgb(0x283593))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rounded)
    ctx.clip()
    fillBackground(in: tile)
    ctx.restoreGState()
    drawShield(cx: s / 2, cy: s / 2, w: tile.width * 0.5)
case "fg":
    // Android adaptive icon: 108dp canvas, keep art inside the 66dp circle.
    drawShield(cx: s / 2, cy: s / 2, w: s * 0.36)
case "mono":
    // Themed icon: only the alpha counts, so cut the keyhole out.
    drawShield(cx: s / 2, cy: s / 2, w: s * 0.36)
    ctx.setBlendMode(.clear)
    let w = s * 0.36, h = w * 1.18, cx = s / 2, kcy = s / 2 - h * 0.06, r = w * 0.13
    ctx.fillEllipse(in: CGRect(x: cx - r, y: kcy - r, width: 2 * r, height: 2 * r))
    let cut = CGMutablePath()
    cut.move(to: CGPoint(x: cx - r * 0.42, y: kcy + r * 0.4))
    cut.addLine(to: CGPoint(x: cx + r * 0.42, y: kcy + r * 0.4))
    cut.addLine(to: CGPoint(x: cx + r * 0.7, y: kcy + r * 2.5))
    cut.addLine(to: CGPoint(x: cx - r * 0.7, y: kcy + r * 2.5))
    cut.closeSubpath()
    ctx.addPath(cut)
    ctx.fillPath()
case "bg":
    fillBackground(in: CGRect(x: 0, y: 0, width: s, height: s))
default:
    fatalError("unknown mode \(mode)")
}

let image = ctx.makeImage()!
var final = image
if mode == "full" || mode == "bg" {
    // iOS rejects icons with an alpha channel.
    let opaque = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaque.draw(image, in: CGRect(x: 0, y: 0, width: s, height: s))
    final = opaque.makeImage()!
}
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, final, nil)
CGImageDestinationFinalize(dest)
