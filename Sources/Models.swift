import Foundation
import SpriteKit

// MARK: - Core Factions, Modes & Settings

enum Faction: String, Codable, CaseIterable {
    case unionBlue
    case grayCorps

    var displayName: String {
        switch self {
        case .unionBlue: return "UNION BLUE"
        case .grayCorps: return "GRAY CORPS"
        }
    }

    var shortLabel: String {
        switch self {
        case .unionBlue: return "BLUE"
        case .grayCorps: return "GRAY"
        }
    }

    var opponent: Faction {
        self == .unionBlue ? .grayCorps : .unionBlue
    }
}

enum CampaignYear: Int, Codable, CaseIterable {
    case y1861 = 1861
    case y1862 = 1862
    case y1863 = 1863
    case y1864 = 1864

    var title: String {
        switch self {
        case .y1861: return "1861 • DAWN OF IRON RAILS"
        case .y1862: return "1862 • RIVER VALLEY CLASH"
        case .y1863: return "1863 • TURNING OF THE TIDE"
        case .y1864: return "1864 • GRAND RAIL CAMPAIGN"
        }
    }
}

enum PlayerMode: String, Codable, CaseIterable {
    case unionVsAI
    case grayVsAI
    case twoPlayerLocal

    var label: String {
        switch self {
        case .unionVsAI:      return "1P: UNION BLUE VS AI"
        case .grayVsAI:       return "1P: GRAY CORPS VS AI"
        case .twoPlayerLocal: return "2P: PASS & PLAY / COUCH"
        }
    }

    func isHuman(_ faction: Faction) -> Bool {
        switch self {
        case .unionVsAI:      return faction == .unionBlue
        case .grayVsAI:       return faction == .grayCorps
        case .twoPlayerLocal: return true
        }
    }
}

enum AIDifficulty: String, Codable, CaseIterable {
    case recruit
    case colonel
    case general

    var label: String {
        switch self {
        case .recruit: return "RECRUIT"
        case .colonel: return "COLONEL"
        case .general: return "GENERAL"
        }
    }
}

enum VisualTheme: String, Codable, CaseIterable {
    case hdOverdrive
    case crtCabinet
    case c64Retro

    var label: String {
        switch self {
        case .hdOverdrive: return "2026 HD COMIC"
        case .crtCabinet:  return "CRT ARCADE"
        case .c64Retro:    return "1989 C64 RETRO"
        }
    }

