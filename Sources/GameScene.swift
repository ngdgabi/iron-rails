import Foundation
import SpriteKit
#if canImport(GameController)
import GameController
#endif

enum ActiveGameMode {
    case titleMenu
    case campaignSetup
    case medalsOverlay
    case howToPlayOverlay
    case settingsOverlay
    case strategyMap
    case fieldBattle
    case fortAssault
    case trainHeist
    case victoryScreen
}

enum FieldUnitKind: Int, CaseIterable {
    case cannon = 0
    case cavalry = 1
    case infantry = 2

    var label: String {
        switch self {
        case .cannon:   return "ARTILLERY"
        case .cavalry:  return "CAVALRY"
        case .infantry: return "INFANTRY"
        }
    }
}

@MainActor
final class GameScene: SKScene {

    // Core Layers
    private let worldLayer = SKNode()
    private let fxLayer = SKNode()
    private let hudLayer = SKNode()
    private let overlayLayer = SKNode()
    private let crtLayer = SKNode()

    // Mode & Campaign State
    private(set) var mode: ActiveGameMode = .titleMenu
    var isActionArcadePhase: Bool {
        mode == .fieldBattle || mode == .fortAssault || mode == .trainHeist
    }

    private var campaign: CampaignState?
    private var activeEncounter: PendingEncounter?
    private var isQuickSkirmish: Bool = false

    // Menu Selection & Campaign Setup Choices
    private var menuIndex: Int = 0
    private let titleMenuItems = [
        "START CAMPAIGN",
        "QUICK FIELD BATTLE",
        "QUICK TRAIN HEIST",
        "QUICK FORT ASSAULT",
        "MEDALS & HALL OF FAME",
        "HOW TO PLAY",
        "ERA & AUDIO SETTINGS"
    ]
    private var setupYear: CampaignYear = .y1861
    private var setupMode: PlayerMode = .unionVsAI
    private var setupDiff: AIDifficulty = .colonel

    // Input Tracking (Keyboard + Gamepad + Touch)
    private var keysHeld: Set<UInt16> = []
    private var keyJustPressedPrimary: Bool = false
    private var keyJustPressedSecondary: Bool = false
    private var lastUpdateTime: TimeInterval = 0
    private var sceneClock: Double = 0
    private var isUserPaused: Bool = false
    var isAutopilotActive: Bool = false

    // Title Screen Background Props
    private var titleTrainNode: SKNode?
    private var titleCannonNode: SKSpriteNode?

    // Strategy Map State
    private var selectedTerritoryId: Int? = nil
    private var aiTurnTimer: Double = 0
    private var mapBannerQueue: [TurnEventBanner] = []
    private var mapBannerTimer: Double = 0
    private var animatedTrainNode: SKNode?

    // Field Battle Entities
    private struct BattleUnit {
        var id: Int
        var faction: Faction
        var kind: FieldUnitKind
        var pos: CGPoint
        var hp: Int
        var reloadTimer: Double = 0
        var dizzyTimer: Double = 0
        var animPhase: Double = 0
        var node: SKSpriteNode
    }
    private struct CannonShell {
        var faction: Faction
        var start: CGPoint
        var target: CGPoint
        var elapsed: Double
        var duration: Double
        var node: SKShapeNode
        var shadow: SKShapeNode
    }
    private struct MusketBullet {
        var faction: Faction
        var pos: CGPoint
        var vx: CGFloat
        var vy: CGFloat
        var life: Double
        var node: SKShapeNode
    }

    private var battleUnits: [BattleUnit] = []
    private var cannonShells: [CannonShell] = []
    private var musketBullets: [MusketBullet] = []
    private var bridgeSpanHP: [Int] = [2, 2, 2] // 3 wooden spans across canyon river
    private var bridgeNodes: [SKShapeNode] = []
    private var playerBattleFaction: Faction = .unionBlue
    private var selectedUnitKind: FieldUnitKind = .cannon
    private var cannonPowerPhase: Double = 0
    private var battleInitialUnitCount: Int = 0
    private var battleInitialHadCavalry: Bool = false
    private var battleEndCountdown: Double = 0
    private var battleResolvedWinner: Faction? = nil
    private var aiBattleClock: Double = 0

    // Side-Scrolling Action Runner State (Shared by Fort Assault & Train Heist)
    private struct ActionEnemy {
        var pos: CGPoint
        var vx: CGFloat
        var minX: CGFloat
        var maxX: CGFloat
        var isHound: Bool
        var isBarrel: Bool
        var dizzyTimer: Double = 0
        var faction: Faction
        var node: SKSpriteNode
    }
    private var runnerPos: CGPoint = CGPoint(x: 200, y: 210)
    private var runnerVel: CGVector = .zero
    private var runnerGrounded: Bool = true
    private var runnerClimbing: Bool = false
    private var runnerDucking: Bool = false
    private var runnerDizzyTimer: Double = 0
    private var runnerInvulnTimer: Double = 0
    private var runnerPunchTimer: Double = 0
    private var runnerStamina: Int = 3
    private var runnerFaction: Faction = .unionBlue
    private var defenderFaction: Faction = .grayCorps
    private var runnerNode: SKSpriteNode?
    private var actionEnemies: [ActionEnemy] = []
    private var actionTimerLeft: Double = 60.0
    private var actionGoalX: CGFloat = 1075
    private var actionSpawnTimer: Double = 0
    private var actionEndCountdown: Double = 0
    private var actionWinner: Faction? = nil
    private var scrollingProps: [SKNode] = []
    private var overheadHazardX: CGFloat = 1400

    // Victory Summary
    private var victoryFaction: Faction = .unionBlue
    private var victoryHeadline: String = ""
    private var victorySubline: String = ""

    // Toast Medal Notification
    private var medalToastNode: SKNode?

    override func didMove(to view: SKView) {
        size = CGSize(width: 1280, height: 800)
        scaleMode = .aspectFill
        backgroundColor = Palette.deepNavyBg

        if worldLayer.parent == nil {
            worldLayer.zPosition = 10
            fxLayer.zPosition = 40
            hudLayer.zPosition = 80
            overlayLayer.zPosition = 120
            crtLayer.zPosition = 200
            addChild(worldLayer)
            addChild(fxLayer)
            addChild(hudLayer)
            addChild(overlayLayer)
            addChild(crtLayer)
        }

        let settings = PersistenceManager.shared.data.settings
        AudioSynth.shared.syncSettings(settings)
        setupDiff = settings.aiDifficulty
        rebuildCRTOverlay()
        enterTitleMenu()
    }

    // MARK: - Live Visual & Audio Era Switching (1989 C64 <-> 2026 HD Comic)

    var isC64: Bool {
        PersistenceManager.shared.data.settings.visualTheme == .c64Retro
    }

    func cycleVisualTheme() {
        var nextTheme: VisualTheme = .hdOverdrive
        PersistenceManager.shared.updateSettings { s in
            s.visualTheme = s.visualTheme.next()
            nextTheme = s.visualTheme
        }
        AudioSynth.shared.trigger(.menuSelect)
        HapticsManager.tap()
        checkTimeTravelerMedal()
        rebuildCRTOverlay()
        refreshCurrentModeVisuals()
        showFloatingBanner("VISUAL ERA: \(nextTheme.label)", color: Palette.brassGold)
    }

    func cycleAudioChip() {
        var nextChip: AudioChipMode = .modernSynth
        PersistenceManager.shared.updateSettings { s in
            s.audioChip = s.audioChip.next()
            nextChip = s.audioChip
        }
        AudioSynth.shared.syncSettings(PersistenceManager.shared.data.settings)
        AudioSynth.shared.trigger(.goldChime)
        HapticsManager.tap()
        checkTimeTravelerMedal()
        refreshCurrentModeVisuals()
        showFloatingBanner("AUDIO CHIP: \(nextChip.label)", color: Palette.unionBright)
    }

    func togglePauseFromUI() {
        guard mode == .fieldBattle || mode == .fortAssault || mode == .trainHeist || mode == .strategyMap else { return }
        if mode == .strategyMap {
            enterTitleMenu()
            return
        }
        isUserPaused.toggle()
        AudioSynth.shared.setPaused(isUserPaused)
        AudioSynth.shared.trigger(.menuSelect)
        rebuildPauseOverlay()
    }

    private func checkTimeTravelerMedal() {
        let s = PersistenceManager.shared.data.settings
        if s.visualTheme == .c64Retro && s.audioChip == .c64SID {
            if let m = PersistenceManager.shared.unlockMedal("time_machine_89") {
                presentMedalToast(m)
            }
        }
    }

    private func rebuildCRTOverlay() {
        crtLayer.removeAllChildren()
        let theme = PersistenceManager.shared.data.settings.visualTheme
        if theme == .crtCabinet || theme == .c64Retro {
            let scan = SKSpriteNode(texture: SpriteFactory.shared.crtScanlineTexture(), size: CGSize(width: 1280, height: 800))
            scan.position = CGPoint(x: 640, y: 400)
            scan.alpha = theme == .c64Retro ? 0.55 : 0.38
            crtLayer.addChild(scan)
        }
        if theme == .c64Retro {
            // Subtle classic C64 light-blue outer frame hint at extreme edges
            let frame = SKShapeNode(rect: CGRect(x: 8, y: 8, width: 1264, height: 784))
            frame.strokeColor = Palette.c64LightBlue.withAlphaComponent(0.55)
            frame.lineWidth = 14
            crtLayer.addChild(frame)
        }
    }

    private func refreshCurrentModeVisuals() {
        switch mode {
        case .titleMenu:         enterTitleMenu()
        case .campaignSetup:     showCampaignSetup()
        case .medalsOverlay:     showMedalsOverlay()
        case .howToPlayOverlay:  showHowToPlayOverlay()
        case .settingsOverlay:   showSettingsOverlay()
        case .strategyMap:       renderStrategyMap()
        case .fieldBattle:       refreshBattleTextures()
        case .fortAssault:       rebuildFortBackdropAndHUD()
        case .trainHeist:        rebuildTrainBackdropAndHUD()
        case .victoryScreen:     renderVictoryScreen()
        }
    }

    private func clearAllModeNodes() {
        worldLayer.removeAllChildren()
        fxLayer.removeAllChildren()
        hudLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        isUserPaused = false
        AudioSynth.shared.setPaused(false)
    }

    // MARK: - 1. Interactive Title Command Tent

    func enterTitleMenu() {
        mode = .titleMenu
        clearAllModeNodes()
        AudioSynth.shared.setTrack(.titleMarch)

        let c64 = isC64
        // Scenic Sky + Hills + Canyon River + Trestle Bridge
        let sky = SKSpriteNode(color: c64 ? Palette.c64Blue : SKColor.hex(0x163368), size: CGSize(width: 1280, height: 800))
        sky.position = CGPoint(x: 640, y: 400)
        worldLayer.addChild(sky)

        // Sunset horizon glow
        if !c64 {
            let glow = SKShapeNode(ellipseOf: CGSize(width: 980, height: 340))
            glow.fillColor = SKColor.hex(0xFFAE42).withAlphaComponent(0.24)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: 640, y: 310)
            worldLayer.addChild(glow)
        }

