#!/usr/bin/env swift
// Generates all game art as PNGs via CoreGraphics.
// Run from the repo root:  swift Tools/generate_sprites.swift
// Writes into NobleStars/Resources/Sprites/ (override with argv[1]).

import Foundation
import CoreGraphics
import ImageIO

// MARK: - Plumbing

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "NobleStars/Resources/Sprites"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let outline = rgba(0.13, 0.11, 0.10)

func render(_ name: String, _ w: Int, _ h: Int, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    draw(ctx)
    let url = URL(fileURLWithPath: "\(outDir)/\(name).png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name).png (\(w)x\(h))")
}

extension CGContext {
    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, fill: CGColor,
                stroke: CGColor? = nil, lw: CGFloat = 3) {
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        setFillColor(fill); fillEllipse(in: rect)
        if let stroke { setStrokeColor(stroke); setLineWidth(lw); strokeEllipse(in: rect) }
    }
    func rounded(_ rect: CGRect, _ radius: CGFloat, fill: CGColor,
                 stroke: CGColor? = nil, lw: CGFloat = 3) {
        let p = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        addPath(p); setFillColor(fill); fillPath()
        if let stroke { addPath(p); setStrokeColor(stroke); setLineWidth(lw); strokePath() }
    }
    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
              _ color: CGColor, _ lw: CGFloat) {
        setStrokeColor(color); setLineWidth(lw)
        move(to: CGPoint(x: x1, y: y1)); addLine(to: CGPoint(x: x2, y: y2)); strokePath()
    }
}

