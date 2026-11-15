import Foundation
import SpriteKit
import CoreGraphics

enum SoldierPose: Int {
    case idle = 0
    case marchA = 1
    case marchB = 2
    case aim = 3
    case dizzy = 4
}

@MainActor
final class SpriteFactory {
    static let shared = SpriteFactory()
    private var cache: [String: SKTexture] = [:]

    private init() {}

    func clearCache() {
        cache.removeAll()
    }

    private func cached(_ key: String, width: Int, height: Int, pixelArt: Bool, draw: (CGContext, CGFloat, CGFloat) -> Void) -> SKTexture {
        let fullKey = "\(key)_\(pixelArt ? "c64" : "hd")"
        if let existing = cache[fullKey] {
            return existing
        }
        let scale = pixelArt ? 1 : 2
        let pw = max(4, width * scale)
        let ph = max(4, height * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pw,
            height: ph,
            bitsPerComponent: 8,
            bytesPerRow: pw * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SKTexture()
        }
        ctx.clear(CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        if pixelArt {
            ctx.setShouldAntialias(false)
            ctx.interpolationQuality = .none
        } else {
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high
        }
        draw(ctx, CGFloat(width), CGFloat(height))
        guard let cg = ctx.makeImage() else { return SKTexture() }
        let tex = SKTexture(cgImage: cg)
        tex.filteringMode = pixelArt ? .nearest : .linear
        cache[fullKey] = tex
        return tex
    }

    // MARK: - Comic / C64 Soldier Sprite (Facing Right by Default)

    func soldierTexture(faction: Faction, pose: SoldierPose, c64: Bool) -> SKTexture {
        cached("soldier_\(faction.rawValue)_\(pose.rawValue)", width: 44, height: 52, pixelArt: c64) { ctx, w, h in
            let coat = c64
                ? (faction == .unionBlue ? Palette.c64Blue : Palette.c64MidGrey)
                : (faction == .unionBlue ? SKColor.hex(0x1E56D8) : SKColor.hex(0x6E7F99))
            let pants = c64
                ? (faction == .unionBlue ? Palette.c64LightBlue : Palette.c64LightGrey)
                : (faction == .unionBlue ? SKColor.hex(0x4B8DF8) : SKColor.hex(0x95A6C2))
            let trim = c64 ? Palette.c64Yellow : Palette.brassGold
            let skin = c64 ? Palette.c64LightRed : SKColor.hex(0xFFCC9E)
            let ink  = c64 ? Palette.c64Black : SKColor.hex(0x101522)
            let wood = c64 ? Palette.c64Brown : SKColor.hex(0x8B5228)
            let steel = c64 ? Palette.c64White : SKColor.hex(0xDCE6F7)

            func fillRect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ col: SKColor, stroke: Bool = true) {
                let r = CGRect(x: x, y: y, width: rw, height: rh)
                ctx.setFillColor(col.cgColor)
                if c64 {
                    ctx.fill(r)
                } else {
                    let p = CGPath(roundedRect: r, cornerWidth: min(rw, rh) * 0.28, cornerHeight: min(rw, rh) * 0.28, transform: nil)
                    ctx.addPath(p)
                    ctx.fillPath()
                    if stroke {
                        ctx.setStrokeColor(ink.cgColor)
                        ctx.setLineWidth(1.6)
                        ctx.addPath(p)
                        ctx.strokePath()
                    }
                }
            }

            if pose == .dizzy {
                // Sitting slapstick soldier with popped kepi and stars
                fillRect(10, 6, 18, 8, pants)
                fillRect(24, 6, 8, 7, ink) // boots
                fillRect(11, 12, 16, 15, coat)
                // Head tilted
                fillRect(12, 26, 14, 13, skin)
                // Popped kepi floating above
                fillRect(10, 42, 16, 6, coat)
                fillRect(22, 42, 7, 3, ink)
                // Golden comic stars
                ctx.setFillColor(trim.cgColor)
                ctx.fillEllipse(in: CGRect(x: 5, y: 36, width: 5, height: 5))
                ctx.fillEllipse(in: CGRect(x: 30, y: 38, width: 5, height: 5))
                ctx.fillEllipse(in: CGRect(x: 20, y: 48, width: 4, height: 4))
                return
            }

            // Legs & Boots
            let strideA: CGFloat = pose == .marchA ? -4 : (pose == .marchB ? 4 : 0)
            fillRect(15 + strideA, 4, 6, 13, pants)
            fillRect(22 - strideA, 4, 6, 13, pants)
            fillRect(14 + strideA, 2, 8, 5, ink)
            fillRect(21 - strideA, 2, 8, 5, ink)

            // Torso Coat + Brass Buttons
            fillRect(13, 15, 17, 17, coat)
            ctx.setFillColor(trim.cgColor)
            ctx.fill(CGRect(x: 13, y: 20, width: 17, height: 2.5)) // belt
            ctx.fillEllipse(in: CGRect(x: 23, y: 25, width: 3.5, height: 3.5))
            ctx.fillEllipse(in: CGRect(x: 23, y: 29, width: 3.5, height: 3.5))

            // Comic Head + Mustache + Kepi Cap
            fillRect(14, 31, 15, 13, skin)
            ctx.setFillColor(ink.cgColor)
            ctx.fillEllipse(in: CGRect(x: 24, y: 37, width: 2.6, height: 2.6)) // eye
            ctx.fill(CGRect(x: 23, y: 33, width: 7, height: 2.2)) // comic mustache

            // Kepi Cap + Visor + Emblem
            fillRect(12, 42, 17, 7, coat)
            fillRect(25, 42, 8, 3, ink) // visor
            ctx.setFillColor(trim.cgColor)
            ctx.fillEllipse(in: CGRect(x: 20, y: 44, width: 4, height: 4))

            // Musket / Rifle & Arms
            if pose == .aim {
                fillRect(20, 24, 18, 4, wood)
                fillRect(30, 26, 13, 2.5, steel, stroke: false)
                fillRect(18, 22, 10, 5, coat)
            } else {
                // Diagonal musket across chest
                ctx.saveGState()
                ctx.translateBy(x: 22, y: 22)
                ctx.rotate(by: 0.48)
                fillRect(-3, -6, 5, 22, wood)
                fillRect(-2, 14, 3, 11, steel, stroke: false)
                ctx.restoreGState()
                fillRect(17, 19, 8, 6, coat)
            }
        }
    }