    func next() -> VisualTheme {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

enum AudioChipMode: String, Codable, CaseIterable {
    case modernSynth
    case c64SID

    var label: String {
        switch self {
        case .modernSynth: return "BRASS & RAGTIME"
        case .c64SID:      return "C64 SID 6581"
        }
    }

    func next() -> AudioChipMode {
        self == .modernSynth ? .c64SID : .modernSynth
    }
}

// MARK: - Color Palettes (HD Illustrated Arcade + Authentic 16-Color 1989 C64 Pepto)

enum Palette {
    // 16-Color C64 Pepto Palette
    static let c64Black      = SKColor.hex(0x000000)
    static let c64White      = SKColor.hex(0xFFFFFF)
    static let c64Red        = SKColor.hex(0x68372B)
    static let c64Cyan       = SKColor.hex(0x70A4B2)
    static let c64Purple     = SKColor.hex(0x6F3D86)
    static let c64Green      = SKColor.hex(0x588D43)
    static let c64Blue       = SKColor.hex(0x352879)
    static let c64Yellow     = SKColor.hex(0xB8C76F)
    static let c64Orange     = SKColor.hex(0x6F4F25)
    static let c64Brown      = SKColor.hex(0x433900)
    static let c64LightRed   = SKColor.hex(0x9A6759)
    static let c64DarkGrey   = SKColor.hex(0x444444)
    static let c64MidGrey    = SKColor.hex(0x6C6C6C)
    static let c64LightGreen = SKColor.hex(0x9AD284)
    static let c64LightBlue  = SKColor.hex(0x6C5EB5)
    static let c64LightGrey  = SKColor.hex(0x959595)

    // HD Overdrive Comic-Arcade Colors
    static let deepNavyBg    = SKColor.hex(0x0B1324)
    static let panelBg       = SKColor.hex(0x131F38)
    static let brassGold     = SKColor.hex(0xFFD24A)
    static let warmAmber     = SKColor.hex(0xFF9B2E)
    static let unionPrimary  = SKColor.hex(0x2868F2)
    static let unionBright   = SKColor.hex(0x58A6FF)
    static let grayPrimary   = SKColor.hex(0x8E9EBA)
    static let grayAccent    = SKColor.hex(0xFF5656)
    static let meadowGreen   = SKColor.hex(0x3FA34D)
    static let prairieSand   = SKColor.hex(0xD8A85E)
    static let riverCyan     = SKColor.hex(0x24B8E8)
    static let emeraldWin    = SKColor.hex(0x2CE88A)

    static func factionColor(_ faction: Faction, c64: Bool) -> SKColor {
        switch (faction, c64) {
        case (.unionBlue, false): return unionBright
        case (.unionBlue, true):  return c64LightBlue
        case (.grayCorps, false): return SKColor.hex(0xCFD9EC)
        case (.grayCorps, true):  return c64LightGrey
        }
    }

    static func factionFill(_ faction: Faction, c64: Bool) -> SKColor {
        switch (faction, c64) {
        case (.unionBlue, false): return SKColor.hex(0x1E4DB7)
        case (.unionBlue, true):  return c64Blue
        case (.grayCorps, false): return SKColor.hex(0x5E6D87)
        case (.grayCorps, true):  return c64MidGrey
        }
    }
}

// MARK: - Strategic Map Territory & Railway Definitions

struct TerritoryDef {
    let id: Int
    let code: String
    let name: String
    let mapPos: CGPoint // In 1280x800 scene space (corridor x: 230..1050, y: 110..690)
    let neighbors: [Int]
    let hasFort: Bool
    let fortName: String?
    let isCoastalPort: Bool
    let isRailStation: Bool
}

enum CampaignMapCatalog {
    static let territories: [TerritoryDef] = [
        TerritoryDef(id: 0,  code: "KS", name: "Kansas",       mapPos: CGPoint(x: 315, y: 470), neighbors: [1, 2, 5],          hasFort: true,  fortName: "Fort Kaw",        isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 1,  code: "TX", name: "Texas",        mapPos: CGPoint(x: 325, y: 215), neighbors: [0, 3, 4],          hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 2,  code: "MO", name: "Missouri",     mapPos: CGPoint(x: 455, y: 465), neighbors: [0, 3, 5, 6],       hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 3,  code: "AR", name: "Arkansas",     mapPos: CGPoint(x: 465, y: 310), neighbors: [1, 2, 4, 7, 8],    hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 4,  code: "LA", name: "Louisiana",    mapPos: CGPoint(x: 480, y: 165), neighbors: [1, 3, 8],          hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: false),
        TerritoryDef(id: 5,  code: "IL", name: "Illinois",     mapPos: CGPoint(x: 565, y: 538), neighbors: [0, 2, 6, 9],       hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 6,  code: "KY", name: "Kentucky",     mapPos: CGPoint(x: 635, y: 432), neighbors: [2, 5, 7, 9, 11],   hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 7,  code: "TN", name: "Tennessee",    mapPos: CGPoint(x: 645, y: 322), neighbors: [3, 6, 8, 12, 13],  hasFort: true,  fortName: "Fort Cumberland", isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 8,  code: "MS", name: "Mississippi",  mapPos: CGPoint(x: 610, y: 195), neighbors: [3, 4, 7, 13],      hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 9,  code: "OH", name: "Ohio",         mapPos: CGPoint(x: 735, y: 535), neighbors: [5, 6, 10, 11],     hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 10, code: "PA", name: "Pennsylvania", mapPos: CGPoint(x: 885, y: 545), neighbors: [9, 11],            hasFort: true,  fortName: "Fort Keystone",   isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 11, code: "VA", name: "Virginia",     mapPos: CGPoint(x: 885, y: 430), neighbors: [6, 9, 10, 12],     hasFort: true,  fortName: "Fort Ironclad",   isCoastalPort: false, isRailStation: true),
        TerritoryDef(id: 12, code: "NC", name: "Carolinas",    mapPos: CGPoint(x: 895, y: 305), neighbors: [7, 11, 13],        hasFort: false, fortName: nil,               isCoastalPort: true,  isRailStation: true),
        TerritoryDef(id: 13, code: "GA", name: "Georgia",      mapPos: CGPoint(x: 790, y: 205), neighbors: [7, 8, 12],         hasFort: false, fortName: nil,               isCoastalPort: false, isRailStation: true),
    ]

    // Ordered railroad routes across territories
    static let northernRailRoute: [Int] = [0, 2, 5, 9, 10, 11]
    static let southernRailRoute: [Int] = [1, 3, 8, 7, 13, 12]
    static let centralSpurRoute:  [Int] = [5, 6, 7]

    static let allRailEdges: [(Int, Int)] = [
        (0, 2), (2, 5), (5, 9), (9, 10), (10, 11),
        (1, 3), (3, 8), (8, 7), (7, 13), (13, 12),
        (5, 6), (6, 7)
    ]
}

// MARK: - Army Stack

struct ArmyStack: Codable, Equatable {
    var faction: Faction
    var infantry: Int   // 1..3 regiments
    var cavalry: Int    // 1..3 squadrons
    var cannons: Int    // 1..3 batteries
    var movedThisTurn: Bool = false
    var stunnedByStorm: Bool = false

    var totalStrength: Int {
        infantry * 2 + cavalry * 3 + cannons * 4
    }

    mutating func merge(with other: ArmyStack) {
        guard other.faction == faction else { return }
        infantry = min(3, infantry + other.infantry)
        cavalry = min(3, cavalry + other.cavalry)
        cannons = min(3, cannons + other.cannons)
    }

    static func standard(for faction: Faction) -> ArmyStack {
        ArmyStack(faction: faction, infantry: 1, cavalry: 1, cannons: 1)
    }

    static func veteran(for faction: Faction) -> ArmyStack {
        ArmyStack(faction: faction, infantry: 2, cavalry: 2, cannons: 2)
    }
}

// MARK: - Achievements, High Scores & Settings Persistence

struct HighScoreEntry: Codable {
    var initials: String
    var score: Int
    var year: Int
    var faction: String
}

struct PlayerSettings: Codable {
    var visualTheme: VisualTheme = .hdOverdrive
    var audioChip: AudioChipMode = .modernSynth
    var aiDifficulty: AIDifficulty = .colonel
    var stormEventsEnabled: Bool = true
    var musicVolume: Float = 0.80
    var sfxVolume: Float = 0.85
    var launchFullscreen: Bool = false
}

struct SavePayload: Codable {
    var settings: PlayerSettings = PlayerSettings()
    var highScores: [HighScoreEntry] = [
        HighScoreEntry(initials: "NGD", score: 18500, year: 1864, faction: "BLUE"),
        HighScoreEntry(initials: "GEN", score: 14200, year: 1863, faction: "GRAY"),
        HighScoreEntry(initials: "REB", score: 11800, year: 1862, faction: "BLUE"),
        HighScoreEntry(initials: "CAV", score: 9400,  year: 1861, faction: "GRAY"),
        HighScoreEntry(initials: "LOC", score: 7200,  year: 1861, faction: "BLUE"),
    ]
    var unlockedMedals: Set<String> = []
    var campaignsWon: Int = 0
    var battlesWon: Int = 0
    var trainsRobbed: Int = 0
    var fortsCaptured: Int = 0
}

struct MedalDefinition {
    let id: String
    let title: String
    let subtitle: String
}

enum AchievementCatalog {
    static let all: [MedalDefinition] = [
        MedalDefinition(id: "first_skirmish",  title: "FIRST VOLLEY",       subtitle: "Win your first tactical Field Battle"),
        MedalDefinition(id: "bridge_buster",   title: "BRIDGE BUSTER",      subtitle: "Demolish the wooden river bridge with cannon fire"),
        MedalDefinition(id: "train_robber",    title: "GREAT TRAIN ROBBER", subtitle: "Capture an enemy Paymaster Locomotive mid-run"),
        MedalDefinition(id: "fort_stormer",    title: "FORT STORMER",       subtitle: "Raise your colors over a defended Railway Fort"),
        MedalDefinition(id: "cavalry_sweep",   title: "SABER THUNDER",      subtitle: "Win a Field Battle with your Cavalry Squadron intact"),
        MedalDefinition(id: "grand_army",      title: "GRAND ARMY CORPS",   subtitle: "Merge battalions into a 3-3-3 full-strength army"),
        MedalDefinition(id: "port_admiral",    title: "ATLANTIC ADMIRAL",   subtitle: "Receive overseas Clipper Ship reinforcements"),
        MedalDefinition(id: "paymaster_baron", title: "RAILROAD BARON",     subtitle: "Recruit a new army from Paymaster Train gold"),
        MedalDefinition(id: "time_machine_89", title: "1989 TIME TRAVELER", subtitle: "Play in 1989 C64 Retro visual + SID 6581 audio mode"),
        MedalDefinition(id: "flawless_battle", title: "IRON BRIGADE",       subtitle: "Win a Field Battle without losing a single unit"),
        MedalDefinition(id: "campaign_victor", title: "CONTINENTAL VICTOR", subtitle: "Unify every territory in a full Campaign"),
        MedalDefinition(id: "general_rank",    title: "FIVE-STAR GENERAL",  subtitle: "Win a battle or campaign on GENERAL AI difficulty"),
    ]
}

@MainActor
final class PersistenceManager {
    static let shared = PersistenceManager()
    private let key = "com.ngd.ironrails.save.v1"
    private(set) var data: SavePayload

    private init() {
        if let raw = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(SavePayload.self, from: raw) {
            self.data = decoded
        } else {
            self.data = SavePayload()
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func updateSettings(_ block: (inout PlayerSettings) -> Void) {
        block(&data.settings)
        save()
    }

    @discardableResult
    func unlockMedal(_ id: String) -> MedalDefinition? {
        guard !data.unlockedMedals.contains(id) else { return nil }
        data.unlockedMedals.insert(id)
        save()
        return AchievementCatalog.all.first { $0.id == id }
    }

    func recordBattleWin() {
        data.battlesWon += 1
        save()
    }

    func recordTrainRobbed() {
        data.trainsRobbed += 1
        save()
    }

    func recordFortCaptured() {
        data.fortsCaptured += 1
        save()
    }

    func recordCampaignWin(initials: String, score: Int, year: Int, faction: Faction) {
        data.campaignsWon += 1
        data.highScores.append(HighScoreEntry(initials: initials, score: score, year: year, faction: faction.shortLabel))
        data.highScores.sort { $0.score > $1.score }
        if data.highScores.count > 8 {
            data.highScores = Array(data.highScores.prefix(8))
        }
        save()
    }
}