/// Deterministic pseudo-random for tile noise.
struct LCG {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

// MARK: - Shared character pieces

struct Face {
    let skin: CGColor
    /// Draws eyes + smile centered on (cx, cy) for a head of radius r.
    func draw(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        let eyeY = cy - r * 0.05
        let dx = r * 0.38
        for side: CGFloat in [-1, 1] {
            c.circle(cx + side * dx, eyeY, r * 0.11, fill: outline)
            c.circle(cx + side * dx + r * 0.035, eyeY + r * 0.035, r * 0.035, fill: rgba(1, 1, 1))
        }
        // Smile
        c.setStrokeColor(outline); c.setLineWidth(max(2.5, r * 0.06))
        c.addArc(center: CGPoint(x: cx, y: cy - r * 0.28), radius: r * 0.28,
                 startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        c.strokePath()
    }
}

let henrySkin = rgba(0.96, 0.80, 0.66)
let tonySkin = rgba(0.93, 0.76, 0.60)
let henryHairColor = rgba(0.76, 0.58, 0.38)
let tonyHairColor = rgba(0.22, 0.18, 0.15)
let henryVest = rgba(0.72, 0.68, 0.62)
let henryVestLight = rgba(0.83, 0.80, 0.75)
let tonyHoodie = rgba(0.63, 0.64, 0.67)
let sageShorts = rgba(0.66, 0.74, 0.60)
let tonyPants = rgba(0.24, 0.24, 0.27)
let novaSuit = rgba(0.25, 0.75, 0.95)
let novaSuitDark = rgba(0.16, 0.52, 0.70)

/// Curly hair: a crown of overlapping circles.
func henryHair(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
    let curls: [(CGFloat, CGFloat, CGFloat)] = [
        (-0.85, 0.45, 0.34), (-0.55, 0.80, 0.38), (-0.18, 0.95, 0.40),
        (0.22, 0.93, 0.38), (0.58, 0.76, 0.36), (0.86, 0.42, 0.32),
        (-0.98, 0.05, 0.24), (0.98, 0.02, 0.22),
    ]
    for (fx, fy, fr) in curls {
        c.circle(cx + fx * r, cy + fy * r, fr * r, fill: henryHairColor, stroke: outline, lw: 3)
    }
    // Fill gaps between curls
    for (fx, fy, fr) in curls {
        c.circle(cx + fx * r, cy + fy * r, fr * r, fill: henryHairColor)
    }
}

/// Straight dark hair with a full fringe.
func tonyHair(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
    // Cap covering the top of the head
    c.setFillColor(tonyHairColor)
    c.addArc(center: CGPoint(x: cx, y: cy), radius: r + 2,
             startAngle: .pi * 0.02, endAngle: .pi * 0.98, clockwise: false)
    c.closePath(); c.fillPath()
    // Fringe: a band with a softly scalloped bottom edge
    let top = cy + r * 0.30
    c.move(to: CGPoint(x: cx - r - 2, y: cy))
    c.addLine(to: CGPoint(x: cx - r - 2, y: top))
    c.addLine(to: CGPoint(x: cx + r + 2, y: top))
    c.addLine(to: CGPoint(x: cx + r + 2, y: cy))
    var x = cx + r
    while x > cx - r {
        c.addArc(center: CGPoint(x: x - r * 0.16, y: cy + r * 0.16), radius: r * 0.17,
                 startAngle: 0, endAngle: .pi, clockwise: false)
        x -= r * 0.33
    }
    c.closePath(); c.fillPath()
    // Outline pass
    c.setStrokeColor(outline); c.setLineWidth(3)
    c.addArc(center: CGPoint(x: cx, y: cy), radius: r + 2,
             startAngle: .pi * 0.02, endAngle: .pi * 0.98, clockwise: false)
    c.strokePath()
}

/// Nova: simple star-visor helmet.
func novaHelmet(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
    c.circle(cx, cy, r + 3, fill: novaSuit, stroke: outline, lw: 3.5)
    // Visor
    let visor = CGRect(x: cx - r * 0.72, y: cy - r * 0.45, width: r * 1.44, height: r * 0.95)
    c.rounded(visor, r * 0.4, fill: rgba(0.92, 0.97, 1.0), stroke: outline, lw: 3)
    // Star on the helmet crown
    starPath(c, cx, cy + r * 0.72, r * 0.22)
    c.setFillColor(rgba(1.0, 0.85, 0.25)); c.fillPath()
}

func starPath(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
    for i in 0..<10 {
        let angle = CGFloat(i) * .pi / 5 - .pi / 2
        let radius = i.isMultiple(of: 2) ? r : r * 0.45
        let p = CGPoint(x: cx + cos(angle) * radius, y: cy - sin(angle) * radius)
        i == 0 ? c.move(to: p) : c.addLine(to: p)
    }
    c.closePath()
}

// MARK: - Portraits (menu cards) 240x280

func portraitHenry(_ c: CGContext) {
    let cx: CGFloat = 120
    // Torso: open fuzzy vest over bare chest
    c.rounded(CGRect(x: 45, y: -30, width: 150, height: 140), 40,
              fill: henrySkin, stroke: outline, lw: 3.5)
    for side: CGFloat in [-1, 1] {   // vest panels
        let x = cx + side * 52 - 26
        c.rounded(CGRect(x: x, y: -30, width: 52, height: 138), 22,
                  fill: henryVest, stroke: outline, lw: 3.5)
        // fluffy inner edge
        var y: CGFloat = -14
        while y < 96 {
            c.circle(cx + side * 28, y, 9, fill: henryVestLight)
            y += 17
        }
    }
    // Oar over the right shoulder, blade peeking up top-right
    c.saveGState()
    c.translateBy(x: 196, y: 92); c.rotate(by: -0.22)
    c.rounded(CGRect(x: -8, y: -80, width: 14, height: 170), 7,
              fill: rgba(0.72, 0.52, 0.30), stroke: outline, lw: 3)
    c.rounded(CGRect(x: -16, y: 88, width: 30, height: 68), 12,
              fill: rgba(0.35, 0.48, 0.90), stroke: outline, lw: 3)
    c.line(-1, 100, -1, 144, rgba(0.95, 0.97, 1.0), 5)
    c.restoreGState()
    // Head
    let cy: CGFloat = 178, r: CGFloat = 60
    c.circle(cx, cy, r, fill: henrySkin, stroke: outline, lw: 3.5)
    henryHair(c, cx, cy, r)
    Face(skin: henrySkin).draw(c, cx, cy, r)
}

func portraitTony(_ c: CGContext) {
    let cx: CGFloat = 120
    // Racket over the left shoulder, head peeking up top-left
    c.saveGState()
    c.translateBy(x: 44, y: 96); c.rotate(by: 0.26)
    c.rounded(CGRect(x: -6, y: -60, width: 12, height: 130), 6,
              fill: rgba(0.30, 0.30, 0.34), stroke: outline, lw: 3)
    let head = CGRect(x: -26, y: 62, width: 52, height: 74)
    c.setFillColor(rgba(0.98, 0.98, 0.95)); c.fillEllipse(in: head)
    c.setStrokeColor(rgba(0.75, 0.20, 0.18)); c.setLineWidth(7); c.strokeEllipse(in: head)
    c.setStrokeColor(rgba(0.65, 0.65, 0.62)); c.setLineWidth(1.5)
    for i in 1..<4 {
        let x = head.minX + head.width * CGFloat(i) / 4
        c.move(to: CGPoint(x: x, y: head.minY + 4)); c.addLine(to: CGPoint(x: x, y: head.maxY - 4)); c.strokePath()
        let y = head.minY + head.height * CGFloat(i) / 4
        c.move(to: CGPoint(x: head.minX + 4, y: y)); c.addLine(to: CGPoint(x: head.maxX - 4, y: y)); c.strokePath()
    }
    c.restoreGState()
    // Hoodie torso
    c.rounded(CGRect(x: 40, y: -30, width: 160, height: 142), 42,
              fill: tonyHoodie, stroke: outline, lw: 3.5)
    // Hood behind neck
    c.rounded(CGRect(x: 78, y: 92, width: 84, height: 30), 15,
              fill: rgba(0.55, 0.56, 0.59), stroke: outline, lw: 3)
    // Drawstrings
    c.line(106, 96, 103, 62, outline, 3.5)
    c.line(134, 96, 137, 62, outline, 3.5)
    // Team badge: ring + star + tennis ball
    c.circle(cx, 46, 30, fill: rgba(0.94, 0.95, 0.97), stroke: rgba(0.16, 0.22, 0.38), lw: 6)
    starPath(c, cx, 50, 12)
    c.setFillColor(rgba(0.16, 0.22, 0.38)); c.fillPath()
    c.circle(cx + 16, 30, 8, fill: rgba(0.85, 0.95, 0.30), stroke: outline, lw: 2)
    // Head
    let cy: CGFloat = 180, r: CGFloat = 58
    c.circle(cx, cy, r, fill: tonySkin, stroke: outline, lw: 3.5)
    Face(skin: tonySkin).draw(c, cx, cy, r)
    tonyHair(c, cx, cy, r)
}

func portraitNova(_ c: CGContext) {
    let cx: CGFloat = 120
    c.rounded(CGRect(x: 48, y: -30, width: 144, height: 136), 40,
              fill: novaSuit, stroke: outline, lw: 3.5)
    c.rounded(CGRect(x: 96, y: 10, width: 48, height: 52), 12,
              fill: rgba(0.92, 0.97, 1.0), stroke: outline, lw: 3)
    starPath(c, cx, 38, 15)
    c.setFillColor(rgba(1.0, 0.85, 0.25)); c.fillPath()
    novaHelmet(c, cx, 178, 58)
    // Eyes behind visor
    Face(skin: novaSuit).draw(c, cx, 172, 52)
}

// MARK: - In-game bodies 88x100 (drawn small, ~44x50pt in game)

func bodyCommon(_ c: CGContext, torso: CGColor, legs: CGColor, skin: CGColor,
                hair: (CGContext, CGFloat, CGFloat, CGFloat) -> Void,
                helmet: Bool = false) {
    // Legs
    for side: CGFloat in [-1, 1] {
        c.rounded(CGRect(x: 44 + side * 15 - 9, y: 0, width: 18, height: 20), 7,
                  fill: legs, stroke: outline, lw: 3)
    }
    // Torso
    c.rounded(CGRect(x: 20, y: 12, width: 48, height: 36), 15,
              fill: torso, stroke: outline, lw: 3)
    // Head
    let cy: CGFloat = 68, r: CGFloat = 26
    c.circle(44, cy, r, fill: skin, stroke: outline, lw: 3)
    if helmet {
        novaHelmet(c, 44, cy, r - 2)
        Face(skin: skin).draw(c, 44, cy - 3, r * 0.82)
    } else {
        Face(skin: skin).draw(c, 44, cy, r)
        hair(c, 44, cy, r)
    }
}

// MARK: - Weapons (pointing right; anchor near the left/grip end)

func weaponRacket(_ c: CGContext) {
    c.rounded(CGRect(x: 0, y: 12, width: 44, height: 12), 6,
              fill: rgba(0.30, 0.30, 0.34), stroke: outline, lw: 2.5)
    let head = CGRect(x: 40, y: 2, width: 56, height: 32)
    c.setFillColor(rgba(0.98, 0.98, 0.95)); c.fillEllipse(in: head)
    c.setStrokeColor(rgba(0.75, 0.20, 0.18)); c.setLineWidth(5); c.strokeEllipse(in: head)
    c.setStrokeColor(rgba(0.65, 0.65, 0.62)); c.setLineWidth(1.2)
    for i in 1..<4 {
        let x = head.minX + head.width * CGFloat(i) / 4
        c.move(to: CGPoint(x: x, y: head.minY + 3)); c.addLine(to: CGPoint(x: x, y: head.maxY - 3)); c.strokePath()
    }
    for i in 1..<3 {
        let y = head.minY + head.height * CGFloat(i) / 3
        c.move(to: CGPoint(x: head.minX + 4, y: y)); c.addLine(to: CGPoint(x: head.maxX - 4, y: y)); c.strokePath()
    }
}

func weaponPaddle(_ c: CGContext) {
    c.rounded(CGRect(x: 0, y: 9, width: 76, height: 10), 5,
              fill: rgba(0.72, 0.52, 0.30), stroke: outline, lw: 2.5)
    c.rounded(CGRect(x: 72, y: 1, width: 44, height: 26), 11,
              fill: rgba(0.35, 0.48, 0.90), stroke: outline, lw: 2.5)
    c.line(80, 14, 108, 14, rgba(0.95, 0.97, 1.0), 4)
}

func weaponShotgun(_ c: CGContext) {
    c.rounded(CGRect(x: 0, y: 6, width: 34, height: 14), 5,
              fill: rgba(0.55, 0.38, 0.22), stroke: outline, lw: 2.5)
    c.rounded(CGRect(x: 28, y: 13, width: 58, height: 7), 3,
              fill: rgba(0.35, 0.36, 0.40), stroke: outline, lw: 2)
    c.rounded(CGRect(x: 28, y: 4, width: 58, height: 7), 3,
              fill: rgba(0.42, 0.43, 0.47), stroke: outline, lw: 2)
}

// MARK: - Environment tiles

func grassTile(_ c: CGContext, base: CGColor, seed: UInt64) {
    c.setFillColor(base); c.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    var rng = LCG(state: seed)
    for _ in 0..<18 {
        let x = rng.next() * 122 + 3
        let y = rng.next() * 118 + 3
        let dark = rng.next() > 0.5
        let blade = dark ? rgba(0, 0, 0, 0.08) : rgba(1, 1, 1, 0.10)
        c.line(x, y, x + rng.next() * 3 - 1.5, y + 5 + rng.next() * 4, blade, 2.5)
    }
}

func wallTopTile(_ c: CGContext) {
    c.setFillColor(rgba(0.63, 0.47, 0.33)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    // Bevel: light top/left, dark bottom/right
    c.setFillColor(rgba(1, 1, 1, 0.16)); c.fill(CGRect(x: 0, y: 118, width: 128, height: 10))
    c.setFillColor(rgba(1, 1, 1, 0.10)); c.fill(CGRect(x: 0, y: 0, width: 8, height: 128))
    c.setFillColor(rgba(0, 0, 0, 0.16)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 9))
    c.setFillColor(rgba(0, 0, 0, 0.10)); c.fill(CGRect(x: 120, y: 0, width: 8, height: 128))
    var rng = LCG(state: 77)
    for _ in 0..<9 {  // pebbles/speckles
        let x = rng.next() * 100 + 14
        let y = rng.next() * 96 + 16
        c.circle(x, y, 3.5 + rng.next() * 3, fill: rgba(0, 0, 0, 0.10))
    }
}

func wallFrontTile(_ c: CGContext) {
    c.setFillColor(rgba(0.45, 0.32, 0.22)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 48))
    c.setFillColor(rgba(0, 0, 0, 0.18)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 7))
    var rng = LCG(state: 55)
    for _ in 0..<5 {
        let x = rng.next() * 118 + 5
        c.line(x, 8 + rng.next() * 8, x + rng.next() * 4 - 2, 40, rgba(0, 0, 0, 0.13), 3)
    }
}

