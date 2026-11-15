import AppKit
import CoreGraphics
import ImageIO
import Foundation

// Generates sleek A4 (595.28 x 841.89 pt) Designer One-Page Game Pitch / Sell-Sheet PDFs
// in BOTH English (IronRails_OnePager_EN.pdf) and Hungarian (IronRails_Egyoldalas_Jatekleiras.pdf)

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: make_onepagers_pdf <project_dir>\n", stderr)
    exit(1)
}

let projectDir = URL(fileURLWithPath: args[1], isDirectory: true)

func loadCGImage(_ relPath: String) -> CGImage? {
    let url = projectDir.appendingPathComponent(relPath)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

let bannerImg = loadCGImage("Marketing/storefront_banner.png")
let iconImg   = loadCGImage("Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let shotBat   = loadCGImage("dist/AppStore_Assets/Mac_2560x1600/01_river_bridge_field_battle.jpg")
let shotTrain = loadCGImage("dist/AppStore_Assets/Mac_2560x1600/02_paymaster_train_heist.jpg")
let shotMap   = loadCGImage("dist/AppStore_Assets/Mac_2560x1600/03_continental_railway_map.jpg")

struct SheetCopy {
    let outName: String
    let subtitle: String
    let pills: [String]
    let leftTitle: String
    let leftBody: String
    let rightTitle: String
    let rightBody: String
    let stripTitle: String
    let cards: [(String, String, String)]
    let shotCaptions: [String]
    let footLeftTitle: String
    let footLeftBody: String
    let footRightTitle: String
    let footRightBody: String
}

let enCopy = SheetCopy(
    outName: "IronRails_OnePager_EN.pdf",
    subtitle: "A 120Hz Comic-Arcade Tribute to 1989 C64 / Amiga Railroad Strategy & Action  •  © 2026 NGD",
    pills: [
        "iPhone • iPad • Mac Universal",
        "4 Classic Modes in 1 Game",
        "1989 C64 SID + Brass Synth",
        "Launch Sale $3.99 (Reg $6.99)"
    ],
    leftTitle: "COMMAND THE CONTINENTAL RAILS!",
    leftBody: "Lead Union Blue or the Gray Corps across 14 interconnected territories from 1861 to 1864 in a lighthearted, slapstick comic-book strategy-action adventure.\n\n• Paymaster Gold Express: Hold linked stations to run gold trains (+5G recruits a new Army) — or ambush enemy trains!\n• Live Era Switch [V / B]: Morph anytime between 120Hz HD Comic Art, CRT Cabinet, and 1989 C64 pixel + SID 6581 audio!",
    rightTitle: "4 ICONIC ACTION & STRATEGY PHASES",
    rightBody: "• STRATEGY MAP: 1861–1864 campaigns, Atlantic Clipper Ship reinforcements in Carolinas, army merging & Storm Clouds.\n• RIVER-BRIDGE FIELD BATTLE: Switch live [TAB] between Range-Gauge Artillery, Saber Cavalry & Infantry Volleys!\n• TRAIN HEIST & FORT ASSAULT: Leap swaying bullion boxcars and storm 3-tier ramparts past TNT barrels & guard hounds!",
    stripTitle: "SIX PILLARS OF IRON RAILS — STRATEGY, ARTILLERY, HEISTS & RETRO TIME-MACHINE",
    cards: [
        ("RAIL MAP", "14 states, 1861–64 scenarios & AI", "4 CAMPAIGNS"),
        ("ARTILLERY", "Variable range & destructible bridge", "BRIDGE BOOM"),
        ("CAVALRY", "Bugle saber sweeps & flanking fords", "FAST CHARGE"),
        ("TRAIN RAID", "Leap couplings & seize the Cab!", "GOLD HEIST"),
        ("FORT STORM", "3-tier ramparts, TNT & hounds!", "60S SPRINT"),
        ("1989 C64", "16-color pixel + 3-voice SID 6581", "LIVE [V / B]")
    ],
    shotCaptions: [
        "RIVER-BRIDGE ARTILLERY & CAVALRY",
        "HIGH-SPEED STEAM TRAIN HEIST",
        "1861–1864 CONTINENTAL RAILWAY MAP"
    ],
    footLeftTitle: "UNIVERSAL CONTROLS & MULTIPLAYER",
    footLeftBody: "• iPhone & iPad: Landscape Touch Map + Virtual Stick & Haptics\n• Mac: Mouse & Keyboard (Arrows/WASD, Space, Tab, V & B)\n• 1P vs Smart AI (3 Ranks) or 2P Local Pass-and-Play / Couch\n• Native PS5 DualSense, Xbox & MFi Bluetooth Gamepads",
    footRightTitle: "PRODUCT & APP STORE FACTSHEET",
    footRightBody: "• Developer & Publisher: NGD (Bundle ID: com.ngd.ironrails)\n• 100% Original IP, Comic Art, Code & Dual-Chip Synth Engine\n• Platforms: iOS 16+, iPadOS 16+, macOS 14+ Universal 2\n• Business Model: Pay-Once Universal • Zero Ads • Zero IAP"
)

let huCopy = SheetCopy(
    outName: "IronRails_Egyoldalas_Jatekleiras.pdf",
    subtitle: "120Hz-es tisztelgés az 1989-es C64 / Amiga stratégiai-akció klasszikus előtt  •  © 2026 NGD",
    pills: [
        "iPhone • iPad • Mac",
        "4 Klasszikus Mód 1 Játékban",
        "1989 C64 SID + Rézfúvós",
        "Akció: $3.99 ($6.99)"
    ],
    leftTitle: "URALD A KONTINENTÁLIS VASÚTVONALAT!",
    leftBody: "Vezesd a Union Blue vagy a Gray Corps csapatait 14 összekötött államon át 1861-től 1864-ig egy humoros, európai képregény-hangulatú stratégiai-akciójátékban!\n\n• Paymaster Aranyvonat: Védd az összekötött állomásokat az aranyért (5G = Új Hadsereg), vagy rabold ki az ellenség vonatát!\n• Élő Időgép [V / B]: Válts bármikor a 120Hz HD Képregény, a CRT monitor és az 1989-es C64 pixel + SID 6581 hang között!",
    rightTitle: "4 IKONIKUS STRATÉGIAI ÉS AKCIÓ FÁZIS",
    rightBody: "• STRATÉGIAI TÉRKÉP: 1861–1864 hadjáratok, Atlanti Klipper hajós erősítés, sereg-összevonás és viharfelhők.\n• HÍD-CSATA (FIELD BATTLE): Válts élőben [TAB] az irányzékos Ágyúk, a Lovassági roham és a Gyalogsági sortűz között!\n• VONATRABLÁS & ERŐDOSTROM: Ugrálj a zakatoló vagonok tetején, és rohamozd meg a 3-szintes erődöt TNT hordók között!",
    stripTitle: "AZ IRON RAILS HAT PILLÉRE — STRATÉGIA, TÜZÉRSÉG, VONATRABLÁS ÉS RETRO IDŐGÉP",
    cards: [
        ("VASÚTTÉRKÉP", "14 állam, 1861–64 és okos AI", "4 HADJÁRAT"),
        ("TÜZÉRSÉG", "Távolságmérő & lerombolható fahíd!", "HÍDROBBANTÁS"),
        ("LOVASSÁG", "Kürtjelre induló szablyás roham", "GYORS ROHAM"),
        ("VONATRABLÁS", "Ugrás a vagonokon a mozdonyig!", "ARANYZSÁKMÁNY"),
        ("ERŐDOSTROM", "3-szintes sánc, TNT és őrkutyák", "60 MP SPRINT"),
        ("1989 C64", "16-színű pixel + 3-sávos SID 6581", "ÉLŐ [V / B]")
    ],
    shotCaptions: [
        "FOLYÓPARTI TÜZÉRSÉG ÉS LOVASSÁG",
        "SZÁGULDÓ GŐZVONAT-RABLÁS",
        "1861–1864 KONTINENTÁLIS VASÚTTÉRKÉP"
    ],
    footLeftTitle: "UNIVERZÁLIS IRÁNYÍTÁS & TÖBBJÁTÉKOS MÓD",
    footLeftBody: "• iPhone & iPad: Fekvő érintőtérkép + Virtuális kar & Haptika\n• Mac: Egér és Billentyűzet (Nyilak/WASD, Space, Tab, V & B)\n• 1P vs AI (3 nehézségi szint) vagy 2P Helyi Pass & Play mód\n• Natív PS5 DualSense, Xbox és MFi Bluetooth kontrollerek",
    footRightTitle: "TERMÉK & APP STORE ADATLAP",
    footRightBody: "• Fejlesztő & Kiadó: NGD (Bundle ID: com.ngd.ironrails)\n• 100% Eredeti IP, Képregény-Grafika, Kód & Szintetizátor\n• Platformok: iOS 16+, iPadOS 16+, macOS 14+ Universal 2\n• Üzleti modell: Egyszeri vásárlás • Reklám- és IAP-mentes"
)

func renderPDF(_ copy: SheetCopy) {
    let mktURL = projectDir.appendingPathComponent("Marketing/\(copy.outName)")
    let distURL = projectDir.appendingPathComponent("dist/\(copy.outName)")

    let pageW: CGFloat = 595.28
    let pageH: CGFloat = 841.89
    var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

    guard let consumer = CGDataConsumer(url: mktURL as CFURL),
          let pdfCtx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fputs("Failed to create PDF at \(mktURL.path)\n", stderr)
        return
    }

    let cs = CGColorSpaceCreateDeviceRGB()
    let brass   = NSColor(calibratedRed: 1.00, green: 0.83, blue: 0.28, alpha: 1.0)
    let unionB  = NSColor(calibratedRed: 0.35, green: 0.66, blue: 1.00, alpha: 1.0)
    let crimson = NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.36, alpha: 1.0)
    let emerald = NSColor(calibratedRed: 0.20, green: 0.92, blue: 0.56, alpha: 1.0)
    let cardBg  = NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.22, alpha: 0.94)
    let muted   = NSColor(calibratedRed: 0.84, green: 0.89, blue: 0.97, alpha: 1.0)

    pdfCtx.beginPDFPage(nil)

    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [
            NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.13, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.22, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.14, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
    pdfCtx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: pageH), end: CGPoint(x: pageW, y: 0), options: [])

    let outerFrame = CGPath(roundedRect: CGRect(x: 16, y: 16, width: pageW - 32, height: pageH - 32), cornerWidth: 14, cornerHeight: 14, transform: nil)
    pdfCtx.setStrokeColor(brass.withAlphaComponent(0.45).cgColor)
    pdfCtx.setLineWidth(1.3)
    pdfCtx.addPath(outerFrame)
    pdfCtx.strokePath()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: pdfCtx, flipped: false)

    func drawText(_ text: String, rect: CGRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left, lineSpacing: CGFloat = 1.5) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    func drawCard(_ rect: CGRect, border: NSColor, fill: NSColor = cardBg, radius: CGFloat = 10) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        pdfCtx.setFillColor(fill.cgColor)
        pdfCtx.addPath(path)
        pdfCtx.fillPath()
        pdfCtx.setStrokeColor(border.withAlphaComponent(0.62).cgColor)
        pdfCtx.setLineWidth(1.15)
        pdfCtx.addPath(path)
        pdfCtx.strokePath()
    }

    func drawClippedImage(_ img: CGImage?, in rect: CGRect, radius: CGFloat = 8, border: NSColor? = nil) {
        guard let img = img else { return }
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        pdfCtx.saveGState()
        pdfCtx.addPath(path)
        pdfCtx.clip()
        pdfCtx.interpolationQuality = .high
        pdfCtx.draw(img, in: rect)
        pdfCtx.restoreGState()
        if let b = border {
            pdfCtx.setStrokeColor(b.cgColor)
            pdfCtx.setLineWidth(1.2)
            pdfCtx.addPath(path)
            pdfCtx.strokePath()
        }
    }

    // 1. Hero Banner
    let heroRect = CGRect(x: 28, y: pageH - 220, width: pageW - 56, height: 192)
    drawClippedImage(bannerImg, in: heroRect, radius: 12, border: brass.withAlphaComponent(0.88))

    let titleBarRect = CGRect(x: heroRect.minX + 8, y: heroRect.minY + 8, width: heroRect.width - 16, height: 64)
    let titleBarPath = CGPath(roundedRect: titleBarRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    pdfCtx.setFillColor(NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.16, alpha: 0.88).cgColor)
    pdfCtx.addPath(titleBarPath)
    pdfCtx.fillPath()

    drawClippedImage(iconImg, in: CGRect(x: pageW - 102, y: heroRect.minY + 12, width: 56, height: 56), radius: 12, border: brass.withAlphaComponent(0.7))

    drawText(
        "IRON RAILS: BLUE & GRAY",
        rect: CGRect(x: 46, y: heroRect.minY + 36, width: 430, height: 26),
        font: .systemFont(ofSize: 19.5, weight: .black),
        color: brass
    )
    drawText(
        copy.subtitle,
        rect: CGRect(x: 46, y: heroRect.minY + 14, width: 435, height: 18),
        font: .systemFont(ofSize: 8.6, weight: .semibold),
        color: .white
    )

    // 2. 4 Pill Badges
    let pillColors = [brass, unionB, crimson, emerald]
    let pillW = (pageW - 56 - 24) / 4.0
    let pillY: CGFloat = pageH - 248
    for i in 0..<4 {
        let px = 28 + CGFloat(i) * (pillW + 8)
        let pRect = CGRect(x: px, y: pillY, width: pillW, height: 20)
        drawCard(pRect, border: pillColors[i], fill: pillColors[i].withAlphaComponent(0.14), radius: 10)
        drawText(copy.pills[i], rect: CGRect(x: px, y: pillY - 1, width: pillW, height: 17), font: .systemFont(ofSize: 7.6, weight: .bold), color: pillColors[i], align: .center)
    }

    // 3. Two-Column Pitch & Modes
    let colW: CGFloat = (pageW - 68) / 2.0
    let leftX: CGFloat = 28
    let rightX: CGFloat = 28 + colW + 12
    let midRowY: CGFloat = pageH - 408

    drawCard(CGRect(x: leftX, y: midRowY, width: colW, height: 150), border: brass)
    drawText(copy.leftTitle, rect: CGRect(x: leftX + 12, y: midRowY + 124, width: colW - 24, height: 16), font: .systemFont(ofSize: 9.8, weight: .heavy), color: brass)
    drawText(copy.leftBody, rect: CGRect(x: leftX + 12, y: midRowY + 6, width: colW - 24, height: 115), font: .systemFont(ofSize: 7.8, weight: .regular), color: muted, lineSpacing: 1.35)

    drawCard(CGRect(x: rightX, y: midRowY, width: colW, height: 150), border: unionB)
    drawText(copy.rightTitle, rect: CGRect(x: rightX + 12, y: midRowY + 124, width: colW - 24, height: 16), font: .systemFont(ofSize: 9.8, weight: .heavy), color: unionB)
    drawText(copy.rightBody, rect: CGRect(x: rightX + 12, y: midRowY + 6, width: colW - 24, height: 115), font: .systemFont(ofSize: 7.8, weight: .regular), color: muted, lineSpacing: 1.35)

    // 4. 6 Pillar Cards Strip
    let secBoxY: CGFloat = pageH - 528
    drawCard(CGRect(x: 28, y: secBoxY, width: pageW - 56, height: 110), border: brass)
    drawText(copy.stripTitle, rect: CGRect(x: 40, y: secBoxY + 84, width: 515, height: 16), font: .systemFont(ofSize: 9.0, weight: .heavy), color: brass)

    let cardColors: [NSColor] = [unionB, brass, emerald, crimson, brass, .white]
    let sCardW: CGFloat = (pageW - 80 - 25) / 6.0
    for (i, w) in copy.cards.enumerated() {
        let sx = 40 + CGFloat(i) * (sCardW + 5)
        let sRect = CGRect(x: sx, y: secBoxY + 10, width: sCardW, height: 70)
        drawCard(sRect, border: cardColors[i], fill: NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.17, alpha: 0.96), radius: 7)
        drawText(w.0, rect: CGRect(x: sx + 5, y: secBoxY + 59, width: sCardW - 10, height: 13), font: .systemFont(ofSize: 6.8, weight: .black), color: cardColors[i])
        drawText(w.1, rect: CGRect(x: sx + 5, y: secBoxY + 23, width: sCardW - 10, height: 34), font: .systemFont(ofSize: 6.8, weight: .regular), color: muted, lineSpacing: 1.05)
        drawText(w.2, rect: CGRect(x: sx + 5, y: secBoxY + 9, width: sCardW - 10, height: 12), font: .monospacedSystemFont(ofSize: 6.6, weight: .bold), color: .white)
    }

    // 5. Three Screenshot Gallery
    let galY: CGFloat = pageH - 666
    let shotW: CGFloat = (pageW - 56 - 16) / 3.0
    let shotH: CGFloat = shotW * (1600.0 / 2560.0)
    let shots: [(CGImage?, String, NSColor)] = [
        (shotBat,   copy.shotCaptions[0], brass),
        (shotTrain, copy.shotCaptions[1], emerald),
        (shotMap,   copy.shotCaptions[2], unionB)
    ]
    for (i, item) in shots.enumerated() {
        let gx = 28 + CGFloat(i) * (shotW + 8)
        let imgRect = CGRect(x: gx, y: galY + 18, width: shotW, height: shotH)
        drawClippedImage(item.0, in: imgRect, radius: 8, border: item.2)
        drawText(item.1, rect: CGRect(x: gx, y: galY + 1, width: shotW, height: 14), font: .systemFont(ofSize: 7.4, weight: .bold), color: item.2, align: .center)
    }

    // 6. Bottom Factsheet
    let footY: CGFloat = 28
    let footH: CGFloat = galY - footY - 8
    drawCard(CGRect(x: 28, y: footY, width: pageW - 56, height: footH), border: emerald)

    drawText(copy.footLeftTitle, rect: CGRect(x: 42, y: footY + footH - 23, width: 255, height: 15), font: .systemFont(ofSize: 9.2, weight: .heavy), color: emerald)
    drawText(copy.footLeftBody, rect: CGRect(x: 42, y: footY + 8, width: 258, height: footH - 33), font: .systemFont(ofSize: 7.9, weight: .regular), color: muted, lineSpacing: 1.85)

    drawText(copy.footRightTitle, rect: CGRect(x: 312, y: footY + footH - 23, width: 248, height: 15), font: .systemFont(ofSize: 9.2, weight: .heavy), color: brass)
    drawText(copy.footRightBody, rect: CGRect(x: 312, y: footY + 8, width: 248, height: footH - 33), font: .systemFont(ofSize: 7.9, weight: .regular), color: muted, lineSpacing: 1.85)

    NSGraphicsContext.restoreGraphicsState()
    pdfCtx.endPDFPage()
    pdfCtx.closePDF()

    try? FileManager.default.removeItem(at: distURL)
    try? FileManager.default.copyItem(at: mktURL, to: distURL)
    print("Generated \(mktURL.path) & \(distURL.path)")
}

renderPDF(enCopy)
renderPDF(huCopy)