    // MARK: - Cavalry Horse + Saber Trooper (Facing Right)

    func cavalryTexture(faction: Faction, gallopFrame: Int, c64: Bool) -> SKTexture {
        cached("cavalry_\(faction.rawValue)_\(gallopFrame)", width: 72, height: 62, pixelArt: c64) { ctx, w, h in
            let coat = c64
                ? (faction == .unionBlue ? Palette.c64Blue : Palette.c64MidGrey)
                : (faction == .unionBlue ? SKColor.hex(0x1E56D8) : SKColor.hex(0x6E7F99))
            let horse = c64
                ? (faction == .unionBlue ? Palette.c64Brown : Palette.c64White)
                : (faction == .unionBlue ? SKColor.hex(0x9E5D30) : SKColor.hex(0xEEF3FA))
            let mane = c64 ? Palette.c64DarkGrey : SKColor.hex(0x3B2516)
            let trim = c64 ? Palette.c64Yellow : Palette.brassGold
            let skin = c64 ? Palette.c64LightRed : SKColor.hex(0xFFCC9E)
            let steel = c64 ? Palette.c64White : SKColor.hex(0xEAF2FF)
            let ink = c64 ? Palette.c64Black : SKColor.hex(0x101522)

            func box(_ x: CGFloat, _ y: CGFloat, _ bw: CGFloat, _ bh: CGFloat, _ col: SKColor) {
                let r = CGRect(x: x, y: y, width: bw, height: bh)
                ctx.setFillColor(col.cgColor)
                if c64 {
                    ctx.fill(r)
                } else {
                    let p = CGPath(roundedRect: r, cornerWidth: min(bw, bh) * 0.3, cornerHeight: min(bw, bh) * 0.3, transform: nil)
                    ctx.addPath(p)
                    ctx.fillPath()
                    ctx.setStrokeColor(ink.cgColor)
                    ctx.setLineWidth(1.6)
                    ctx.addPath(p)
                    ctx.strokePath()
                }
            }

            let kick: CGFloat = gallopFrame == 0 ? 5 : -4
            // Horse legs
            box(14 - kick, 3, 6, 15, horse)
            box(23 + kick, 4, 6, 14, horse)
            box(42 - kick, 4, 6, 15, horse)
            box(51 + kick, 5, 6, 14, horse)
            // Tail
            box(5, 20, 9, 10, mane)
            // Horse body + saddle blanket
            box(13, 15, 42, 18, horse)
            box(25, 21, 18, 11, trim)
            // Horse neck & head
            box(47, 25, 13, 18, horse)
            box(53, 33, 14, 10, horse)
            ctx.setFillColor(ink.cgColor)
            ctx.fillEllipse(in: CGRect(x: 59, y: 38, width: 2.8, height: 2.8))

            // Rider
            box(28, 28, 14, 16, coat)
            box(29, 43, 12, 11, skin)
            box(27, 52, 15, 6, coat)
            // Raised gleaming saber!
            ctx.saveGState()
            ctx.translateBy(x: 40, y: 42)
            ctx.rotate(by: gallopFrame == 0 ? 0.55 : 0.20)
            ctx.setFillColor(trim.cgColor)
            ctx.fill(CGRect(x: -2, y: -2, width: 5, height: 5))
            ctx.setFillColor(steel.cgColor)
            ctx.fill(CGRect(x: 0, y: 3, width: 3.5, height: 19))
            ctx.restoreGState()
        }
    }