func waterTile(_ c: CGContext) {
    c.setFillColor(rgba(0.30, 0.55, 0.85)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    c.setStrokeColor(rgba(1, 1, 1, 0.28)); c.setLineWidth(4)
    for (x, y) in [(18, 96), (70, 76), (34, 40), (88, 22)] {
        c.addArc(center: CGPoint(x: x, y: y), radius: 14,
                 startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        c.strokePath()
    }
    c.setFillColor(rgba(0, 0, 0, 0.07)); c.fill(CGRect(x: 0, y: 0, width: 128, height: 10))
}

func bushSprite(_ c: CGContext) {
    let dark = rgba(0.20, 0.46, 0.19)
    let mid = rgba(0.25, 0.53, 0.22)
    let light = rgba(0.34, 0.62, 0.28)
    let clumps: [(CGFloat, CGFloat, CGFloat)] = [
        (48, 58, 40), (102, 58, 40), (75, 46, 38), (75, 88, 44), (44, 92, 34), (106, 92, 34),
    ]
    for (x, y, r) in clumps { c.circle(x, y, r, fill: mid, stroke: outline, lw: 3.5) }
    for (x, y, r) in clumps { c.circle(x, y, r, fill: mid) }
    for (x, y, r) in clumps { c.circle(x - r * 0.2, y + r * 0.25, r * 0.5, fill: light) }
    c.circle(75, 66, 20, fill: dark)
}

func crateSprite(_ c: CGContext) {
    c.rounded(CGRect(x: 3, y: 3, width: 78, height: 78), 10,
              fill: rgba(0.80, 0.60, 0.26), stroke: outline, lw: 4)
    c.line(6, 30, 78, 30, rgba(0, 0, 0, 0.14), 3)
    c.line(6, 56, 78, 56, rgba(0, 0, 0, 0.14), 3)
    c.rounded(CGRect(x: 34, y: 4, width: 16, height: 76), 3,
              fill: rgba(0.56, 0.40, 0.16), stroke: outline, lw: 2.5)
    c.rounded(CGRect(x: 4, y: 34, width: 76, height: 16), 3,
              fill: rgba(0.56, 0.40, 0.16), stroke: outline, lw: 2.5)
}

// MARK: - Generate everything

render("portrait_henry", 240, 280) { portraitHenry($0) }
render("portrait_tony", 240, 280) { portraitTony($0) }
render("portrait_nova", 240, 280) { portraitNova($0) }

render("body_henry", 88, 100) { c in
    bodyCommon(c, torso: henryVest, legs: sageShorts, skin: henrySkin,
               hair: { henryHair($0, $1, $2, $3) })
}
render("body_tony", 88, 100) { c in
    bodyCommon(c, torso: tonyHoodie, legs: tonyPants, skin: tonySkin,
               hair: { tonyHair($0, $1, $2, $3) })
}
render("body_nova", 88, 100) { c in
    bodyCommon(c, torso: novaSuit, legs: novaSuitDark, skin: henrySkin,
               hair: { _, _, _, _ in }, helmet: true)
}

render("weapon_racket", 100, 36) { weaponRacket($0) }
render("weapon_paddle", 120, 28) { weaponPaddle($0) }
render("weapon_shotgun", 90, 26) { weaponShotgun($0) }

render("tile_grass_light", 128, 128) { grassTile($0, base: rgba(0.55, 0.75, 0.35), seed: 11) }
render("tile_grass_dark", 128, 128) { grassTile($0, base: rgba(0.51, 0.71, 0.32), seed: 29) }
render("wall_top", 128, 128) { wallTopTile($0) }
render("wall_front", 128, 48) { wallFrontTile($0) }
render("tile_water", 128, 128) { waterTile($0) }
render("bush", 150, 130) { bushSprite($0) }
render("crate", 84, 84) { crateSprite($0) }

print("done.")