        // Rolling Prairie Hills
        let meadow = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 1280, height: 280))
        meadow.fillColor = c64 ? Palette.c64Green : SKColor.hex(0x2D7E43)
        meadow.strokeColor = .clear
        worldLayer.addChild(meadow)

        // Canyon River Center
        let river = SKShapeNode(rect: CGRect(x: 520, y: 0, width: 240, height: 280))
        river.fillColor = c64 ? Palette.c64Cyan : Palette.riverCyan
        river.strokeColor = .clear
        worldLayer.addChild(river)

        // High Wooden Trestle Bridge across background
        let trestleY: CGFloat = 280
        let railBeam = SKShapeNode(rect: CGRect(x: 0, y: trestleY, width: 1280, height: 10))
        railBeam.fillColor = c64 ? Palette.c64Brown : SKColor.hex(0x693B1B)
        railBeam.strokeColor = c64 ? Palette.c64Black : SKColor.hex(0x1B120B)
        worldLayer.addChild(railBeam)
        for tx in stride(from: 60 as CGFloat, through: 1220, by: 85) {
            let pier = SKShapeNode(rect: CGRect(x: tx, y: 120, width: 8, height: trestleY - 120))
            pier.fillColor = c64 ? Palette.c64Brown : SKColor.hex(0x5A3217)
            pier.strokeColor = .clear
            worldLayer.addChild(pier)
        }

        // Animated Background Steam Train
        let trainContainer = SKNode()
        trainContainer.position = CGPoint(x: 240, y: trestleY + 46)
        let loco = SKSpriteNode(texture: SpriteFactory.shared.locomotiveTexture(c64: c64), size: CGSize(width: 170, height: 88))
        loco.position = CGPoint(x: 160, y: 0)
        let car1 = SKSpriteNode(texture: SpriteFactory.shared.boxcarTexture(isPaymasterGold: true, c64: c64), size: CGSize(width: 136, height: 68))
        car1.position = CGPoint(x: 0, y: -8)
        let car2 = SKSpriteNode(texture: SpriteFactory.shared.boxcarTexture(isPaymasterGold: false, c64: c64), size: CGSize(width: 136, height: 68))
        car2.position = CGPoint(x: -144, y: -8)
        trainContainer.addChild(car2)
        trainContainer.addChild(car1)
        trainContainer.addChild(loco)
        worldLayer.addChild(trainContainer)
        self.titleTrainNode = trainContainer

        // Interactive Comic Gag Cannon on Left Bank (Click/Tap Easter Egg!)
        let gagCannon = SKSpriteNode(texture: SpriteFactory.shared.cannonTexture(faction: .unionBlue, c64: c64), size: CGSize(width: 96, height: 68))
        gagCannon.position = CGPoint(x: 235, y: 195)
        gagCannon.name = "gag_cannon"
        worldLayer.addChild(gagCannon)
        self.titleCannonNode = gagCannon

        let blueGuard = SKSpriteNode(texture: SpriteFactory.shared.soldierTexture(faction: .unionBlue, pose: .idle, c64: c64), size: CGSize(width: 58, height: 68))
        blueGuard.position = CGPoint(x: 175, y: 198)
        blueGuard.name = "gag_cannon"
        worldLayer.addChild(blueGuard)

        let grayCav = SKSpriteNode(texture: SpriteFactory.shared.cavalryTexture(faction: .grayCorps, gallopFrame: 0, c64: c64), size: CGSize(width: 102, height: 88))
        grayCav.xScale = -1.0
        grayCav.position = CGPoint(x: 1050, y: 205)
        worldLayer.addChild(grayCav)

        // Title Crest Plaque (Safe Zone x: 250..1030, y: 555..665)
        let crest = SKShapeNode(rectOf: CGSize(width: 760, height: 104), cornerRadius: 16)
        crest.position = CGPoint(x: 640, y: 612)
        crest.fillColor = (c64 ? Palette.c64Black : Palette.panelBg).withAlphaComponent(0.92)
        crest.strokeColor = c64 ? Palette.c64Yellow : Palette.brassGold
        crest.lineWidth = 3.5
        hudLayer.addChild(crest)

        let titleLbl = CoreTextLabelRenderer.makeLabelNode("IRON RAILS: BLUE & GRAY", fontSize: 36, color: c64 ? Palette.c64Yellow : Palette.brassGold)
        titleLbl.position = CGPoint(x: 640, y: 626)
        hudLayer.addChild(titleLbl)

        let subLbl = CoreTextLabelRenderer.makeLabelNode("COMIC STRATEGY • RIVER ARTILLERY • TRAIN HEISTS • FORT ASSAULTS", fontSize: 13, color: c64 ? Palette.c64Cyan : SKColor.hex(0xBFD6FF))
        subLbl.position = CGPoint(x: 640, y: 585)
        hudLayer.addChild(subLbl)

        // Menu Card Stack (y: 165..530)
        rebuildTitleMenuButtons()

        // Era Quick-Switch Pills in Top Corners (Safe Zone)
        addEraQuickPills()
    }

    private func rebuildTitleMenuButtons() {
        hudLayer.children.filter { $0.name?.hasPrefix("menu_row_") == true }.forEach { $0.removeFromParent() }
        let c64 = isC64
        let startY: CGFloat = 515
        let stepY: CGFloat = 52

        for (idx, title) in titleMenuItems.enumerated() {
            let isSel = (idx == menuIndex)
            let row = SKShapeNode(rectOf: CGSize(width: 440, height: 42), cornerRadius: 10)
            row.position = CGPoint(x: 640, y: startY - CGFloat(idx) * stepY)
            row.fillColor = isSel
                ? (c64 ? Palette.c64Blue : SKColor.hex(0x2352B8))
                : (c64 ? Palette.c64Black : Palette.panelBg).withAlphaComponent(0.88)
            row.strokeColor = isSel ? (c64 ? Palette.c64Yellow : Palette.brassGold) : SKColor.hex(0x466294)
            row.lineWidth = isSel ? 3.0 : 1.5
            row.name = "menu_row_\(idx)"

            let txt = CoreTextLabelRenderer.makeLabelNode(
                isSel ? "▶  \(title)  ◀" : title,
                fontSize: 17,
                color: isSel ? (c64 ? Palette.c64White : Palette.brassGold) : .white
            )
            txt.name = "menu_row_\(idx)"
            row.addChild(txt)
            hudLayer.addChild(row)
        }
    }

    private func addEraQuickPills() {
        let s = PersistenceManager.shared.data.settings
        let c64 = isC64

        let eraBtn = makePillButton(name: "btn_era", text: "ERA: \(s.visualTheme.label)", width: 215, pos: CGPoint(x: 255, y: 652), accent: c64 ? Palette.c64Yellow : Palette.brassGold)
        let chipBtn = makePillButton(name: "btn_chip", text: "CHIP: \(s.audioChip.label)", width: 215, pos: CGPoint(x: 1025, y: 652), accent: c64 ? Palette.c64Cyan : Palette.unionBright)
        hudLayer.addChild(eraBtn)
        hudLayer.addChild(chipBtn)
    }

    private func makePillButton(name: String, text: String, width: CGFloat, pos: CGPoint, accent: SKColor, height: CGFloat = 32) -> SKShapeNode {
        let pill = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height * 0.45)
        pill.position = pos
        pill.fillColor = SKColor.hex(0x0F1A30).withAlphaComponent(0.92)
        pill.strokeColor = accent
        pill.lineWidth = 2.0
        pill.name = name
        let lbl = CoreTextLabelRenderer.makeLabelNode(text, fontSize: 12, color: accent)
        lbl.name = name
        pill.addChild(lbl)
        return pill
    }

    private func activateTitleMenuSelection() {
        AudioSynth.shared.trigger(.menuSelect)
        HapticsManager.mediumImpact()
        switch menuIndex {
        case 0: showCampaignSetup()
        case 1:
            isQuickSkirmish = true
            startFieldBattle(
                attacker: .veteran(for: .unionBlue),
                defender: .veteran(for: .grayCorps),
                humanFaction: .unionBlue
            )
        case 2:
            isQuickSkirmish = true
            startTrainHeist(raider: .unionBlue, trainOwner: .grayCorps)
        case 3:
            isQuickSkirmish = true
            startFortAssault(attacker: .unionBlue, defender: .grayCorps)
        case 4: showMedalsOverlay()
        case 5: showHowToPlayOverlay()
        case 6: showSettingsOverlay()
        default: break
        }
    }

    // MARK: - Title Sub-Modals (Campaign Setup, Medals, How To Play, Settings)

    private func showCampaignSetup() {
        mode = .campaignSetup
        overlayLayer.removeAllChildren()

        let card = makeModalCard(title: "CAMPAIGN DISPATCH HQ", subtitle: "Configure Year, Commanders & Difficulty")

        let rows: [(String, String, CGFloat)] = [
            ("opt_year", "SCENARIO:  \(setupYear.title)", 465),
            ("opt_mode", "COMMANDERS:  \(setupMode.label)", 405),
            ("opt_diff", "AI GENERAL:  \(setupDiff.label)", 345),
        ]
        for (nm, label, y) in rows {
            let b = makePillButton(name: nm, text: label, width: 560, pos: CGPoint(x: 640, y: y), accent: Palette.unionBright, height: 42)
            card.addChild(b)
        }

        let launch = makePillButton(name: "btn_launch_campaign", text: "★ LAUNCH CONTINENTAL CAMPAIGN ★", width: 460, pos: CGPoint(x: 640, y: 265), accent: Palette.emeraldWin, height: 48)
        launch.fillColor = SKColor.hex(0x164B3A)
        card.addChild(launch)

        let back = makePillButton(name: "btn_modal_back", text: "BACK TO COMMAND TENT", width: 280, pos: CGPoint(x: 640, y: 195), accent: Palette.brassGold, height: 36)
        card.addChild(back)
        overlayLayer.addChild(card)
    }

    private func showMedalsOverlay() {
        mode = .medalsOverlay
        overlayLayer.removeAllChildren()
        let card = makeModalCard(title: "COMMANDER MEDALS & HALL OF FAME", subtitle: "\(PersistenceManager.shared.data.unlockedMedals.count)/12 Ribbons Unlocked • Campaigns Won: \(PersistenceManager.shared.data.campaignsWon)")

        let unlocked = PersistenceManager.shared.data.unlockedMedals
        for (i, m) in AchievementCatalog.all.enumerated() {
            let col = i % 2
            let row = i / 2
            let x: CGFloat = col == 0 ? 430 : 850
            let y: CGFloat = 490 - CGFloat(row) * 46
            let has = unlocked.contains(m.id)
            let badge = SKShapeNode(rectOf: CGSize(width: 385, height: 38), cornerRadius: 8)
            badge.position = CGPoint(x: x, y: y)
            badge.fillColor = has ? SKColor.hex(0x1C3B2F) : SKColor.hex(0x141E33)
            badge.strokeColor = has ? Palette.brassGold : SKColor.hex(0x33476B)
            let t = CoreTextLabelRenderer.makeLabelNode("\(has ? "★" : "☆") \(m.title)", fontSize: 12, color: has ? Palette.brassGold : SKColor.hex(0x93A8CC))
            t.position = CGPoint(x: 0, y: 7)
            let s = CoreTextLabelRenderer.makeLabelNode(m.subtitle, fontSize: 9.5, color: .white, bold: false)
            s.position = CGPoint(x: 0, y: -8)
            badge.addChild(t)
            badge.addChild(s)
            card.addChild(badge)
        }

        let back = makePillButton(name: "btn_modal_back", text: "BACK TO COMMAND TENT", width: 280, pos: CGPoint(x: 640, y: 190), accent: Palette.brassGold, height: 36)
        card.addChild(back)
        overlayLayer.addChild(card)
    }

    private func showHowToPlayOverlay() {
        mode = .howToPlayOverlay
        overlayLayer.removeAllChildren()
        let card = makeModalCard(title: "FIELD MANUAL & CONTROLS", subtitle: "Four Classic Modes — One Unified Campaign")

        let lines = [
            "1. STRATEGY MAP: Tap/Click a friendly Army, then tap an adjacent State to March, Merge, or Attack!",
            "   • Control connected Railroad Stations to run the Paymaster Gold Express (+5G = Recruit New Army!).",
            "   • Hold Carolinas Port for free Atlantic Clipper reinforcements every 3 rounds.",
            "2. FIELD BATTLE: [TAB / ALT] switches Cannon, Cavalry & Infantry! Destroy the river bridge with shells!",
            "3. STEAM TRAIN HEIST: Sprint right across swaying boxcars, Jump couplings, Punch guards to seize the Cab!",
            "4. FORT ASSAULT: Climb ramparts, Jump rolling TNT barrels & hounds to raise your flag before 60s expires!",
            "5. TIME MACHINE: Press [V] & [B] (or tap ERA & CHIP) anytime for 1989 C64 16-Color + SID 6581 Chiptune!"
        ]
        for (i, ln) in lines.enumerated() {
            let lbl = CoreTextLabelRenderer.makeLabelNode(ln, fontSize: 12.5, color: i % 2 == 0 ? Palette.brassGold : .white, bold: i % 2 == 0)
            lbl.position = CGPoint(x: 640, y: 485 - CGFloat(i) * 38)
            card.addChild(lbl)
        }

        let back = makePillButton(name: "btn_modal_back", text: "READY FOR DUTY", width: 280, pos: CGPoint(x: 640, y: 195), accent: Palette.emeraldWin, height: 38)
        card.addChild(back)
        overlayLayer.addChild(card)
    }

    private func showSettingsOverlay() {
        mode = .settingsOverlay
        overlayLayer.removeAllChildren()
        let s = PersistenceManager.shared.data.settings
        let card = makeModalCard(title: "ERA, AUDIO & GAMEPLAY SETTINGS", subtitle: "Switch Live Anytime During Battle with V & B")

        card.addChild(makePillButton(name: "set_theme", text: "VISUAL ERA:  \(s.visualTheme.label)", width: 500, pos: CGPoint(x: 640, y: 475), accent: Palette.brassGold, height: 42))
        card.addChild(makePillButton(name: "set_chip", text: "AUDIO SYNTH:  \(s.audioChip.label)", width: 500, pos: CGPoint(x: 640, y: 420), accent: Palette.unionBright, height: 42))
        card.addChild(makePillButton(name: "set_storm", text: "STORM CLOUD HAZARD:  \(s.stormEventsEnabled ? "ENABLED" : "OFF")", width: 500, pos: CGPoint(x: 640, y: 365), accent: Palette.emeraldWin, height: 42))
        card.addChild(makePillButton(name: "set_music", text: "MUSIC VOLUME:  \(Int(round(s.musicVolume * 100)))%", width: 500, pos: CGPoint(x: 640, y: 310), accent: .white, height: 40))
        card.addChild(makePillButton(name: "set_sfx", text: "SFX VOLUME:  \(Int(round(s.sfxVolume * 100)))%", width: 500, pos: CGPoint(x: 640, y: 255), accent: .white, height: 40))

        let back = makePillButton(name: "btn_modal_back", text: "SAVE & RETURN", width: 280, pos: CGPoint(x: 640, y: 190), accent: Palette.brassGold, height: 36)
        card.addChild(back)
        overlayLayer.addChild(card)
    }

    private func makeModalCard(title: String, subtitle: String) -> SKNode {
        let root = SKNode()
        let dim = SKSpriteNode(color: SKColor.rgba(0, 0, 0, 0.72), size: CGSize(width: 1280, height: 800))
        dim.position = CGPoint(x: 640, y: 400)
        root.addChild(dim)

        let box = SKShapeNode(rectOf: CGSize(width: 860, height: 470), cornerRadius: 18)
        box.position = CGPoint(x: 640, y: 395)
        box.fillColor = isC64 ? Palette.c64Black : SKColor.hex(0x101B32)
        box.strokeColor = isC64 ? Palette.c64Yellow : Palette.brassGold
        box.lineWidth = 3.5
        root.addChild(box)

        let t = CoreTextLabelRenderer.makeLabelNode(title, fontSize: 25, color: isC64 ? Palette.c64Yellow : Palette.brassGold)
        t.position = CGPoint(x: 640, y: 585)
        root.addChild(t)

        let sub = CoreTextLabelRenderer.makeLabelNode(subtitle, fontSize: 13, color: SKColor.hex(0xAEC6EC), bold: false)
        sub.position = CGPoint(x: 640, y: 552)
        root.addChild(sub)
        return root
    }

    // MARK: - 2. Strategic Territory & Railway Map Mode

    func startNewCampaign(year: CampaignYear, playerMode: PlayerMode, difficulty: AIDifficulty) {
        isQuickSkirmish = false
        let stormOn = PersistenceManager.shared.data.settings.stormEventsEnabled
        let camp = CampaignState(year: year, mode: playerMode, difficulty: difficulty, stormEnabled: stormOn)
        self.campaign = camp
        self.selectedTerritoryId = nil
        enterStrategyMap(runTurnIntro: true)
    }

    private func enterStrategyMap(runTurnIntro: Bool) {
        guard let camp = campaign else { return }
        if let victor = camp.checkCampaignWinner() {
            concludeCampaign(winner: victor)
            return
        }

        mode = .strategyMap
        clearAllModeNodes()
        AudioSynth.shared.setTrack(.strategyMap)

        if runTurnIntro {
            AudioSynth.shared.trigger(.turnHorn)
            let (banners, heist, trainPath) = camp.beginTurnPhase()
            mapBannerQueue.append(contentsOf: banners)
            renderStrategyMap(trainRoute: trainPath)
            if let h = heist {
                // Brief visual beat then launch Train Heist!
                activeEncounter = h
                if case .trainHeist(let raider, let owner, _, _) = h {
                    run(.sequence([
                        .wait(forDuration: 0.9),
                        .run { [weak self] in
                            self?.startTrainHeist(raider: raider, trainOwner: owner)
                        }
                    ]))
                    return
                }
            }
        } else {
            renderStrategyMap()
        }

        if !camp.playerMode.isHuman(camp.activeFaction) {
            aiTurnTimer = 0.85
        }
    }

    private func renderStrategyMap(trainRoute: [Int] = []) {
        worldLayer.removeAllChildren()
        hudLayer.removeAllChildren()
        guard let camp = campaign else { return }
        let c64 = isC64

        // Ocean & Continental Map Board
        let ocean = SKSpriteNode(color: c64 ? Palette.c64Blue : SKColor.hex(0x112B52), size: CGSize(width: 1280, height: 800))
        ocean.position = CGPoint(x: 640, y: 400)
        worldLayer.addChild(ocean)

        let landMass = SKShapeNode(rectOf: CGSize(width: 735, height: 520), cornerRadius: 34)
        landMass.position = CGPoint(x: 590, y: 382)
        landMass.fillColor = c64 ? Palette.c64Brown : SKColor.hex(0x274B37)
        landMass.strokeColor = c64 ? Palette.c64Yellow : SKColor.hex(0xD8B46A)
        landMass.lineWidth = 3.0
        worldLayer.addChild(landMass)

        // Draw Neighbor Marching Roads
        for t in CampaignMapCatalog.territories {
            for nb in t.neighbors where nb > t.id {
                let p2 = CampaignMapCatalog.territories[nb].mapPos
                let path = CGMutablePath()
                path.move(to: t.mapPos)
                path.addLine(to: p2)
                let road = SKShapeNode(path: path)
                road.strokeColor = SKColor.rgba(1, 1, 1, 0.16)
                road.lineWidth = 2.0
                worldLayer.addChild(road)
            }
        }

        // Draw Iron Railroad Lines (Cross-ties + Twin Steel Rails)
        for (a, b) in CampaignMapCatalog.allRailEdges {
            let p1 = CampaignMapCatalog.territories[a].mapPos
            let p2 = CampaignMapCatalog.territories[b].mapPos
            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            let bed = SKShapeNode(path: path)
            bed.strokeColor = c64 ? Palette.c64DarkGrey : SKColor.hex(0x181E2B)
            bed.lineWidth = 7.0
            worldLayer.addChild(bed)

            let rail = SKShapeNode(path: path)
            rail.strokeColor = c64 ? Palette.c64Yellow : Palette.brassGold
            rail.lineWidth = 2.5
            worldLayer.addChild(rail)
        }

        // Atlantic Clipper Ship off Carolinas Port (id: 12) in open ocean below HQ panel
        let ship = SKSpriteNode(texture: SpriteFactory.shared.clipperShipTexture(c64: c64), size: CGSize(width: 64, height: 54))
        ship.position = CGPoint(x: 1052, y: 208)
        ship.zPosition = 14
        worldLayer.addChild(ship)
        let shipLbl = CoreTextLabelRenderer.makeLabelNode("CLIPPER IN \(camp.clipperCountdown)T", fontSize: 10.5, color: Palette.brassGold)
        shipLbl.position = CGPoint(x: 1052, y: 168)
        shipLbl.zPosition = 14
        worldLayer.addChild(shipLbl)

        let validTargets: Set<Int> = {
            guard let sel = selectedTerritoryId,
                  let st = camp.armies[sel],
                  st.faction == camp.activeFaction,
                  !st.movedThisTurn,
                  !st.stunnedByStorm else { return [] }
            return Set(CampaignMapCatalog.territories[sel].neighbors)
        }()

        // Territory Plates & Stationed Armies
        for t in CampaignMapCatalog.territories {
            let owner = camp.owners[t.id]
            let isSelected = (selectedTerritoryId == t.id)
            let isTarget = validTargets.contains(t.id)

            let plate = SKShapeNode(rectOf: CGSize(width: 96, height: 64), cornerRadius: 12)
            plate.position = t.mapPos
            if let ow = owner {
                plate.fillColor = Palette.factionFill(ow, c64: c64)
            } else {
                plate.fillColor = c64 ? Palette.c64DarkGrey : SKColor.hex(0x3B4659)
            }
            plate.strokeColor = isSelected
                ? Palette.brassGold
                : (isTarget ? Palette.emeraldWin : SKColor.rgba(1, 1, 1, 0.45))
            plate.lineWidth = (isSelected || isTarget) ? 3.5 : 1.8
            plate.name = "terr_\(t.id)"
            worldLayer.addChild(plate)

            let codeLbl = CoreTextLabelRenderer.makeLabelNode(
                t.hasFort ? "♜ \(t.code)" : (t.isCoastalPort ? "⚓ \(t.code)" : t.code),
                fontSize: 12,
                color: .white
            )
            codeLbl.position = CGPoint(x: 0, y: 19)
            codeLbl.name = "terr_\(t.id)"
            plate.addChild(codeLbl)

            if let stack = camp.armies[t.id] {
                let spr = SKSpriteNode(
                    texture: SpriteFactory.shared.soldierTexture(faction: stack.faction, pose: stack.stunnedByStorm ? .dizzy : .idle, c64: c64),
                    size: CGSize(width: 30, height: 35)
                )
                spr.position = CGPoint(x: -22, y: -6)
                spr.name = "terr_\(t.id)"
                plate.addChild(spr)

                let comp = CoreTextLabelRenderer.makeLabelNode(
                    "\(stack.infantry)•\(stack.cavalry)•\(stack.cannons)",
                    fontSize: 11.5,
                    color: (stack.movedThisTurn || stack.stunnedByStorm) ? SKColor.hex(0xAEBACF) : Palette.brassGold
                )
                comp.position = CGPoint(x: 15, y: -8)
                comp.name = "terr_\(t.id)"
                plate.addChild(comp)
            } else {
                let nm = CoreTextLabelRenderer.makeLabelNode(t.name.uppercased(), fontSize: 8.5, color: SKColor.rgba(1, 1, 1, 0.72), bold: false)
                nm.position = CGPoint(x: 0, y: -8)
                nm.name = "terr_\(t.id)"
                plate.addChild(nm)
            }
        }

        // Storm Cloud Overlay
        if let stId = camp.stormTerritoryId {
            let p = CampaignMapCatalog.territories[stId].mapPos
            let cloud = SKSpriteNode(texture: SpriteFactory.shared.stormCloudTexture(c64: c64), size: CGSize(width: 64, height: 48))
            cloud.position = CGPoint(x: p.x + 28, y: p.y + 30)
            cloud.zPosition = 8
            worldLayer.addChild(cloud)
        }

        // Animated Paymaster Express along connected route
        if trainRoute.count >= 2 {
            let miniLoco = SKSpriteNode(texture: SpriteFactory.shared.locomotiveTexture(c64: c64), size: CGSize(width: 58, height: 30))
            miniLoco.position = CampaignMapCatalog.territories[trainRoute[0]].mapPos
            miniLoco.zPosition = 12
            worldLayer.addChild(miniLoco)
            AudioSynth.shared.trigger(.trainWhistle)
            var moves: [SKAction] = []
            for nextId in trainRoute.dropFirst() {
                let dest = CampaignMapCatalog.territories[nextId].mapPos
                moves.append(.move(to: dest, duration: 0.28))
            }
            moves.append(.run { AudioSynth.shared.trigger(.goldChime) })
            moves.append(.fadeOut(withDuration: 0.25))
            moves.append(.removeFromParent())
            miniLoco.run(.sequence(moves))
        }

        // Top Command Banner + Right Tactical Sidebar (Inside Universal Safe Box x: 145..1135, y: 135..665)
        let topBar = SKShapeNode(rectOf: CGSize(width: 980, height: 42), cornerRadius: 10)
        topBar.position = CGPoint(x: 640, y: 652)
        topBar.fillColor = SKColor.hex(0x0E182D).withAlphaComponent(0.95)
        topBar.strokeColor = Palette.factionColor(camp.activeFaction, c64: c64)
        topBar.lineWidth = 2.5
        hudLayer.addChild(topBar)

        let turnTxt = "\(camp.dateLabel) • TURN \(camp.turnNumber)   |   COMMAND: \(camp.activeFaction.displayName)   |   BLUE: \(camp.blueGold)G (\(camp.territoryCount(for: .unionBlue)) ST)   |   GRAY: \(camp.grayGold)G (\(camp.territoryCount(for: .grayCorps)) ST)"
        let topLbl = CoreTextLabelRenderer.makeLabelNode(turnTxt, fontSize: 12.5, color: .white)
        topLbl.position = CGPoint(x: 640, y: 652)
        hudLayer.addChild(topLbl)

        // Right Command Panel (x: 1055, width: 165 -> x: 972..1137, safely <= 1145!)
        let sidePanel = SKShapeNode(rectOf: CGSize(width: 168, height: 360), cornerRadius: 14)
        sidePanel.position = CGPoint(x: 1052, y: 435)
        sidePanel.fillColor = SKColor.hex(0x101B32).withAlphaComponent(0.94)
        sidePanel.strokeColor = Palette.brassGold
        sidePanel.lineWidth = 2.0
        hudLayer.addChild(sidePanel)

        let cmdTitle = CoreTextLabelRenderer.makeLabelNode("HQ ORDERS", fontSize: 14, color: Palette.brassGold)
        cmdTitle.position = CGPoint(x: 1052, y: 588)
        hudLayer.addChild(cmdTitle)

        let isHumanTurn = camp.playerMode.isHuman(camp.activeFaction)
        let canRecruit = isHumanTurn && camp.canRecruitArmy(for: camp.activeFaction) != nil
        hudLayer.addChild(makePillButton(
            name: "map_recruit",
            text: "RECRUIT (5G)",
            width: 148,
            pos: CGPoint(x: 1052, y: 535),
            accent: canRecruit ? Palette.emeraldWin : SKColor.hex(0x556684),
            height: 36
        ))

        hudLayer.addChild(makePillButton(
            name: "map_end_turn",
            text: isHumanTurn ? "END TURN ▶" : "AI THINKING...",
            width: 148,
            pos: CGPoint(x: 1052, y: 480),
            accent: isHumanTurn ? Palette.brassGold : SKColor.hex(0x788BA8),
            height: 38
        ))

        hudLayer.addChild(makePillButton(name: "btn_era", text: "ERA [V]", width: 148, pos: CGPoint(x: 1052, y: 415), accent: Palette.unionBright, height: 32))
        hudLayer.addChild(makePillButton(name: "btn_chip", text: "CHIP [B]", width: 148, pos: CGPoint(x: 1052, y: 370), accent: Palette.unionBright, height: 32))
        hudLayer.addChild(makePillButton(name: "map_menu", text: "TITLE MENU", width: 148, pos: CGPoint(x: 1052, y: 310), accent: SKColor.hex(0xFF867C), height: 32))
    }

    private func handleTerritoryTap(_ tid: Int) {
        guard let camp = campaign, camp.playerMode.isHuman(camp.activeFaction) else { return }

        if let sel = selectedTerritoryId {
            if sel == tid {
                selectedTerritoryId = nil
                AudioSynth.shared.trigger(.menuMove)
                renderStrategyMap()
                return
            }
            if CampaignMapCatalog.territories[sel].neighbors.contains(tid),
               let st = camp.armies[sel], st.faction == camp.activeFaction, !st.movedThisTurn, !st.stunnedByStorm {
                selectedTerritoryId = nil
                performMapMove(from: sel, to: tid)
                return
            }
        }

        if let st = camp.armies[tid], st.faction == camp.activeFaction {
            if st.stunnedByStorm {
                AudioSynth.shared.trigger(.thunderClap)
                showFloatingBanner("PINNED BY THUNDERSTORM!", color: Palette.warmAmber)
            } else if st.movedThisTurn {
                AudioSynth.shared.trigger(.menuMove)
                showFloatingBanner("ARMY ALREADY MARCHED THIS TURN", color: SKColor.hex(0xB8C7E0))
            } else {
                selectedTerritoryId = tid
                AudioSynth.shared.trigger(.menuSelect)
                HapticsManager.tap()
                renderStrategyMap()
            }
        }
    }

    private func performMapMove(from fromId: Int, to toId: Int) {
        guard let camp = campaign else { return }
        if let enc = camp.executeArmyMove(from: fromId, to: toId) {
            activeEncounter = enc
            switch enc {
            case .fieldBattle(_, _, let att, let def):
                let humanSide: Faction = camp.playerMode.isHuman(att.faction) ? att.faction : def.faction
                startFieldBattle(attacker: att, defender: def, humanFaction: humanSide)
            case .fortAssault(_, _, let att, let defFac, _):
                startFortAssault(attacker: att.faction, defender: defFac)
            case .trainHeist(let raider, let owner, _, _):
                startTrainHeist(raider: raider, trainOwner: owner)
            }
        } else {
            AudioSynth.shared.trigger(.cavalryBugle)
            HapticsManager.lightImpact()
            if let victor = camp.checkCampaignWinner() {
                concludeCampaign(winner: victor)
            } else {
                renderStrategyMap()
            }
        }
    }

    // MARK: - 3. Real-Time Tactical Field Battle (River Canyon + Destructible Bridge!)

    func startFieldBattle(attacker: ArmyStack, defender: ArmyStack, humanFaction: Faction) {
        mode = .fieldBattle
        clearAllModeNodes()
        AudioSynth.shared.setTrack(.fieldBattle)
        AudioSynth.shared.trigger(.cavalryBugle)

        battleUnits.removeAll()
        cannonShells.removeAll()
        musketBullets.removeAll()
        bridgeSpanHP = [2, 2, 2]
        battleResolvedWinner = nil
        battleEndCountdown = 0
        cannonPowerPhase = 0
        playerBattleFaction = humanFaction

        let blueStack = attacker.faction == .unionBlue ? attacker : defender
        let grayStack = attacker.faction == .grayCorps ? attacker : defender

        buildFieldBattleArena()

        var nextId = 1
        func spawnSide(_ stack: ArmyStack, isLeft: Bool) {
            let baseX: CGFloat = isLeft ? 215 : 1065
            let infX: CGFloat  = isLeft ? 375 : 905
            let cavX: CGFloat  = isLeft ? 295 : 985

            for i in 0..<max(1, stack.cannons) {
                let y: CGFloat = 245 + CGFloat(i) * 145
                addBattleUnit(id: nextId, faction: stack.faction, kind: .cannon, pos: CGPoint(x: baseX, y: y), hp: 4)
                nextId += 1
            }
            for i in 0..<stack.cavalry {
                let y: CGFloat = 260 + CGFloat(i) * 135
                addBattleUnit(id: nextId, faction: stack.faction, kind: .cavalry, pos: CGPoint(x: cavX, y: y), hp: 3)
                nextId += 1
            }
            for i in 0..<max(1, stack.infantry) {
                let y: CGFloat = 230 + CGFloat(i) * 140
                addBattleUnit(id: nextId, faction: stack.faction, kind: .infantry, pos: CGPoint(x: infX, y: y), hp: 3)
                nextId += 1
            }
        }

        spawnSide(blueStack, isLeft: true)
        spawnSide(grayStack, isLeft: false)

        let myUnits = battleUnits.filter { $0.faction == playerBattleFaction }
        battleInitialUnitCount = myUnits.count
        battleInitialHadCavalry = myUnits.contains { $0.kind == .cavalry }
        selectedUnitKind = myUnits.first?.kind ?? .cannon
        rebuildBattleHUD()
    }

    private func buildFieldBattleArena() {
        let c64 = isC64
        // Lush Meadow Ground
        let grass = SKSpriteNode(color: c64 ? Palette.c64Green : SKColor.hex(0x378B46), size: CGSize(width: 1280, height: 800))
        grass.position = CGPoint(x: 640, y: 400)
        worldLayer.addChild(grass)

        // Decorative meadow patches
        if !c64 {
            for (px, py) in [(260, 520), (410, 210), (870, 530), (1020, 220)] as [(CGFloat, CGFloat)] {
                let patch = SKShapeNode(ellipseOf: CGSize(width: 160, height: 90))
                patch.position = CGPoint(x: px, y: py)
                patch.fillColor = SKColor.hex(0x459F55).withAlphaComponent(0.45)
                patch.strokeColor = .clear
                worldLayer.addChild(patch)
            }
        }

        // Canyon River (x: 580..700) + Shallow Fords at y: 195 and y: 575
        let river = SKShapeNode(rect: CGRect(x: 580, y: 0, width: 120, height: 800))
        river.fillColor = c64 ? Palette.c64Cyan : Palette.riverCyan
        river.strokeColor = c64 ? Palette.c64Brown : SKColor.hex(0x6E4726)
        river.lineWidth = 5
        worldLayer.addChild(river)

        for fy in [195, 575] as [CGFloat] {
            let ford = SKShapeNode(rectOf: CGSize(width: 124, height: 48), cornerRadius: 8)
            ford.position = CGPoint(x: 640, y: fy)
            ford.fillColor = (c64 ? Palette.c64LightBlue : SKColor.hex(0x69DCFF)).withAlphaComponent(0.65)
            ford.strokeColor = .clear
            worldLayer.addChild(ford)
        }

        // 3-Span Destructible Wooden Bridge at center (y: 355..425)
        bridgeNodes.removeAll()
        for i in 0..<3 {
            let sx: CGFloat = 600 + CGFloat(i) * 40
            let span = SKShapeNode(rectOf: CGSize(width: 40, height: 74), cornerRadius: 4)
            span.position = CGPoint(x: sx, y: 390)
            span.fillColor = c64 ? Palette.c64Brown : SKColor.hex(0x8B5228)
            span.strokeColor = c64 ? Palette.c64Black : SKColor.hex(0x2D180A)
            span.lineWidth = 2.5
            worldLayer.addChild(span)
            bridgeNodes.append(span)
        }
    }

    private func addBattleUnit(id: Int, faction: Faction, kind: FieldUnitKind, pos: CGPoint, hp: Int) {
        let c64 = isC64
        let tex: SKTexture
        let sz: CGSize
        switch kind {
        case .cannon:
            tex = SpriteFactory.shared.cannonTexture(faction: faction, c64: c64)
            sz = CGSize(width: 68, height: 48)
        case .cavalry:
            tex = SpriteFactory.shared.cavalryTexture(faction: faction, gallopFrame: 0, c64: c64)
            sz = CGSize(width: 72, height: 62)
        case .infantry:
            tex = SpriteFactory.shared.soldierTexture(faction: faction, pose: .aim, c64: c64)
            sz = CGSize(width: 46, height: 54)
        }
        let node = SKSpriteNode(texture: tex, size: sz)
        node.position = pos
        node.xScale = (faction == .unionBlue) ? 1.0 : -1.0
        node.zPosition = 20
        worldLayer.addChild(node)
        battleUnits.append(BattleUnit(id: id, faction: faction, kind: kind, pos: pos, hp: hp, node: node))
    }

    private func refreshBattleTextures() {
        let c64 = isC64
        for u in battleUnits {
            switch u.kind {
            case .cannon:   u.node.texture = SpriteFactory.shared.cannonTexture(faction: u.faction, c64: c64)
            case .cavalry:  u.node.texture = SpriteFactory.shared.cavalryTexture(faction: u.faction, gallopFrame: 0, c64: c64)
            case .infantry: u.node.texture = SpriteFactory.shared.soldierTexture(faction: u.faction, pose: .aim, c64: c64)
            }
        }
        rebuildBattleHUD()
    }

    private func rebuildBattleHUD() {
        hudLayer.removeAllChildren()
        let c64 = isC64
        let blueAlive = battleUnits.filter { $0.faction == .unionBlue }.count
        let grayAlive = battleUnits.filter { $0.faction == .grayCorps }.count

        let bar = SKShapeNode(rectOf: CGSize(width: 980, height: 46), cornerRadius: 12)
        bar.position = CGPoint(x: 640, y: 650)
        bar.fillColor = SKColor.hex(0x0D172B).withAlphaComponent(0.92)
        bar.strokeColor = Palette.brassGold
        bar.lineWidth = 2.2
        hudLayer.addChild(bar)

        let bLbl = CoreTextLabelRenderer.makeLabelNode("BLUE UNITS: \(blueAlive)", fontSize: 14, color: Palette.unionBright)
        bLbl.position = CGPoint(x: 280, y: 650)
        hudLayer.addChild(bLbl)

        let cLbl = CoreTextLabelRenderer.makeLabelNode("ACTIVE: \(selectedUnitKind.label)  •  [TAB/ALT] SWITCH", fontSize: 14, color: c64 ? Palette.c64Yellow : Palette.brassGold)
        cLbl.position = CGPoint(x: 640, y: 650)
        cLbl.name = "hud_switch_unit"
        hudLayer.addChild(cLbl)

        let gLbl = CoreTextLabelRenderer.makeLabelNode("GRAY UNITS: \(grayAlive)", fontSize: 14, color: SKColor.hex(0xDCE6F7))
        gLbl.position = CGPoint(x: 1000, y: 650)
        hudLayer.addChild(gLbl)

        // Artillery Range Gauge bar underneath HUD when Cannon is selected
        let gaugeBg = SKShapeNode(rectOf: CGSize(width: 220, height: 12), cornerRadius: 6)
        gaugeBg.position = CGPoint(x: 640, y: 616)
        gaugeBg.fillColor = SKColor.hex(0x162440)
        gaugeBg.strokeColor = Palette.brassGold
        gaugeBg.name = "gauge_bg"
        let fill = SKShapeNode(rectOf: CGSize(width: 14, height: 10), cornerRadius: 4)
        fill.fillColor = Palette.warmAmber
        fill.strokeColor = .clear
        fill.name = "gauge_pip"
        gaugeBg.addChild(fill)
        hudLayer.addChild(gaugeBg)
    }

    private func switchNextBattleUnitKind() {
        let myKinds = Set(battleUnits.filter { $0.faction == playerBattleFaction }.map(\.kind))
        guard !myKinds.isEmpty else { return }
        let all = FieldUnitKind.allCases
        var idx = all.firstIndex(of: selectedUnitKind) ?? 0
        for _ in 0..<all.count {
            idx = (idx + 1) % all.count
            if myKinds.contains(all[idx]) {
                selectedUnitKind = all[idx]
                break
            }
        }
        AudioSynth.shared.trigger(.menuMove)
        HapticsManager.tap()
        rebuildBattleHUD()
    }

    private func fireUnitGroup(faction: Faction, kind: FieldUnitKind, powerRatio: CGFloat) {
        let dir: CGFloat = (faction == .unionBlue) ? 1.0 : -1.0
        for i in battleUnits.indices where battleUnits[i].faction == faction && battleUnits[i].kind == kind && battleUnits[i].dizzyTimer <= 0 {
            guard battleUnits[i].reloadTimer <= 0 else { continue }
            let origin = battleUnits[i].pos
            switch kind {
            case .cannon:
                battleUnits[i].reloadTimer = 1.35
                let range = 360.0 + powerRatio * 540.0
                let tx = max(160, min(1120, origin.x + dir * range))
                let ty = max(165, min(595, origin.y + CGFloat.random(in: -22...22)))
                spawnCannonShell(faction: faction, from: CGPoint(x: origin.x + dir * 32, y: origin.y + 10), to: CGPoint(x: tx, y: ty))
                spawnSmokePuff(at: CGPoint(x: origin.x + dir * 38, y: origin.y + 12), radius: 18)
                AudioSynth.shared.trigger(.cannonFire)
                HapticsManager.heavyImpact()

            case .infantry:
                battleUnits[i].reloadTimer = 0.55
                for spread in [-12, 0, 12] as [CGFloat] {
                    let b = SKShapeNode(circleOfRadius: 3.5)
                    b.fillColor = Palette.brassGold
                    b.strokeColor = .black
                    let start = CGPoint(x: origin.x + dir * 24, y: origin.y + 4)
                    b.position = start
                    fxLayer.addChild(b)
                    musketBullets.append(MusketBullet(faction: faction, pos: start, vx: dir * 520, vy: spread * 2.2, life: 1.05, node: b))
                }
                spawnSmokePuff(at: CGPoint(x: origin.x + dir * 26, y: origin.y + 6), radius: 10)
                AudioSynth.shared.trigger(.musketShot)
                HapticsManager.lightImpact()

            case .cavalry:
                battleUnits[i].reloadTimer = 0.85
                AudioSynth.shared.trigger(.cavalryBugle)
            }
        }
    }

    private func spawnCannonShell(faction: Faction, from: CGPoint, to: CGPoint) {
        let ball = SKShapeNode(circleOfRadius: 6.5)
        ball.fillColor = isC64 ? Palette.c64White : SKColor.hex(0x202634)
        ball.strokeColor = Palette.brassGold
        ball.lineWidth = 2.0
        ball.position = from
        ball.zPosition = 50
        fxLayer.addChild(ball)

        let sh = SKShapeNode(ellipseOf: CGSize(width: 14, height: 6))
        sh.fillColor = SKColor.rgba(0, 0, 0, 0.35)
        sh.strokeColor = .clear
        sh.position = from
        fxLayer.addChild(sh)

        cannonShells.append(CannonShell(faction: faction, start: from, target: to, elapsed: 0, duration: 0.78, node: ball, shadow: sh))
    }

    private func detonateShell(at pt: CGPoint, attacker: Faction) {
        spawnSmokePuff(at: pt, radius: 32, fiery: true)
        AudioSynth.shared.trigger(.explosionBridge)

        // Check wooden river bridge spans!
        for idx in 0..<bridgeNodes.count where bridgeSpanHP[idx] > 0 {
            let bx = 600 + CGFloat(idx) * 40
            if hypot(pt.x - bx, pt.y - 390) < 42 {
                bridgeSpanHP[idx] -= 1
                if bridgeSpanHP[idx] == 1 {
                    bridgeNodes[idx].fillColor = SKColor.hex(0x593115)
                } else {
                    bridgeNodes[idx].alpha = 0.14
                    showFloatingBanner("WOODEN BRIDGE SPAN DEMOLISHED!", color: Palette.warmAmber)
                    if attacker == playerBattleFaction, let m = PersistenceManager.shared.unlockMedal("bridge_buster") {
                        presentMedalToast(m)
                    }
                }
            }
        }

        // Splash damage to enemy battle units
        for idx in battleUnits.indices.reversed() {
            if battleUnits[idx].faction != attacker && hypot(battleUnits[idx].pos.x - pt.x, battleUnits[idx].pos.y - pt.y) < 54 {
                damageBattleUnit(at: idx, by: 2)
            }
        }
    }

    private func damageBattleUnit(at index: Int, by dmg: Int) {
        battleUnits[index].hp -= dmg
        battleUnits[index].dizzyTimer = 0.35
        AudioSynth.shared.trigger(.punchSlapstick)
        if battleUnits[index].hp <= 0 {
            let dead = battleUnits.remove(at: index)
            // Comic dizzy bounce-out animation (zero gore!)
            dead.node.texture = SpriteFactory.shared.soldierTexture(faction: dead.faction, pose: .dizzy, c64: isC64)
            dead.node.run(.sequence([
                .group([
                    .moveBy(x: 0, y: 26, duration: 0.35),
                    .fadeOut(withDuration: 0.45)
                ]),
                .removeFromParent()
            ]))
            AudioSynth.shared.trigger(.dizzyBoing)
            rebuildBattleHUD()
            if battleUnits.filter({ $0.faction == playerBattleFaction && $0.kind == selectedUnitKind }).isEmpty {
                switchNextBattleUnitKind()
            }
        }
    }

    // MARK: - 4. Side-Scrolling Fort Assault Mode

    func startFortAssault(attacker: Faction, defender: Faction) {
        mode = .fortAssault
        clearAllModeNodes()
        AudioSynth.shared.setTrack(.fortAssault)
        AudioSynth.shared.trigger(.fortAlarm)

        runnerFaction = attacker
        defenderFaction = defender
        runnerPos = CGPoint(x: 185, y: 210)
        runnerVel = .zero
        runnerGrounded = true
        runnerClimbing = false
        runnerDucking = false
        runnerDizzyTimer = 0
        runnerInvulnTimer = 0
        runnerPunchTimer = 0
        runnerStamina = 3
        actionTimerLeft = 60.0
        actionGoalX = 1075
        actionSpawnTimer = 1.6
        actionEndCountdown = 0
        actionWinner = nil
        actionEnemies.removeAll()
        scrollingProps.removeAll()

        rebuildFortBackdropAndHUD()
        spawnFortDefenders()
    }

    private func rebuildFortBackdropAndHUD() {
        worldLayer.removeAllChildren()
        hudLayer.removeAllChildren()
        let c64 = isC64

        let sky = SKSpriteNode(color: c64 ? Palette.c64Blue : SKColor.hex(0x1D3B73), size: CGSize(width: 1280, height: 800))
        sky.position = CGPoint(x: 640, y: 400)
        worldLayer.addChild(sky)

        // Timber Palisade Wall Background
        let wall = SKShapeNode(rect: CGRect(x: 135, y: 165, width: 1010, height: 420))
        wall.fillColor = c64 ? Palette.c64Brown : SKColor.hex(0x5A3820)
        wall.strokeColor = Palette.brassGold
        wall.lineWidth = 3
        worldLayer.addChild(wall)

        // 3 Walkable Rampart Decks: Ground y=180, Mid y=320, Top y=460
        let platforms: [CGRect] = [
            CGRect(x: 140, y: 165, width: 1000, height: 20),
            CGRect(x: 250, y: 305, width: 780,  height: 18),
            CGRect(x: 420, y: 445, width: 710,  height: 18),
        ]
        for r in platforms {
            let deck = SKShapeNode(rect: r)
            deck.fillColor = c64 ? Palette.c64Orange : SKColor.hex(0x8D5830)
            deck.strokeColor = SKColor.hex(0x26150A)
            deck.lineWidth = 2
            worldLayer.addChild(deck)
        }

        // Ladders at x=330 (Ground->Mid), x=640 (Ground->Mid), x=510 (Mid->Top), x=860 (Mid->Top)
        let ladders: [(CGFloat, CGFloat, CGFloat)] = [
            (330, 185, 323),
            (640, 185, 323),
            (510, 323, 463),
            (860, 323, 463),
        ]
        for (lx, y1, y2) in ladders {
            let lad = SKShapeNode(rect: CGRect(x: lx - 14, y: y1, width: 28, height: y2 - y1))
            lad.fillColor = SKColor.hex(0xB87E44).withAlphaComponent(0.45)
            lad.strokeColor = Palette.brassGold
            lad.lineWidth = 2.5
            worldLayer.addChild(lad)
            for ry in stride(from: y1 + 14, to: y2, by: 18) {
                let rung = SKShapeNode(rect: CGRect(x: lx - 14, y: ry, width: 28, height: 3))
                rung.fillColor = Palette.brassGold
                rung.strokeColor = .clear
                worldLayer.addChild(rung)
            }
        }

        // Objective Flagpole on Top Right Bastion (x=1075, y=463)
        let pole = SKShapeNode(rect: CGRect(x: 1072, y: 463, width: 6, height: 115))
        pole.fillColor = Palette.brassGold
        pole.strokeColor = .black
        worldLayer.addChild(pole)

        let flag = SKShapeNode(rectOf: CGSize(width: 58, height: 34), cornerRadius: 4)
        flag.position = CGPoint(x: 1042, y: 556)
        flag.fillColor = Palette.factionFill(defenderFaction, c64: c64)
        flag.strokeColor = Palette.brassGold
        flag.name = "fort_flag"
        worldLayer.addChild(flag)

        // Runner Sprite
        let rNode = SKSpriteNode(texture: SpriteFactory.shared.soldierTexture(faction: runnerFaction, pose: .marchA, c64: c64), size: CGSize(width: 48, height: 56))
        rNode.position = runnerPos
        rNode.zPosition = 30
        worldLayer.addChild(rNode)
        self.runnerNode = rNode

        // Re-attach existing enemies
        for i in actionEnemies.indices {
            worldLayer.addChild(actionEnemies[i].node)
        }

        buildActionHUD(title: "STORM THE FORT RAMPARTS! REACH THE FLAGPOLE!")
    }

    private func spawnFortDefenders() {
        let c64 = isC64
        // Patrol Guards & Hounds on Mid and Top Ramparts
        let specs: [(CGPoint, CGFloat, CGFloat, Bool)] = [
            (CGPoint(x: 520, y: 208), 380, 760, true),   // Guard Hound on Ground
            (CGPoint(x: 740, y: 348), 460, 960, false),  // Defender on Mid Rampart
            (CGPoint(x: 920, y: 488), 620, 1040, false), // Elite Guard near Flagpole
        ]
        for (pt, minX, maxX, hound) in specs {
            let tex = hound
                ? SpriteFactory.shared.guardHoundTexture(frame: 0, c64: c64)
                : SpriteFactory.shared.soldierTexture(faction: defenderFaction, pose: .marchA, c64: c64)
            let sz = hound ? CGSize(width: 48, height: 32) : CGSize(width: 46, height: 54)
            let n = SKSpriteNode(texture: tex, size: sz)
            n.position = pt
            n.zPosition = 28
            worldLayer.addChild(n)
            actionEnemies.append(ActionEnemy(pos: pt, vx: -115, minX: minX, maxX: maxX, isHound: hound, isBarrel: false, faction: defenderFaction, node: n))
        }
    }

    // MARK: - 5. Side-Scrolling Moving Steam Train Heist Mode

    func startTrainHeist(raider: Faction, trainOwner: Faction) {
        mode = .trainHeist
        clearAllModeNodes()
        AudioSynth.shared.setTrack(.trainHeist)
        AudioSynth.shared.trigger(.trainWhistle)

        runnerFaction = raider
        defenderFaction = trainOwner
        runnerPos = CGPoint(x: 215, y: 342)
        runnerVel = .zero
        runnerGrounded = true
        runnerClimbing = false
        runnerDucking = false
        runnerDizzyTimer = 0
        runnerInvulnTimer = 0
        runnerPunchTimer = 0
        runnerStamina = 3
        actionTimerLeft = 45.0
        actionGoalX = 985
        actionEndCountdown = 0
        actionWinner = nil
        overheadHazardX = 1360
        actionEnemies.removeAll()
        scrollingProps.removeAll()

        rebuildTrainBackdropAndHUD()
        spawnTrainGuards()
    }

    // Car roof spans in Train Heist: 4 boxcars + Locomotive Cab
    private let trainCarSpans: [(minX: CGFloat, maxX: CGFloat, roofY: CGFloat)] = [
        (165, 325, 316), // Caboose / Rear Car
        (350, 510, 316), // Freight Car
        (535, 695, 316), // Paymaster Gold Bullion Car
        (720, 880, 316), // Forward Guard Car
        (905, 1085, 330) // Steam Locomotive Cab & Boiler!
    ]

    private func rebuildTrainBackdropAndHUD() {
        worldLayer.removeAllChildren()
        hudLayer.removeAllChildren()
        scrollingProps.removeAll()
        let c64 = isC64

        // Prairie Sunset Sky & Desert Floor
        let sky = SKSpriteNode(color: c64 ? Palette.c64LightBlue : SKColor.hex(0x28569E), size: CGSize(width: 1280, height: 800))
        sky.position = CGPoint(x: 640, y: 400)
        worldLayer.addChild(sky)

        let desert = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 1280, height: 245))
        desert.fillColor = c64 ? Palette.c64Yellow : Palette.prairieSand
        desert.strokeColor = .clear
        worldLayer.addChild(desert)

        // Scrolling Telegraph Poles
        for px in stride(from: 120 as CGFloat, through: 1240, by: 220) {
            let pole = SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 155))
            pole.fillColor = c64 ? Palette.c64Brown : SKColor.hex(0x5E381B)
            pole.strokeColor = .clear
            pole.position = CGPoint(x: px, y: 235)
            let cross = SKShapeNode(rect: CGRect(x: -18, y: 138, width: 36, height: 5))
            cross.fillColor = pole.fillColor
            cross.strokeColor = .clear
            pole.addChild(cross)
            worldLayer.addChild(pole)
            scrollingProps.append(pole)
        }

        // Steel Rail Trackbed
        let rail = SKShapeNode(rect: CGRect(x: 0, y: 232, width: 1280, height: 8))
        rail.fillColor = c64 ? Palette.c64DarkGrey : SKColor.hex(0x2B3344)
        rail.strokeColor = Palette.brassGold
        worldLayer.addChild(rail)

        // 4 Boxcars + Steam Locomotive at Front
        for i in 0..<4 {
            let span = trainCarSpans[i]
            let car = SKSpriteNode(
                texture: SpriteFactory.shared.boxcarTexture(isPaymasterGold: i == 2, c64: c64),
                size: CGSize(width: span.maxX - span.minX + 8, height: 88)
            )
            car.position = CGPoint(x: (span.minX + span.maxX) * 0.5, y: 276)
            car.zPosition = 20
            worldLayer.addChild(car)
        }

        let loco = SKSpriteNode(texture: SpriteFactory.shared.locomotiveTexture(c64: c64), size: CGSize(width: 215, height: 112))
        loco.position = CGPoint(x: 1002, y: 288)
        loco.zPosition = 22
        worldLayer.addChild(loco)

        // Sweeping Overhead Signal Gantry Hazard (Duck under!)
        let gantry = SKShapeNode(rectOf: CGSize(width: 26, height: 48), cornerRadius: 4)
        gantry.fillColor = Palette.warmAmber
        gantry.strokeColor = .black
        gantry.lineWidth = 2
        gantry.position = CGPoint(x: overheadHazardX, y: 368)
        gantry.name = "train_gantry"
        gantry.zPosition = 32
        worldLayer.addChild(gantry)

        // Runner Sprite
        let rNode = SKSpriteNode(texture: SpriteFactory.shared.soldierTexture(faction: runnerFaction, pose: .marchA, c64: c64), size: CGSize(width: 48, height: 56))
        rNode.position = runnerPos
        rNode.zPosition = 30
        worldLayer.addChild(rNode)
        self.runnerNode = rNode

        for i in actionEnemies.indices {
            worldLayer.addChild(actionEnemies[i].node)
        }

        buildActionHUD(title: "GREAT TRAIN HEIST! LEAP CARS & SEIZE THE LOCOMOTIVE CAB!")
    }

    private func spawnTrainGuards() {
        let c64 = isC64
        for idx in [1, 2, 3] {
            let span = trainCarSpans[idx]
            let pt = CGPoint(x: (span.minX + span.maxX) * 0.5, y: span.roofY + 26)
            let g = SKSpriteNode(texture: SpriteFactory.shared.soldierTexture(faction: defenderFaction, pose: .marchA, c64: c64), size: CGSize(width: 46, height: 54))
            g.position = pt
            g.zPosition = 28
            worldLayer.addChild(g)
            actionEnemies.append(ActionEnemy(pos: pt, vx: -75, minX: span.minX + 18, maxX: span.maxX - 18, isHound: false, isBarrel: false, faction: defenderFaction, node: g))
        }
    }

    private func buildActionHUD(title: String) {
        let bar = SKShapeNode(rectOf: CGSize(width: 980, height: 46), cornerRadius: 12)
        bar.position = CGPoint(x: 640, y: 650)
        bar.fillColor = SKColor.hex(0x0E182D).withAlphaComponent(0.92)
        bar.strokeColor = Palette.brassGold
        bar.lineWidth = 2.2
        hudLayer.addChild(bar)

        let hearts = String(repeating: "★ ", count: max(0, runnerStamina))
        let hpLbl = CoreTextLabelRenderer.makeLabelNode("GRIT: \(hearts)", fontSize: 14, color: Palette.emeraldWin)
        hpLbl.position = CGPoint(x: 255, y: 650)
        hpLbl.name = "act_hp"
        hudLayer.addChild(hpLbl)

        let tLbl = CoreTextLabelRenderer.makeLabelNode(title, fontSize: 12.5, color: Palette.brassGold)
        tLbl.position = CGPoint(x: 640, y: 650)
        hudLayer.addChild(tLbl)

        let clkLbl = CoreTextLabelRenderer.makeLabelNode(String(format: "TIME: %02dS", Int(ceil(actionTimerLeft))), fontSize: 14, color: .white)
        clkLbl.position = CGPoint(x: 1025, y: 650)
        clkLbl.name = "act_clock"
        hudLayer.addChild(clkLbl)
    }

    // MARK: - 6. Victory & Encounter Resolution

    private func finishActionEncounter(winner: Faction) {
        if mode == .trainHeist && winner == runnerFaction {
            PersistenceManager.shared.recordTrainRobbed()
            if let m = PersistenceManager.shared.unlockMedal("train_robber") { presentMedalToast(m) }
        }
        if mode == .fortAssault && winner == runnerFaction {
            PersistenceManager.shared.recordFortCaptured()
            if let m = PersistenceManager.shared.unlockMedal("fort_stormer") { presentMedalToast(m) }
        }

        if isQuickSkirmish || campaign == nil {
            victoryFaction = winner
            victoryHeadline = "\(winner.displayName) TRIUMPHS!"
            victorySubline = mode == .trainHeist
                ? "Paymaster Gold Express captured at full steam!"
                : "Fortress ramparts stormed before the fuse ran out!"
            enterVictoryScreen()
            return
        }

        if let enc = activeEncounter, let camp = campaign {
            camp.resolveEncounterVictory(encounter: enc, winner: winner, survivingWinnerArmy: nil)
            activeEncounter = nil
            enterStrategyMap(runTurnIntro: false)
        }
    }

    private func finishFieldBattle(winner: Faction) {
        let surviving = battleUnits.filter { $0.faction == winner }
        let inf = min(3, max(1, surviving.filter { $0.kind == .infantry }.count))
        let cav = min(3, surviving.filter { $0.kind == .cavalry }.count)
        let can = min(3, surviving.filter { $0.kind == .cannon }.count)
        let survivorStack = ArmyStack(faction: winner, infantry: inf, cavalry: cav, cannons: can)

        if winner == playerBattleFaction {
            PersistenceManager.shared.recordBattleWin()
            if let m = PersistenceManager.shared.unlockMedal("first_skirmish") { presentMedalToast(m) }
            if battleInitialHadCavalry && cav > 0, let m = PersistenceManager.shared.unlockMedal("cavalry_sweep") { presentMedalToast(m) }
            if surviving.count >= battleInitialUnitCount, let m = PersistenceManager.shared.unlockMedal("flawless_battle") { presentMedalToast(m) }
            if PersistenceManager.shared.data.settings.aiDifficulty == .general, let m = PersistenceManager.shared.unlockMedal("general_rank") { presentMedalToast(m) }
        }

        if isQuickSkirmish || campaign == nil {
            victoryFaction = winner
            victoryHeadline = "\(winner.displayName) WINS THE FIELD!"
            victorySubline = "Surviving Battalions — Infantry: \(inf) • Cavalry: \(cav) • Artillery: \(can)"
            enterVictoryScreen()
            return
        }

        if let enc = activeEncounter, let camp = campaign {
            camp.resolveEncounterVictory(encounter: enc, winner: winner, survivingWinnerArmy: survivorStack)
            activeEncounter = nil
            enterStrategyMap(runTurnIntro: false)
        }
    }

    private func concludeCampaign(winner: Faction) {
        guard let camp = campaign else { return }
        let totalScore = (winner == .unionBlue ? camp.blueScore : camp.grayScore) + max(1000, (30 - camp.turnNumber) * 250)
        if camp.playerMode.isHuman(winner) {
            PersistenceManager.shared.recordCampaignWin(initials: "GEN", score: totalScore, year: camp.year.rawValue, faction: winner)
            if let m = PersistenceManager.shared.unlockMedal("campaign_victor") { presentMedalToast(m) }
            if camp.aiDifficulty == .general, let m = PersistenceManager.shared.unlockMedal("general_rank") { presentMedalToast(m) }
        }
        victoryFaction = winner
        victoryHeadline = "\(winner.displayName) UNIFIES THE IRON RAILS!"
        victorySubline = "Campaign \(camp.year.rawValue) Completed in \(camp.turnNumber) Turns • Final Score: \(totalScore)"
        enterVictoryScreen()
    }

    private func enterVictoryScreen() {
        mode = .victoryScreen
        clearAllModeNodes()
        AudioSynth.shared.setTrack(.victoryFanfare)
        AudioSynth.shared.trigger(.flagCapture)
        renderVictoryScreen()
    }

    private func renderVictoryScreen() {
        worldLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        let card = makeModalCard(title: victoryHeadline, subtitle: victorySubline)

        let cav = SKSpriteNode(texture: SpriteFactory.shared.cavalryTexture(faction: victoryFaction, gallopFrame: 0, c64: isC64), size: CGSize(width: 132, height: 114))
        cav.position = CGPoint(x: 640, y: 415)
        card.addChild(cav)

        let btn = makePillButton(name: "btn_modal_back", text: "RETURN TO COMMAND TENT", width: 340, pos: CGPoint(x: 640, y: 235), accent: Palette.emeraldWin, height: 46)
        card.addChild(btn)
        overlayLayer.addChild(card)
    }

    // MARK: - Frame Update Loop (120Hz ProMotion & Desktop Ready)

    override func update(_ currentTime: TimeInterval) {
        let rawDt = lastUpdateTime == 0 ? (1.0 / 60.0) : (currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        let dt = min(1.0 / 24.0, max(1.0 / 240.0, rawDt))
        guard !isUserPaused else { return }

        sceneClock += dt
        pollHardwareGamepads()

        switch mode {
        case .titleMenu:
            if let tr = titleTrainNode {
                tr.position.x += CGFloat(95.0 * dt)
                if tr.position.x > 1480 { tr.position.x = -240 }
                if Int(sceneClock * 6) % 3 == 0 && Double.random(in: 0...1) < 0.25 {
                    spawnSmokePuff(at: CGPoint(x: tr.position.x + 215, y: tr.position.y + 44), radius: 11)
                }
            }

        case .strategyMap:
            updateStrategyMapAI(dt: dt)

        case .fieldBattle:
            updateFieldBattle(dt: dt)

        case .fortAssault:
            updateFortAssault(dt: dt)

        case .trainHeist:
            updateTrainHeist(dt: dt)

        default:
            break
        }

        keyJustPressedPrimary = false
        keyJustPressedSecondary = false
        TouchInputState.shared.primaryJustPressed = false
        TouchInputState.shared.secondaryJustPressed = false
    }

    private func updateStrategyMapAI(dt: Double) {
        guard let camp = campaign, !camp.playerMode.isHuman(camp.activeFaction), activeEncounter == nil else { return }
        aiTurnTimer -= dt
        guard aiTurnTimer <= 0 else { return }
        aiTurnTimer = 0.75

        let decision = camp.chooseNextAIAction()
        if decision.recruit {
            if let rId = camp.recruitArmy(for: camp.activeFaction) {
                AudioSynth.shared.trigger(.goldChime)
                showFloatingBanner("\(camp.activeFaction.shortLabel) RECRUITED ARMY IN \(CampaignMapCatalog.territories[rId].code)!", color: Palette.brassGold)
                renderStrategyMap()
                return
            }
        }
        if let mv = decision.move {
            performMapMove(from: mv.from, to: mv.to)
            return
        }
        camp.endTurn()
        enterStrategyMap(runTurnIntro: true)
    }

    private func updateFieldBattle(dt: Double) {
        if let win = battleResolvedWinner {
            battleEndCountdown -= dt
            if battleEndCountdown <= 0 {
                finishFieldBattle(winner: win)
            }
            return
        }

        let blueCount = battleUnits.filter { $0.faction == .unionBlue }.count
        let grayCount = battleUnits.filter { $0.faction == .grayCorps }.count
        if blueCount == 0 || grayCount == 0 {
            battleResolvedWinner = blueCount > 0 ? .unionBlue : .grayCorps
            battleEndCountdown = 1.15
            AudioSynth.shared.trigger(.flagCapture)
            showFloatingBanner("\(battleResolvedWinner!.displayName) VICTORY!", color: Palette.emeraldWin)
            return
        }

        // Oscillate Cannon Power Gauge
        cannonPowerPhase += dt * 2.4
        let powerRatio = CGFloat((sin(cannonPowerPhase) + 1.0) * 0.5)
        if let bg = hudLayer.childNode(withName: "gauge_bg"), let pip = bg.childNode(withName: "gauge_pip") {
            pip.position.x = -100 + powerRatio * 200
            bg.alpha = (selectedUnitKind == .cannon) ? 1.0 : 0.25
        }

        // Gather Human Input
        let (dx, dy, firePressed, switchPressed) = readCombinedControls()
        if switchPressed {
            switchNextBattleUnitKind()
        }
        if firePressed {
            fireUnitGroup(faction: playerBattleFaction, kind: selectedUnitKind, powerRatio: powerRatio)
        }

        // Move Player's Selected Unit Group & Animate All Units
        let c64 = isC64
        for i in battleUnits.indices.reversed() {
            battleUnits[i].reloadTimer = max(0, battleUnits[i].reloadTimer - dt)
            battleUnits[i].dizzyTimer = max(0, battleUnits[i].dizzyTimer - dt)
            battleUnits[i].animPhase += dt * 7.5

            let isPlayerGroup = (battleUnits[i].faction == playerBattleFaction && battleUnits[i].kind == selectedUnitKind)
            battleUnits[i].node.alpha = isPlayerGroup ? 1.0 : 0.90

            if isPlayerGroup && battleUnits[i].dizzyTimer <= 0 {
                let speed: CGFloat = battleUnits[i].kind == .cavalry ? 205 : (battleUnits[i].kind == .infantry ? 125 : 95)
                var nx = battleUnits[i].pos.x + dx * speed * CGFloat(dt)
                let ny = max(175, min(585, battleUnits[i].pos.y + dy * speed * CGFloat(dt)))
                if battleUnits[i].kind == .cannon {
                    nx = playerBattleFaction == .unionBlue ? min(320, max(170, nx)) : max(960, min(1110, nx))
                } else {
                    nx = max(165, min(1115, nx))
                }
                battleUnits[i].pos = CGPoint(x: nx, y: ny)
            }

            // AI Commander Movement & Firing
            if battleUnits[i].faction != playerBattleFaction && battleUnits[i].dizzyTimer <= 0 {
                let aiDir: CGFloat = battleUnits[i].faction == .unionBlue ? 1.0 : -1.0
                if battleUnits[i].kind == .cavalry {
                    // Charge toward nearest ford or intact bridge!
                    let bridgeIntact = !bridgeSpanHP.contains(0)
                    let targetY: CGFloat = bridgeIntact ? 390 : (battleUnits[i].pos.y < 390 ? 195 : 575)
                    let vy: CGFloat = abs(battleUnits[i].pos.x - 640) < 130 ? (targetY - battleUnits[i].pos.y) * 2.2 : sin(CGFloat(sceneClock * 2.0 + Double(i))) * 45
                    battleUnits[i].pos.x += aiDir * 145 * CGFloat(dt)
                    battleUnits[i].pos.y = max(175, min(585, battleUnits[i].pos.y + vy * CGFloat(dt)))
                } else if battleUnits[i].kind == .infantry {
                    let holdX: CGFloat = battleUnits[i].faction == .unionBlue ? 470 : 810
                    if (aiDir > 0 && battleUnits[i].pos.x < holdX) || (aiDir < 0 && battleUnits[i].pos.x > holdX) {
                        battleUnits[i].pos.x += aiDir * 72 * CGFloat(dt)
                    }
                }
            }

            // Check River Hazard (crossing river x: 585..695 outside intact bridge or shallow fords!)
            let ux = battleUnits[i].pos.x
            let uy = battleUnits[i].pos.y
            if ux > 588 && ux < 692 {
                let onFord = abs(uy - 195) < 28 || abs(uy - 575) < 28
                let spanIdx = max(0, min(2, Int((ux - 580) / 40)))
                let onBridge = abs(uy - 390) < 38 && bridgeSpanHP[spanIdx] > 0
                if !onFord && !onBridge {
                    spawnSmokePuff(at: battleUnits[i].pos, radius: 20)
                    damageBattleUnit(at: i, by: 99)
                    continue
                }
            }

            // Cavalry Melee Saber Clash!
            if battleUnits[i].kind == .cavalry {
                let frame = Int(battleUnits[i].animPhase) % 2
                battleUnits[i].node.texture = SpriteFactory.shared.cavalryTexture(faction: battleUnits[i].faction, gallopFrame: frame, c64: c64)
                if let victimIdx = battleUnits.firstIndex(where: { $0.faction != battleUnits[i].faction && hypot($0.pos.x - ux, $0.pos.y - uy) < 42 }) {
                    if battleUnits[i].reloadTimer <= 0 {
                        battleUnits[i].reloadTimer = 0.55
                        damageBattleUnit(at: victimIdx, by: 2)
                        break
                    }
                }
            } else if battleUnits[i].kind == .infantry && (abs(dx) > 0.1 || abs(dy) > 0.1) && isPlayerGroup {
                let pose: SoldierPose = (Int(battleUnits[i].animPhase) % 2 == 0) ? .marchA : .marchB
                battleUnits[i].node.texture = SpriteFactory.shared.soldierTexture(faction: battleUnits[i].faction, pose: pose, c64: c64)
            }

            battleUnits[i].node.position = battleUnits[i].pos
        }

        // AI Periodic Volley & Cannon Fire
        aiBattleClock += dt
        let aiCadence = PersistenceManager.shared.data.settings.aiDifficulty == .general ? 0.85 : 1.25
        if aiBattleClock >= aiCadence {
            aiBattleClock = 0
            let aiSide = playerBattleFaction.opponent
            fireUnitGroup(faction: aiSide, kind: .cannon, powerRatio: CGFloat.random(in: 0.32...0.88))
            fireUnitGroup(faction: aiSide, kind: .infantry, powerRatio: 0.5)
        }

        // Update Parabolic Cannon Shells
        for idx in cannonShells.indices.reversed() {
            cannonShells[idx].elapsed += dt
            let t = min(1.0, cannonShells[idx].elapsed / cannonShells[idx].duration)
            let sx = cannonShells[idx].start.x + (cannonShells[idx].target.x - cannonShells[idx].start.x) * CGFloat(t)
            let sy = cannonShells[idx].start.y + (cannonShells[idx].target.y - cannonShells[idx].start.y) * CGFloat(t)
            let arc = CGFloat(sin(t * .pi)) * 115.0
            cannonShells[idx].node.position = CGPoint(x: sx, y: sy + arc)
            cannonShells[idx].shadow.position = CGPoint(x: sx, y: sy)
            if t >= 1.0 {
                let hitPt = cannonShells[idx].target
                let owner = cannonShells[idx].faction
                cannonShells[idx].node.removeFromParent()
                cannonShells[idx].shadow.removeFromParent()
                cannonShells.remove(at: idx)
                detonateShell(at: hitPt, attacker: owner)
            }
        }

        // Update Musket Volleys
        for idx in musketBullets.indices.reversed() {
            musketBullets[idx].life -= dt
            musketBullets[idx].pos.x += musketBullets[idx].vx * CGFloat(dt)
            musketBullets[idx].pos.y += musketBullets[idx].vy * CGFloat(dt)
            musketBullets[idx].node.position = musketBullets[idx].pos
            let bp = musketBullets[idx].pos
            let bf = musketBullets[idx].faction
            if let hitU = battleUnits.firstIndex(where: { $0.faction != bf && hypot($0.pos.x - bp.x, $0.pos.y - bp.y) < 28 }) {
                musketBullets[idx].node.removeFromParent()
                musketBullets.remove(at: idx)
                damageBattleUnit(at: hitU, by: 1)
                continue
            }
            if musketBullets[idx].life <= 0 {
                musketBullets[idx].node.removeFromParent()
                musketBullets.remove(at: idx)
            }
        }
    }

    // MARK: - Fort Assault & Train Heist Physics Loops

    private func updateFortAssault(dt: Double) {
        if let win = actionWinner {
            actionEndCountdown -= dt
            if actionEndCountdown <= 0 { finishActionEncounter(winner: win) }
            return
        }

        actionTimerLeft = max(0, actionTimerLeft - dt)
        updateActionHUDLabels()
        if actionTimerLeft <= 0 || runnerStamina <= 0 {
            actionWinner = defenderFaction
            actionEndCountdown = 1.1
            AudioSynth.shared.trigger(.explosionBridge)
            showFloatingBanner("FORT HELD BY DEFENDERS!", color: Palette.grayAccent)
            return
        }

        // Spawn Rolling TNT Barrel down ramparts periodically!
        actionSpawnTimer -= dt
        if actionSpawnTimer <= 0 {
            actionSpawnTimer = 2.6
            let yLvl: CGFloat = Bool.random() ? 482 : 342
            let b = SKSpriteNode(texture: SpriteFactory.shared.tntBarrelTexture(c64: isC64), size: CGSize(width: 32, height: 32))
            let start = CGPoint(x: 1030, y: yLvl)
            b.position = start
            b.zPosition = 29
            worldLayer.addChild(b)
            actionEnemies.append(ActionEnemy(pos: start, vx: -195, minX: 160, maxX: 1060, isHound: false, isBarrel: true, faction: defenderFaction, node: b))
        }

        let (dx, dy, punchPressed, jumpPressed) = readCombinedControls()
        runnerDizzyTimer = max(0, runnerDizzyTimer - dt)
        runnerInvulnTimer = max(0, runnerInvulnTimer - dt)
        runnerPunchTimer = max(0, runnerPunchTimer - dt)

        // Check Ladder Proximity
        let ladderZones: [(x: CGFloat, yMin: CGFloat, yMax: CGFloat)] = [
            (330, 185, 323), (640, 185, 323), (510, 323, 463), (860, 323, 463)
        ]
        let nearLadder = ladderZones.first { abs(runnerPos.x - $0.x) < 24 && runnerPos.y >= $0.yMin - 12 && runnerPos.y <= $0.yMax + 24 }

        if runnerDizzyTimer <= 0 {
            runnerPos.x = max(165, min(1110, runnerPos.x + dx * 225 * CGFloat(dt)))
            if let lad = nearLadder, abs(dy) > 0.25 {
                runnerClimbing = true
                runnerVel.dy = 0
                runnerPos.x = lad.x
                runnerPos.y = max(lad.yMin + 24, min(lad.yMax + 24, runnerPos.y + dy * 175 * CGFloat(dt)))
                runnerGrounded = true
            } else {
                runnerClimbing = false
                if (jumpPressed || dy > 0.65) && runnerGrounded {
                    runnerVel.dy = 430
                    runnerGrounded = false
                    AudioSynth.shared.trigger(.menuMove)
                }
                runnerVel.dy -= 980 * CGFloat(dt)
                runnerPos.y += runnerVel.dy * CGFloat(dt)

                // Deck landings
                runnerGrounded = false
                let decks: [(minX: CGFloat, maxX: CGFloat, topY: CGFloat)] = [
                    (420, 1130, 463),
                    (250, 1030, 323),
                    (140, 1140, 185)
                ]
                for d in decks {
                    if runnerPos.x >= d.minX && runnerPos.x <= d.maxX && runnerVel.dy <= 0 && runnerPos.y <= d.topY + 28 && runnerPos.y >= d.topY + 8 {
                        runnerPos.y = d.topY + 25
                        runnerVel.dy = 0
                        runnerGrounded = true
                        break
                    }
                }
            }

            if punchPressed {
                runnerPunchTimer = 0.25
                AudioSynth.shared.trigger(.punchSlapstick)
                punchNearbyActionEnemies()
            }
        }

        updateRunnerAndEnemiesCommon(dt: dt, dx: dx)

        // Check Flagpole Capture!
        if runnerPos.x >= actionGoalX - 18 && runnerPos.y >= 465 {
            if let fl = worldLayer.childNode(withName: "fort_flag") as? SKShapeNode {
                fl.fillColor = Palette.factionFill(runnerFaction, c64: isC64)
            }
            actionWinner = runnerFaction
            actionEndCountdown = 1.15
            AudioSynth.shared.trigger(.flagCapture)
            HapticsManager.success()
            showFloatingBanner("\(runnerFaction.displayName) SEIZES THE FORT!", color: Palette.emeraldWin)
        }
    }

    private func updateTrainHeist(dt: Double) {
        if let win = actionWinner {
            actionEndCountdown -= dt
            if actionEndCountdown <= 0 { finishActionEncounter(winner: win) }
            return
        }

        actionTimerLeft = max(0, actionTimerLeft - dt)
        updateActionHUDLabels()
        if actionTimerLeft <= 0 || runnerStamina <= 0 {
            actionWinner = defenderFaction
            actionEndCountdown = 1.1
            AudioSynth.shared.trigger(.trainWhistle)
            showFloatingBanner("TRAIN ESCAPED TO FORTIFIED STATION!", color: Palette.grayAccent)
            return
        }

        // Scroll Prairie Telegraph Poles & Locomotive Steam Puffs!
        for pole in scrollingProps {
            pole.position.x -= CGFloat(420 * dt)
            if pole.position.x < -40 { pole.position.x += 1320 }
        }
        if Int(sceneClock * 10) % 2 == 0 && Double.random(in: 0...1) < 0.35 {
            spawnSmokePuff(at: CGPoint(x: 1060, y: 350), radius: 14)
        }

        // Sweep Overhead Signal Gantry
        overheadHazardX -= CGFloat(280 * dt)
        if overheadHazardX < 110 { overheadHazardX = 1380 }
        if let g = worldLayer.childNode(withName: "train_gantry") {
            g.position.x = overheadHazardX
        }

        let (dx, dy, punchPressed, jumpPressed) = readCombinedControls()
        runnerDizzyTimer = max(0, runnerDizzyTimer - dt)
        runnerInvulnTimer = max(0, runnerInvulnTimer - dt)
        runnerPunchTimer = max(0, runnerPunchTimer - dt)
        runnerDucking = (dy < -0.45) && runnerGrounded

        if runnerDizzyTimer <= 0 {
            let moveSpeed: CGFloat = runnerDucking ? 95 : 215
            runnerPos.x = max(175, min(1065, runnerPos.x + dx * moveSpeed * CGFloat(dt)))
            if (jumpPressed || dy > 0.60) && runnerGrounded {
                runnerVel.dy = 415
                runnerGrounded = false
                AudioSynth.shared.trigger(.menuMove)
            }
            runnerVel.dy -= 980 * CGFloat(dt)
            runnerPos.y += runnerVel.dy * CGFloat(dt)

            // Land on Train Car Roofs (or tumble between couplings!)
            runnerGrounded = false
            for span in trainCarSpans {
                if runnerPos.x >= span.minX && runnerPos.x <= span.maxX && runnerVel.dy <= 0 && runnerPos.y <= span.roofY + 30 && runnerPos.y >= span.roofY + 8 {
                    runnerPos.y = span.roofY + 26
                    runnerVel.dy = 0
                    runnerGrounded = true
                    break
                }
            }

            // Fell between railcar couplings!
            if runnerPos.y < 235 {
                bonkRunner()
                runnerPos = CGPoint(x: max(195, runnerPos.x - 45), y: 355)
                runnerVel = .zero
            }

            // Overhead Signal Gantry Collision (unless ducking or jumping high!)
            if abs(runnerPos.x - overheadHazardX) < 22 && !runnerDucking && runnerPos.y < 388 && runnerInvulnTimer <= 0 {
                bonkRunner()
            }

            if punchPressed {
                runnerPunchTimer = 0.25
                AudioSynth.shared.trigger(.punchSlapstick)
                punchNearbyActionEnemies()
            }
        }

        runnerNode?.yScale = runnerDucking ? 0.68 : 1.0
        updateRunnerAndEnemiesCommon(dt: dt, dx: dx)

        // Reached Steam Locomotive Cab!
        if runnerPos.x >= actionGoalX {
            actionWinner = runnerFaction
            actionEndCountdown = 1.15
            AudioSynth.shared.trigger(.trainWhistle)
            AudioSynth.shared.trigger(.goldChime)
            HapticsManager.success()
            showFloatingBanner("LOCOMOTIVE & PAYMASTER GOLD CAPTURED!", color: Palette.emeraldWin)
        }
    }

    private func punchNearbyActionEnemies() {
        for i in actionEnemies.indices where !actionEnemies[i].isBarrel && actionEnemies[i].dizzyTimer <= 0 {
            if hypot(actionEnemies[i].pos.x - runnerPos.x, actionEnemies[i].pos.y - runnerPos.y) < 62 {
                actionEnemies[i].dizzyTimer = 3.5
                actionEnemies[i].node.texture = SpriteFactory.shared.soldierTexture(faction: actionEnemies[i].faction, pose: .dizzy, c64: isC64)
                actionEnemies[i].node.run(.sequence([
                    .moveBy(x: 24, y: 34, duration: 0.22),
                    .fadeOut(withDuration: 0.35)
                ]))
                AudioSynth.shared.trigger(.dizzyBoing)
                HapticsManager.mediumImpact()
            }
        }
    }

    private func bonkRunner() {
        guard runnerInvulnTimer <= 0 else { return }
        runnerStamina -= 1
        runnerDizzyTimer = 0.65
        runnerInvulnTimer = 1.45
        AudioSynth.shared.trigger(.dizzyBoing)
        HapticsManager.heavyImpact()
        updateActionHUDLabels()
    }

    private func updateRunnerAndEnemiesCommon(dt: Double, dx: CGFloat) {
        let c64 = isC64
        if let rn = runnerNode {
            rn.position = runnerPos
            if abs(dx) > 0.1 { rn.xScale = dx >= 0 ? 1.0 : -1.0 }
            let pose: SoldierPose
            if runnerDizzyTimer > 0 {
                pose = .dizzy
            } else if runnerPunchTimer > 0 {
                pose = .aim
            } else if abs(dx) > 0.1 {
                pose = (Int(sceneClock * 10) % 2 == 0) ? .marchA : .marchB
            } else {
                pose = .idle
            }
            rn.texture = SpriteFactory.shared.soldierTexture(faction: runnerFaction, pose: pose, c64: c64)
            rn.alpha = (runnerInvulnTimer > 0 && Int(sceneClock * 16) % 2 == 0) ? 0.45 : 1.0
        }

        for idx in actionEnemies.indices.reversed() {
            if actionEnemies[idx].dizzyTimer > 0 {
                actionEnemies[idx].dizzyTimer -= dt
                if actionEnemies[idx].dizzyTimer <= 2.8 {
                    actionEnemies[idx].node.removeFromParent()
                    actionEnemies.remove(at: idx)
                }
                continue
            }

            actionEnemies[idx].pos.x += actionEnemies[idx].vx * CGFloat(dt)
            if actionEnemies[idx].isBarrel {
                actionEnemies[idx].node.zRotation += CGFloat(dt * 8.0)
                if actionEnemies[idx].pos.x < actionEnemies[idx].minX {
                    actionEnemies[idx].node.removeFromParent()
                    actionEnemies.remove(at: idx)
                    continue
                }
            } else {
                if actionEnemies[idx].pos.x <= actionEnemies[idx].minX || actionEnemies[idx].pos.x >= actionEnemies[idx].maxX {
                    actionEnemies[idx].vx *= -1
                }
                actionEnemies[idx].node.xScale = actionEnemies[idx].vx >= 0 ? 1.0 : -1.0
                if actionEnemies[idx].isHound {
                    actionEnemies[idx].node.texture = SpriteFactory.shared.guardHoundTexture(frame: Int(sceneClock * 10) % 2, c64: c64)
                } else {
                    let p: SoldierPose = (Int(sceneClock * 8) % 2 == 0) ? .marchA : .marchB
                    actionEnemies[idx].node.texture = SpriteFactory.shared.soldierTexture(faction: actionEnemies[idx].faction, pose: p, c64: c64)
                }
            }
            actionEnemies[idx].node.position = actionEnemies[idx].pos

            if runnerInvulnTimer <= 0 && hypot(actionEnemies[idx].pos.x - runnerPos.x, actionEnemies[idx].pos.y - runnerPos.y) < 30 {
                bonkRunner()
            }
        }
    }

    private func updateActionHUDLabels() {
        if let hp = hudLayer.childNode(withName: "act_hp") as? SKLabelNode {
            hp.text = "GRIT: \(String(repeating: "★ ", count: max(0, runnerStamina)))"
        }
        if let clk = hudLayer.childNode(withName: "act_clock") as? SKLabelNode {
            clk.text = String(format: "TIME: %02dS", Int(ceil(actionTimerLeft)))
        }
    }

    // MARK: - Unified Controls Reader (Keyboard + Touch + Bluetooth Gamepad)

    private var padDX: CGFloat = 0
    private var padDY: CGFloat = 0
    private var padPrimaryPrev: Bool = false
    private var padSecondaryPrev: Bool = false
    private var padPrimaryJust: Bool = false
    private var padSecondaryJust: Bool = false

    private func pollHardwareGamepads() {
        #if canImport(GameController)
        guard let gp = GCController.controllers().first?.extendedGamepad else {
            padDX = 0; padDY = 0; return
        }
        let lx = CGFloat(gp.leftThumbstick.xAxis.value)
        let ly = CGFloat(gp.leftThumbstick.yAxis.value)
        let dx = abs(lx) > 0.15 ? lx : CGFloat((gp.dpad.right.isPressed ? 1 : 0) - (gp.dpad.left.isPressed ? 1 : 0))
        let dy = abs(ly) > 0.15 ? ly : CGFloat((gp.dpad.up.isPressed ? 1 : 0) - (gp.dpad.down.isPressed ? 1 : 0))
        padDX = dx
        padDY = dy
        let pNow = gp.buttonA.isPressed || gp.rightTrigger.isPressed
        let sNow = gp.buttonB.isPressed || gp.buttonX.isPressed || gp.leftShoulder.isPressed
        if pNow && !padPrimaryPrev { padPrimaryJust = true }
        if sNow && !padSecondaryPrev { padSecondaryJust = true }
        padPrimaryPrev = pNow
        padSecondaryPrev = sNow
        #endif
    }

    private func readCombinedControls() -> (dx: CGFloat, dy: CGFloat, primaryJust: Bool, secondaryJust: Bool) {
        var dx = TouchInputState.shared.moveDX + padDX
        var dy = TouchInputState.shared.moveDY + padDY

        // macOS KeyCodes: Left=123, Right=124, Down=125, Up=126, A=0, D=2, S=1, W=13
        if keysHeld.contains(123) || keysHeld.contains(0)  { dx -= 1 }
        if keysHeld.contains(124) || keysHeld.contains(2)  { dx += 1 }
        if keysHeld.contains(125) || keysHeld.contains(1)  { dy -= 1 }
        if keysHeld.contains(126) || keysHeld.contains(13) { dy += 1 }

        dx = max(-1, min(1, dx))
        dy = max(-1, min(1, dy))

        let p = keyJustPressedPrimary || TouchInputState.shared.primaryJustPressed || padPrimaryJust
        let s = keyJustPressedSecondary || TouchInputState.shared.secondaryJustPressed || padSecondaryJust
        padPrimaryJust = false
        padSecondaryJust = false
        return (dx, dy, p, s)
    }

    // MARK: - Pointer / Touch Handling (Universal macOS & iOS)

    private func handlePointerDown(at pt: CGPoint) {
        if isUserPaused {
            let hit = nodes(at: pt)
            if hit.contains(where: { $0.name == "pause_resume" }) {
                togglePauseFromUI()
            } else if hit.contains(where: { $0.name == "pause_quit" }) {
                enterTitleMenu()
            }
            return
        }

        let hitNodes = nodes(at: pt)
        for n in hitNodes {
            guard let nm = n.name else { continue }
            if nm == "btn_era" || nm == "set_theme" {
                cycleVisualTheme()
                return
            }
            if nm == "btn_chip" || nm == "set_chip" {
                cycleAudioChip()
                return
            }
            if nm == "gag_cannon" {
                // Classic 1989 North & South interactive title-screen gag!
                AudioSynth.shared.trigger(.cannonFire)
                AudioSynth.shared.trigger(.dizzyBoing)
                spawnSmokePuff(at: CGPoint(x: 285, y: 215), radius: 26, fiery: true)
                titleCannonNode?.run(.sequence([.moveBy(x: -12, y: 0, duration: 0.06), .moveBy(x: 12, y: 0, duration: 0.14)]))
                showFloatingBanner("BOOM! MIND YOUR KEPI, GENERAL!", color: Palette.brassGold)
                return
            }
            if nm.hasPrefix("menu_row_"), let idx = Int(nm.replacingOccurrences(of: "menu_row_", with: "")) {
                menuIndex = idx
                rebuildTitleMenuButtons()
                activateTitleMenuSelection()
                return
            }
            if nm == "btn_modal_back" || nm == "map_menu" {
                AudioSynth.shared.trigger(.menuSelect)
                enterTitleMenu()
                return
            }
            if nm == "opt_year" {
                let all = CampaignYear.allCases
                setupYear = all[((all.firstIndex(of: setupYear) ?? 0) + 1) % all.count]
                AudioSynth.shared.trigger(.menuMove)
                showCampaignSetup()
                return
            }
            if nm == "opt_mode" {
                let all = PlayerMode.allCases
                setupMode = all[((all.firstIndex(of: setupMode) ?? 0) + 1) % all.count]
                AudioSynth.shared.trigger(.menuMove)
                showCampaignSetup()
                return
            }
            if nm == "opt_diff" {
                let all = AIDifficulty.allCases
                setupDiff = all[((all.firstIndex(of: setupDiff) ?? 0) + 1) % all.count]
                PersistenceManager.shared.updateSettings { $0.aiDifficulty = setupDiff }
                AudioSynth.shared.trigger(.menuMove)
                showCampaignSetup()
                return
            }
            if nm == "btn_launch_campaign" {
                AudioSynth.shared.trigger(.cavalryBugle)
                startNewCampaign(year: setupYear, playerMode: setupMode, difficulty: setupDiff)
                return
            }
            if nm == "set_storm" {
                PersistenceManager.shared.updateSettings { $0.stormEventsEnabled.toggle() }
                AudioSynth.shared.trigger(.menuMove)
                showSettingsOverlay()
                return
            }
            if nm == "set_music" {
                PersistenceManager.shared.updateSettings {
                    let v = $0.musicVolume - 0.25
                    $0.musicVolume = v < -0.05 ? 1.0 : max(0.0, v)
                }
                AudioSynth.shared.syncSettings(PersistenceManager.shared.data.settings)
                showSettingsOverlay()
                return
            }
            if nm == "set_sfx" {
                PersistenceManager.shared.updateSettings {
                    let v = $0.sfxVolume - 0.25
                    $0.sfxVolume = v < -0.05 ? 1.0 : max(0.0, v)
                }
                AudioSynth.shared.syncSettings(PersistenceManager.shared.data.settings)
                AudioSynth.shared.trigger(.cannonFire)
                showSettingsOverlay()
                return
            }
            if nm == "map_recruit", let camp = campaign, camp.playerMode.isHuman(camp.activeFaction) {
                if let rId = camp.recruitArmy(for: camp.activeFaction) {
                    AudioSynth.shared.trigger(.goldChime)
                    showFloatingBanner("NEW ARMY MUSTERED IN \(CampaignMapCatalog.territories[rId].name.uppercased())!", color: Palette.emeraldWin)
                    renderStrategyMap()
                } else {
                    AudioSynth.shared.trigger(.menuMove)
                    showFloatingBanner("NEED 5 GOLD TO RECRUIT AN ARMY!", color: Palette.warmAmber)
                }
                return
            }
            if nm == "map_end_turn", let camp = campaign, camp.playerMode.isHuman(camp.activeFaction) {
                selectedTerritoryId = nil
                camp.endTurn()
                enterStrategyMap(runTurnIntro: true)
                return
            }
            if nm.hasPrefix("terr_"), let tid = Int(nm.replacingOccurrences(of: "terr_", with: "")) {
                handleTerritoryTap(tid)
                return
            }
            if nm == "hud_switch_unit" {
                switchNextBattleUnitKind()
                return
            }
        }

        // Direct tap on Field Battle fires active unit (or selects tapped friendly unit!)
        if mode == .fieldBattle {
            if let tapped = battleUnits.first(where: { $0.faction == playerBattleFaction && hypot($0.pos.x - pt.x, $0.pos.y - pt.y) < 42 }) {
                selectedUnitKind = tapped.kind
                AudioSynth.shared.trigger(.menuMove)
                rebuildBattleHUD()
            } else {
                keyJustPressedPrimary = true
            }
        }
    }

    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        handlePointerDown(at: t.location(in: self))
    }
    #else
    override func mouseDown(with event: NSEvent) {
        handlePointerDown(at: event.location(in: self))
    }

    override func rightMouseDown(with event: NSEvent) {
        keyJustPressedSecondary = true
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        let code = event.keyCode
        keysHeld.insert(code)

        // V = 9 (Visual Era), B = 11 (Audio Chip), P / Esc = 35 / 53
        if code == 9  { cycleVisualTheme(); return }
        if code == 11 { cycleAudioChip(); return }
        if code == 35 || code == 53 {
            if mode == .titleMenu { return }
            if mode == .campaignSetup || mode == .medalsOverlay || mode == .howToPlayOverlay || mode == .settingsOverlay || mode == .victoryScreen {
                enterTitleMenu()
                return
            }
            togglePauseFromUI()
            return
        }

        if mode == .titleMenu {
            if code == 126 || code == 13 { // Up / W
                menuIndex = (menuIndex - 1 + titleMenuItems.count) % titleMenuItems.count
                AudioSynth.shared.trigger(.menuMove)
                rebuildTitleMenuButtons()
            } else if code == 125 || code == 1 { // Down / S
                menuIndex = (menuIndex + 1) % titleMenuItems.count
                AudioSynth.shared.trigger(.menuMove)
                rebuildTitleMenuButtons()
            } else if code == 36 || code == 49 { // Return / Space
                activateTitleMenuSelection()
            }
            return
        }

        if mode == .strategyMap, let camp = campaign, camp.playerMode.isHuman(camp.activeFaction) {
            if code == 15 { // R = Recruit
                if let _ = camp.recruitArmy(for: camp.activeFaction) {
                    AudioSynth.shared.trigger(.goldChime)
                    renderStrategyMap()
                }
            } else if code == 14 || code == 36 { // E / Return = End Turn
                selectedTerritoryId = nil
                camp.endTurn()
                enterStrategyMap(runTurnIntro: true)
            }
            return
        }

        // Space (49) / Z (6) / Return (36) = Primary Action (Fire / Punch)
        if code == 49 || code == 6 || code == 36 {
            keyJustPressedPrimary = true
        }
        // Tab (48) / X (7) / Shift (56) = Secondary Action (Switch Unit / Jump)
        if code == 48 || code == 7 || code == 56 {
            keyJustPressedSecondary = true
        }
    }

    override func keyUp(with event: NSEvent) {
        keysHeld.remove(event.keyCode)
    }
    #endif

    // MARK: - Visual FX, Floating Banners, Pause Modal & Medal Toast

    private func spawnSmokePuff(at pt: CGPoint, radius: CGFloat, fiery: Bool = false) {
        let puff = SKShapeNode(circleOfRadius: radius)
        puff.position = pt
        puff.fillColor = fiery ? Palette.warmAmber : SKColor.rgba(1, 1, 1, 0.88)
        puff.strokeColor = isC64 ? Palette.c64Black : SKColor.rgba(0.1, 0.1, 0.15, 0.5)
        puff.lineWidth = 1.5
        puff.zPosition = 45
        fxLayer.addChild(puff)
        puff.run(.sequence([
            .group([
                .scale(to: 1.85, duration: 0.36),
                .fadeOut(withDuration: 0.36)
            ]),
            .removeFromParent()
        ]))
    }

    private func showFloatingBanner(_ text: String, color: SKColor) {
        hudLayer.childNode(withName: "float_banner")?.removeFromParent()
        let b = SKShapeNode(rectOf: CGSize(width: 560, height: 34), cornerRadius: 10)
        b.position = CGPoint(x: mode == .strategyMap ? 585 : 640, y: mode == .strategyMap ? 604 : 582)
        b.fillColor = SKColor.hex(0x0D162A).withAlphaComponent(0.95)
        b.strokeColor = color
        b.lineWidth = 2.0
        b.name = "float_banner"
        let l = CoreTextLabelRenderer.makeLabelNode(text, fontSize: 13.5, color: color)
        b.addChild(l)
        hudLayer.addChild(b)
        b.run(.sequence([.wait(forDuration: 1.8), .fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    private func presentMedalToast(_ medal: MedalDefinition) {
        medalToastNode?.removeFromParent()
        let toast = SKShapeNode(rectOf: CGSize(width: 420, height: 52), cornerRadius: 12)
        toast.position = CGPoint(x: 640, y: 158)
        toast.fillColor = SKColor.hex(0x18392B)
        toast.strokeColor = Palette.brassGold
        toast.lineWidth = 2.5
        let t = CoreTextLabelRenderer.makeLabelNode("★ MEDAL UNLOCKED: \(medal.title)", fontSize: 13, color: Palette.brassGold)
        t.position = CGPoint(x: 0, y: 8)
        let s = CoreTextLabelRenderer.makeLabelNode(medal.subtitle, fontSize: 10.5, color: .white, bold: false)
        s.position = CGPoint(x: 0, y: -10)
        toast.addChild(t)
        toast.addChild(s)
        overlayLayer.addChild(toast)
        medalToastNode = toast
        toast.run(.sequence([.wait(forDuration: 2.8), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    private func rebuildPauseOverlay() {
        overlayLayer.removeAllChildren()
        guard isUserPaused else { return }
        let card = makeModalCard(title: "COMMAND PAUSED", subtitle: "Press P / ESC or Tap Resume to Continue")
        card.addChild(makePillButton(name: "pause_resume", text: "▶ RESUME ACTION", width: 320, pos: CGPoint(x: 640, y: 385), accent: Palette.emeraldWin, height: 46))
        card.addChild(makePillButton(name: "pause_quit", text: "RETURN TO COMMAND TENT", width: 320, pos: CGPoint(x: 640, y: 310), accent: Palette.brassGold, height: 42))
        overlayLayer.addChild(card)
    }

    // MARK: - Deterministic App Store Screenshot Staging (Shots 1..6) & 60fps Trailer Autopilot

    func stageAppStoreScreenshot(index: Int, isMobile: Bool) {
        PersistenceManager.shared.updateSettings {
            $0.visualTheme = (index == 5) ? .c64Retro : .hdOverdrive
            $0.audioChip = (index == 5) ? .c64SID : .modernSynth
        }
        rebuildCRTOverlay()

        switch index {
        case 1:
            // Shot 1: Explosive HD Comic River-Bridge Field Battle!
            isQuickSkirmish = true
            startFieldBattle(
                attacker: ArmyStack(faction: .unionBlue, infantry: 3, cavalry: 2, cannons: 2),
                defender: ArmyStack(faction: .grayCorps, infantry: 3, cavalry: 2, cannons: 2),
                humanFaction: .unionBlue
            )
            // Advance units into dramatic mid-bridge clash + cannonballs & smoke!
            if battleUnits.count >= 6 {
                battleUnits[2].pos = CGPoint(x: 545, y: 392)
                battleUnits[2].node.position = battleUnits[2].pos
                battleUnits[4].pos = CGPoint(x: 475, y: 310)
                battleUnits[4].node.position = battleUnits[4].pos
                battleUnits[9].pos = CGPoint(x: 725, y: 392)
                battleUnits[9].node.position = battleUnits[9].pos
            }
            spawnCannonShell(faction: .unionBlue, from: CGPoint(x: 250, y: 390), to: CGPoint(x: 640, y: 390))
            if !cannonShells.isEmpty {
                cannonShells[0].elapsed = 0.42
                cannonShells[0].node.position = CGPoint(x: 485, y: 495)
            }
            spawnSmokePuff(at: CGPoint(x: 255, y: 398), radius: 24, fiery: true)
            spawnSmokePuff(at: CGPoint(x: 638, y: 395), radius: 30, fiery: true)
            showFloatingBanner("DESTRUCTIBLE BRIDGE ARTILLERY & CAVALRY CLASH!", color: Palette.brassGold)

        case 2:
            // Shot 2: High-Speed Steam Train Heist!
            isQuickSkirmish = true
            startTrainHeist(raider: .unionBlue, trainOwner: .grayCorps)
            runnerPos = CGPoint(x: 522, y: 392) // Mid-leap onto Paymaster Gold Bullion Car!
            runnerNode?.position = runnerPos
            overheadHazardX = 765
            worldLayer.childNode(withName: "train_gantry")?.position.x = overheadHazardX
            spawnSmokePuff(at: CGPoint(x: 1060, y: 365), radius: 22)
            spawnSmokePuff(at: CGPoint(x: 1015, y: 382), radius: 16)
            showFloatingBanner("LEAP SWAYING GOLD CARS & SEIZE THE LOCOMOTIVE!", color: Palette.emeraldWin)

        case 3:
            // Shot 3: Grand North American Railway Strategy Map (1863)!
            startNewCampaign(year: .y1863, playerMode: .unionVsAI, difficulty: .colonel)
            selectedTerritoryId = 6 // Kentucky selected showing glowing green target rings!
            renderStrategyMap(trainRoute: [0, 2, 5, 9, 10])
            showFloatingBanner("1861–1864 CONTINENTAL RAILWAY STRATEGY!", color: Palette.brassGold)

        case 4:
            // Shot 4: Frantic Timber Fort Assault!
            isQuickSkirmish = true
            startFortAssault(attacker: .unionBlue, defender: .grayCorps)
            runnerPos = CGPoint(x: 695, y: 348)
            runnerNode?.position = runnerPos
            let tnt = SKSpriteNode(texture: SpriteFactory.shared.tntBarrelTexture(c64: false), size: CGSize(width: 34, height: 34))
            tnt.position = CGPoint(x: 810, y: 342)
            tnt.zPosition = 29
            worldLayer.addChild(tnt)
            actionTimerLeft = 42
            updateActionHUDLabels()
            showFloatingBanner("STORM 3-TIER FORT RAMPARTS BEFORE THE FUSE BURNS OUT!", color: Palette.warmAmber)

        case 5:
            // Shot 5: Authentic 1989 C64 16-Color Retro + SID 6581 Mode!
            isQuickSkirmish = true
            startFieldBattle(
                attacker: .veteran(for: .unionBlue),
                defender: .veteran(for: .grayCorps),
                humanFaction: .unionBlue
            )
            spawnSmokePuff(at: CGPoint(x: 640, y: 390), radius: 26, fiery: true)
            showFloatingBanner("LIVE 1989 C64 16-COLOR PIXEL & SID 6581 MODE!", color: Palette.c64Yellow)

        default:
            // Shot 6: Interactive Command Tent Title Screen!
            enterTitleMenu()
            titleTrainNode?.position.x = 590
        }
    }

    // Drives smooth 60fps Launch Trailers & Uncut App Review Walkthrough Video
    func applyTrailerAutopilot(frame: Int, includeTitleIntro: Bool = false) {
        isAutopilotActive = true
        let f = includeTitleIntro ? frame : (frame + 180)

        if f == 0 {
            PersistenceManager.shared.updateSettings {
                $0.visualTheme = .hdOverdrive
                $0.audioChip = .modernSynth
            }
            rebuildCRTOverlay()
            enterTitleMenu()
        } else if f == 90 && includeTitleIntro {
            handlePointerDown(at: CGPoint(x: 235, y: 195)) // Fire title gag cannon!
        } else if f == 180 {
            startNewCampaign(year: .y1863, playerMode: .unionVsAI, difficulty: .colonel)
            selectedTerritoryId = 6
            renderStrategyMap(trainRoute: [0, 2, 5, 9, 10])
        } else if f == 330 {
            isQuickSkirmish = true
            startFieldBattle(
                attacker: ArmyStack(faction: .unionBlue, infantry: 3, cavalry: 2, cannons: 2),
                defender: ArmyStack(faction: .grayCorps, infantry: 3, cavalry: 2, cannons: 2),
                humanFaction: .unionBlue
            )
        } else if f > 330 && f < 630 {
            if f % 38 == 0 { keyJustPressedPrimary = true }
            if f == 450 { selectedUnitKind = .cavalry; rebuildBattleHUD() }
            if f > 450 && f < 560 { TouchInputState.shared.moveDX = 1.0 } else { TouchInputState.shared.moveDX = 0 }
        } else if f == 630 {
            TouchInputState.shared.reset()
            startTrainHeist(raider: .unionBlue, trainOwner: .grayCorps)
        } else if f > 630 && f < 860 {
            TouchInputState.shared.moveDX = 0.85
            if f % 42 == 0 { TouchInputState.shared.secondaryJustPressed = true }
            if f % 28 == 0 { TouchInputState.shared.primaryJustPressed = true }
        } else if f == 860 {
            TouchInputState.shared.reset()
            startFortAssault(attacker: .unionBlue, defender: .grayCorps)
        } else if f > 860 && f < 1040 {
            TouchInputState.shared.moveDX = 0.8
            if f == 945 {
                // Live switch to 1989 C64 Retro + SID 6581 mid-action!
                cycleVisualTheme()
                cycleVisualTheme()
                cycleAudioChip()
            }
            if f % 36 == 0 { TouchInputState.shared.secondaryJustPressed = true }
        }

        let simTime = TimeInterval(frame) / 60.0 + 1.0
        update(simTime)
    }
}