    // MARK: - Brass Field Cannon (Facing Right)

    func cannonTexture(faction: Faction, c64: Bool) -> SKTexture {
        cached("cannon_\(faction.rawValue)", width: 68, height: 48, pixelArt: c64) { ctx, w, h in
            let brass = c64 ? Palette.c64Yellow : Palette.brassGold
            let brassDark = c64 ? Palette.c64Orange : SKColor.hex(0xC98A1E)
            let wood = c64 ? Palette.c64Brown : SKColor.hex(0x7C4822)
            let ink = c64 ? Palette.c64Black : SKColor.hex(0x101522)
            let rim = c64 ? Palette.c64LightGrey : SKColor.hex(0xBCC8DC)

            // Gun carriage trail
            ctx.setFillColor(wood.cgColor)
            ctx.fill(CGRect(x: 6, y: 12, width: 34, height: 8))
            if !c64 {
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(1.8)
                ctx.stroke(CGRect(x: 6, y: 12, width: 34, height: 8))
            }

            // Brass Barrel tilted slightly up
            ctx.saveGState()
            ctx.translateBy(x: 26, y: 24)
            ctx.rotate(by: 0.16)
            let barrelRect = CGRect(x: -10, y: -6, width: 42, height: 12)
            ctx.setFillColor(brass.cgColor)
            ctx.fill(barrelRect)
            ctx.setFillColor(brassDark.cgColor)
            ctx.fill(CGRect(x: -10, y: -6, width: 42, height: 4))
            ctx.fillEllipse(in: CGRect(x: -14, y: -4, width: 6, height: 8)) // cascabel knob
            ctx.fill(CGRect(x: 29, y: -7.5, width: 5, height: 15)) // muzzle flare
            if !c64 {
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(1.8)
                ctx.stroke(barrelRect)
            }
            ctx.restoreGState()

            // Spoked Carriage Wheel
            let wheelRect = CGRect(x: 16, y: 4, width: 26, height: 26)
            ctx.setStrokeColor(rim.cgColor)
            ctx.setLineWidth(c64 ? 3.0 : 4.0)
            ctx.strokeEllipse(in: wheelRect)
            ctx.setStrokeColor(wood.cgColor)
            ctx.setLineWidth(2.2)
            let cx: CGFloat = 29, cy: CGFloat = 17
            for a in stride(from: 0.0, to: Double.pi, by: Double.pi / 4.0) {
                let dx = CGFloat(cos(a)) * 11
                let dy = CGFloat(sin(a)) * 11
                ctx.move(to: CGPoint(x: cx - dx, y: cy - dy))
                ctx.addLine(to: CGPoint(x: cx + dx, y: cy + dy))
            }
            ctx.strokePath()
            ctx.setFillColor(brass.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8))
        }
    }

    // MARK: - 1860s Steam Locomotive & Rolling Stock (Facing Right)

    func locomotiveTexture(c64: Bool) -> SKTexture {
        cached("locomotive", width: 210, height: 108, pixelArt: c64) { ctx, w, h in
            let iron = c64 ? Palette.c64DarkGrey : SKColor.hex(0x232B3A)
            let cabWood = c64 ? Palette.c64Red : SKColor.hex(0x9E3426)
            let brass = c64 ? Palette.c64Yellow : Palette.brassGold
            let redCow = c64 ? Palette.c64LightRed : SKColor.hex(0xD93829)
            let ink = c64 ? Palette.c64Black : SKColor.hex(0x0E131F)

            // Red Cowcatcher at front (right)
            ctx.setFillColor(redCow.cgColor)
            ctx.move(to: CGPoint(x: 178, y: 16))
            ctx.addLine(to: CGPoint(x: 206, y: 16))
            ctx.addLine(to: CGPoint(x: 184, y: 38))
            ctx.closePath()
            ctx.fillPath()

            // Chassis beam
            ctx.setFillColor(redCow.cgColor)
            ctx.fill(CGRect(x: 10, y: 18, width: 174, height: 10))

            // Engineer Cab (left)
            ctx.setFillColor(cabWood.cgColor)
            ctx.fill(CGRect(x: 12, y: 28, width: 58, height: 52))
            ctx.setFillColor(SKColor.hex(0xFFE38E).cgColor)
            ctx.fill(CGRect(x: 24, y: 48, width: 16, height: 20))
            ctx.fill(CGRect(x: 46, y: 48, width: 14, height: 20))
            ctx.setFillColor(iron.cgColor)
            ctx.fill(CGRect(x: 6, y: 78, width: 68, height: 7))

            // Boiler + Brass Bands
            ctx.setFillColor(iron.cgColor)
            ctx.fill(CGRect(x: 70, y: 30, width: 108, height: 38))
            ctx.setFillColor(brass.cgColor)
            for bx in [88, 118, 148] as [CGFloat] {
                ctx.fill(CGRect(x: bx, y: 30, width: 4, height: 38))
            }
            // Steam dome + Brass Bell
            ctx.fill(CGRect(x: 102, y: 68, width: 20, height: 16))
            ctx.fillEllipse(in: CGRect(x: 102, y: 78, width: 20, height: 12))
            ctx.fillEllipse(in: CGRect(x: 136, y: 68, width: 12, height: 12))

            // Balloon Smokestack
            ctx.setFillColor(iron.cgColor)
            ctx.move(to: CGPoint(x: 156, y: 68))
            ctx.addLine(to: CGPoint(x: 170, y: 68))
            ctx.addLine(to: CGPoint(x: 178, y: 98))
            ctx.addLine(to: CGPoint(x: 148, y: 98))
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(brass.cgColor)
            ctx.fill(CGRect(x: 148, y: 96, width: 30, height: 4))

            // Headlamp
            ctx.setFillColor(brass.cgColor)
            ctx.fill(CGRect(x: 176, y: 54, width: 14, height: 16))
            ctx.setFillColor(SKColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: 184, y: 56, width: 7, height: 12))

            // Big Red Drive Wheels + Lead Trucks
            for wx in [30, 68] as [CGFloat] {
                ctx.setFillColor(redCow.cgColor)
                ctx.fillEllipse(in: CGRect(x: wx, y: 2, width: 30, height: 30))
                ctx.setStrokeColor(brass.cgColor)
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: CGRect(x: wx + 2, y: 4, width: 26, height: 26))
            }
            for sx in [128, 156] as [CGFloat] {
                ctx.setFillColor(iron.cgColor)
                ctx.fillEllipse(in: CGRect(x: sx, y: 4, width: 18, height: 18))
                ctx.setStrokeColor(brass.cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: sx + 1, y: 5, width: 16, height: 16))
            }
            // Piston Rod
            ctx.setFillColor(SKColor.hex(0xDCE6F7).cgColor)
            ctx.fill(CGRect(x: 42, y: 15, width: 76, height: 4))

            if !c64 {
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(2)
                ctx.stroke(CGRect(x: 12, y: 28, width: 58, height: 52))
                ctx.stroke(CGRect(x: 70, y: 30, width: 108, height: 38))
            }
        }
    }

    func boxcarTexture(isPaymasterGold: Bool, c64: Bool) -> SKTexture {
        cached("boxcar_\(isPaymasterGold ? "gold" : "std")", width: 168, height: 84, pixelArt: c64) { ctx, w, h in
            let body = c64
                ? (isPaymasterGold ? Palette.c64Orange : Palette.c64Red)
                : (isPaymasterGold ? SKColor.hex(0x8D5524) : SKColor.hex(0x7B3A2D))
            let trim = c64 ? Palette.c64Yellow : Palette.brassGold
            let roof = c64 ? Palette.c64DarkGrey : SKColor.hex(0x2B3344)
            let ink = c64 ? Palette.c64Black : SKColor.hex(0x101522)

            // Wheels
            for wx in [22, 46, 108, 132] as [CGFloat] {
                ctx.setFillColor(roof.cgColor)
                ctx.fillEllipse(in: CGRect(x: wx, y: 4, width: 18, height: 18))
                ctx.setStrokeColor(trim.cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: wx + 2, y: 6, width: 14, height: 14))
            }

            // Car body
            ctx.setFillColor(body.cgColor)
            ctx.fill(CGRect(x: 8, y: 20, width: 152, height: 52))
            ctx.setFillColor(roof.cgColor)
            ctx.fill(CGRect(x: 4, y: 70, width: 160, height: 8))

            // Vertical wood slats & sliding door
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(1.5)
            for sx in stride(from: 20 as CGFloat, through: 148, by: 16) {
                ctx.move(to: CGPoint(x: sx, y: 20))
                ctx.addLine(to: CGPoint(x: sx, y: 70))
            }
            ctx.strokePath()

            // Paymaster Gold Bullion emblem
            if isPaymasterGold {
                ctx.setFillColor(trim.cgColor)
                ctx.fill(CGRect(x: 58, y: 34, width: 52, height: 24))
                ctx.setStrokeColor(ink.cgColor)
                ctx.stroke(CGRect(x: 58, y: 34, width: 52, height: 24))
            }
        }
    }

    // MARK: - Fort Assault & Map Icons

    func tntBarrelTexture(c64: Bool) -> SKTexture {
        cached("tnt_barrel", width: 34, height: 34, pixelArt: c64) { ctx, w, h in
            let wood = c64 ? Palette.c64Orange : SKColor.hex(0x9E5D2B)
            let red = c64 ? Palette.c64Red : SKColor.hex(0xE6392E)
            let gold = c64 ? Palette.c64Yellow : Palette.brassGold
            ctx.setFillColor(wood.cgColor)
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 30, height: 30))
            ctx.setFillColor(red.cgColor)
            ctx.fill(CGRect(x: 4, y: 12, width: 26, height: 10))
            ctx.setStrokeColor(gold.cgColor)
            ctx.setLineWidth(2.2)
            ctx.strokeEllipse(in: CGRect(x: 3, y: 3, width: 28, height: 28))
        }
    }

    func guardHoundTexture(frame: Int, c64: Bool) -> SKTexture {
        cached("hound_\(frame)", width: 42, height: 28, pixelArt: c64) { ctx, w, h in
            let fur = c64 ? Palette.c64Orange : SKColor.hex(0xC27D38)
            let ear = c64 ? Palette.c64Brown : SKColor.hex(0x5E3414)
            let collar = c64 ? Palette.c64Yellow : SKColor.hex(0xFF4747)
            let s: CGFloat = frame == 0 ? 4 : -3
            ctx.setFillColor(fur.cgColor)
            ctx.fill(CGRect(x: 8 - s, y: 2, width: 5, height: 9))
            ctx.fill(CGRect(x: 26 + s, y: 2, width: 5, height: 9))
            ctx.fillEllipse(in: CGRect(x: 8, y: 8, width: 24, height: 12))
            ctx.fillEllipse(in: CGRect(x: 26, y: 13, width: 13, height: 11))
            ctx.setFillColor(ear.cgColor)
            ctx.fillEllipse(in: CGRect(x: 27, y: 18, width: 5, height: 7))
            ctx.setFillColor(collar.cgColor)
            ctx.fill(CGRect(x: 25, y: 12, width: 4, height: 8))
        }
    }

    func clipperShipTexture(c64: Bool) -> SKTexture {
        cached("clipper_ship", width: 64, height: 54, pixelArt: c64) { ctx, w, h in
            let hull = c64 ? Palette.c64Brown : SKColor.hex(0x6D3E1E)
            let sail = c64 ? Palette.c64White : SKColor.hex(0xF6F9FF)
            let gold = c64 ? Palette.c64Yellow : Palette.brassGold
            // Hull
            ctx.setFillColor(hull.cgColor)
            ctx.move(to: CGPoint(x: 6, y: 16))
            ctx.addLine(to: CGPoint(x: 58, y: 16))
            ctx.addLine(to: CGPoint(x: 48, y: 5))
            ctx.addLine(to: CGPoint(x: 14, y: 5))
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(gold.cgColor)
            ctx.fill(CGRect(x: 10, y: 13, width: 44, height: 2.5))
            // 3 Billowing Sails
            ctx.setFillColor(sail.cgColor)
            ctx.fill(CGRect(x: 14, y: 19, width: 10, height: 22))
            ctx.fill(CGRect(x: 27, y: 19, width: 12, height: 28))
            ctx.fill(CGRect(x: 42, y: 19, width: 9, height: 20))
        }
    }

    func stormCloudTexture(c64: Bool) -> SKTexture {
        cached("storm_cloud", width: 68, height: 52, pixelArt: c64) { ctx, w, h in
            let cloud = c64 ? Palette.c64DarkGrey : SKColor.hex(0x4E5B73)
            let bolt = c64 ? Palette.c64Yellow : Palette.brassGold
            ctx.setFillColor(cloud.cgColor)
            ctx.fillEllipse(in: CGRect(x: 8, y: 18, width: 28, height: 22))
            ctx.fillEllipse(in: CGRect(x: 22, y: 22, width: 30, height: 26))
            ctx.fillEllipse(in: CGRect(x: 38, y: 18, width: 24, height: 20))
            // Lightning bolt
            ctx.setFillColor(bolt.cgColor)
            ctx.move(to: CGPoint(x: 34, y: 20))
            ctx.addLine(to: CGPoint(x: 25, y: 9))
            ctx.addLine(to: CGPoint(x: 33, y: 9))
            ctx.addLine(to: CGPoint(x: 28, y: 1))
            ctx.addLine(to: CGPoint(x: 42, y: 13))
            ctx.addLine(to: CGPoint(x: 34, y: 13))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    func crtScanlineTexture() -> SKTexture {
        cached("crt_scanlines", width: 32, height: 8, pixelArt: true) { ctx, w, h in
            ctx.setFillColor(SKColor.rgba(0, 0, 0, 0.24).cgColor)
            for y in stride(from: 0 as CGFloat, to: h, by: 2) {
                ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        }
    }
}
