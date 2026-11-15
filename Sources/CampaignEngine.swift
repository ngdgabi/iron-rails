import Foundation
import CoreGraphics

enum PendingEncounter {
    case fieldBattle(fromId: Int, toId: Int, attacker: ArmyStack, defender: ArmyStack)
    case fortAssault(fromId: Int, toId: Int, attacker: ArmyStack, defenderFaction: Faction, defenderArmy: ArmyStack?)
    case trainHeist(raiderFaction: Faction, trainOwner: Faction, goldAtStake: Int, stationId: Int)
}

struct TurnEventBanner {
    let title: String
    let detail: String
    let isGoodForBlue: Bool
}

@MainActor
final class CampaignState {
    var year: CampaignYear
    var playerMode: PlayerMode
    var aiDifficulty: AIDifficulty
    var stormEnabled: Bool

    var turnNumber: Int = 1
    var monthIndex: Int = 3 // April
    var currentYearNumber: Int
    var activeFaction: Faction = .unionBlue

    // Territory ownership & armies by territory ID (0..13)
    var owners: [Int: Faction] = [:]
    var armies: [Int: ArmyStack] = [:]

    var blueGold: Int = 2
    var grayGold: Int = 2
    var blueScore: Int = 0
    var grayScore: Int = 0

    var stormTerritoryId: Int? = 2
    var clipperCountdown: Int = 3

    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    var dateLabel: String {
        "\(Self.monthNames[monthIndex % 12]) \(currentYearNumber)"
    }

    init(year: CampaignYear, mode: PlayerMode, difficulty: AIDifficulty, stormEnabled: Bool) {
        self.year = year
        self.playerMode = mode
        self.aiDifficulty = difficulty
        self.stormEnabled = stormEnabled
        self.currentYearNumber = year.rawValue
        setupScenario(year)
    }

    private func setupScenario(_ scenario: CampaignYear) {
        owners.removeAll()
        armies.removeAll()

        switch scenario {
        case .y1861:
            // Classic brisk opening with neutral border states
            for id in [0, 5, 9, 10] { owners[id] = .unionBlue }
            for id in [1, 4, 8, 12, 13] { owners[id] = .grayCorps }
            armies[5]  = .standard(for: .unionBlue)  // Illinois
            armies[10] = .standard(for: .unionBlue)  // Pennsylvania Fort
            armies[8]  = .standard(for: .grayCorps)  // Mississippi
            armies[11] = .standard(for: .grayCorps)  // Virginia Fort
            owners[11] = .grayCorps

        case .y1862:
            for id in [0, 2, 5, 6, 9, 10] { owners[id] = .unionBlue }
            for id in [1, 3, 4, 7, 8, 11, 12, 13] { owners[id] = .grayCorps }
            armies[2]  = .standard(for: .unionBlue)
            armies[6]  = ArmyStack(faction: .unionBlue, infantry: 2, cavalry: 1, cannons: 1)
            armies[10] = .standard(for: .unionBlue)
            armies[3]  = .standard(for: .grayCorps)
            armies[7]  = ArmyStack(faction: .grayCorps, infantry: 2, cavalry: 1, cannons: 1)
            armies[11] = .standard(for: .grayCorps)

        case .y1863:
            for id in [0, 2, 5, 6, 9, 10] { owners[id] = .unionBlue }
            for id in [1, 3, 4, 7, 8, 11, 12, 13] { owners[id] = .grayCorps }
            armies[0]  = .standard(for: .unionBlue)
            armies[6]  = .veteran(for: .unionBlue)
            armies[9]  = .veteran(for: .unionBlue)
            armies[3]  = .standard(for: .grayCorps)
            armies[7]  = .veteran(for: .grayCorps)
            armies[11] = .veteran(for: .grayCorps)
            blueGold = 3
            grayGold = 3

        case .y1864:
            for id in [0, 2, 5, 6, 7, 9, 10] { owners[id] = .unionBlue }
            for id in [1, 3, 4, 8, 11, 12, 13] { owners[id] = .grayCorps }
            armies[2]  = .standard(for: .unionBlue)
            armies[7]  = .veteran(for: .unionBlue)
            armies[9]  = .veteran(for: .unionBlue)
            armies[10] = .standard(for: .unionBlue)
            armies[3]  = .standard(for: .grayCorps)
            armies[8]  = .veteran(for: .grayCorps)
            armies[11] = .veteran(for: .grayCorps)
            armies[12] = .standard(for: .grayCorps)
            blueGold = 4
            grayGold = 4
        }

        stormTerritoryId = stormEnabled ? 4 : nil
    }

    func gold(for faction: Faction) -> Int {
        faction == .unionBlue ? blueGold : grayGold
    }

    func addGold(_ delta: Int, to faction: Faction) {
        if faction == .unionBlue {
            blueGold = max(0, blueGold + delta)
        } else {
            grayGold = max(0, grayGold + delta)
        }
    }

    func addScore(_ pts: Int, to faction: Faction) {
        if faction == .unionBlue {
            blueScore += pts
        } else {
            grayScore += pts
        }
    }

    func territoryCount(for faction: Faction) -> Int {
        owners.values.filter { $0 == faction }.count
    }

    func armyCount(for faction: Faction) -> Int {
        armies.values.filter { $0.faction == faction }.count
    }

    func checkCampaignWinner() -> Faction? {
        let bArmies = armyCount(for: .unionBlue)
        let gArmies = armyCount(for: .grayCorps)
        let bStates = territoryCount(for: .unionBlue)
        let gStates = territoryCount(for: .grayCorps)

        if gArmies == 0 && gStates == 0 { return .unionBlue }
        if bArmies == 0 && bStates == 0 { return .grayCorps }
        if gArmies == 0 && grayGold < 5 { return .unionBlue }
        if bArmies == 0 && blueGold < 5 { return .grayCorps }
        if bStates >= 13 && gArmies == 0 { return .unionBlue }
        if gStates >= 13 && bArmies == 0 { return .grayCorps }
        return nil
    }

    // Begin turn for activeFaction: refresh armies, run Paymaster Train, Clipper Ship, Storm
    func beginTurnPhase() -> (banners: [TurnEventBanner], heist: PendingEncounter?, trainPath: [Int]) {
        var banners: [TurnEventBanner] = []
        var trainPath: [Int] = []
        var pendingHeist: PendingEncounter? = nil

        // Reset move flags for active faction
        for (tid, var stack) in armies where stack.faction == activeFaction {
            stack.movedThisTurn = false
            stack.stunnedByStorm = (stormTerritoryId == tid)
            armies[tid] = stack
        }

        // Advance calendar & storm at top of Union turn (turn >= 2)
        if activeFaction == .unionBlue && turnNumber > 1 {
            monthIndex += 1
            if monthIndex % 12 == 0 { currentYearNumber += 1 }

            if stormEnabled {
                let currentStorm = stormTerritoryId ?? 2
                let neighbors = CampaignMapCatalog.territories[currentStorm].neighbors
                let nextStorm = neighbors.randomElement() ?? currentStorm
                stormTerritoryId = nextStorm
                // Re-apply stun if landed on active army
                if var st = armies[nextStorm], st.faction == activeFaction {
                    st.stunnedByStorm = true
                    armies[nextStorm] = st
                    let tName = CampaignMapCatalog.territories[nextStorm].name
                    banners.append(TurnEventBanner(
                        title: "STORM OVER \(tName.uppercased())!",
                        detail: "Thunderstorm pins down troops in \(tName) for 1 turn!",
                        isGoodForBlue: activeFaction != .unionBlue
                    ))
                }
            }

            // Overseas Clipper Ship every 3 full rounds in Carolinas (id 12)
            clipperCountdown -= 1
            if clipperCountdown <= 0 {
                clipperCountdown = 3
                if let portOwner = owners[12] {
                    spawnOrReinforce(at: 12, faction: portOwner)
                    banners.append(TurnEventBanner(
                        title: "ATLANTIC CLIPPER DOCKED!",
                        detail: "\(portOwner.displayName) receives overseas reinforcements in Carolinas!",
                        isGoodForBlue: portOwner == .unionBlue
                    ))
                    if playerMode.isHuman(portOwner) {
                        _ = PersistenceManager.shared.unlockMedal("port_admiral")
                    }
                }
            }
        }

        // Paymaster Steam Train gold run along faction's primary rail corridor
        let route = activeFaction == .unionBlue
            ? CampaignMapCatalog.northernRailRoute
            : CampaignMapCatalog.southernRailRoute

        let ownedOnRoute = route.filter { owners[$0] == activeFaction }
        if ownedOnRoute.count >= 2, let firstIdx = route.firstIndex(of: ownedOnRoute.first!), let lastIdx = route.lastIndex(of: ownedOnRoute.last!), lastIdx > firstIdx {
            let subRoute = Array(route[firstIdx...lastIdx])
            trainPath = subRoute
            let goldValue = min(3, max(1, ownedOnRoute.count - 1))

            // Check if opponent army occupies an intermediate rail station on this run -> TRAIN HEIST!
            let opp = activeFaction.opponent
            if let raidStation = subRoute.first(where: { armies[$0]?.faction == opp }) {
                pendingHeist = .trainHeist(
                    raiderFaction: opp,
                    trainOwner: activeFaction,
                    goldAtStake: goldValue,
                    stationId: raidStation
                )
            } else {
                addGold(goldValue, to: activeFaction)
                addScore(goldValue * 120, to: activeFaction)
                banners.append(TurnEventBanner(
                    title: "PAYMASTER EXPRESS ARRIVED",
                    detail: "+\(goldValue) Gold Bullion delivered to \(activeFaction.displayName) treasury!",
                    isGoodForBlue: activeFaction == .unionBlue
                ))
            }
        }

        return (banners, pendingHeist, trainPath)
    }

    func spawnOrReinforce(at territoryId: Int, faction: Faction) {
        owners[territoryId] = faction
        if var existing = armies[territoryId], existing.faction == faction {
            existing.merge(with: .standard(for: faction))
            armies[territoryId] = existing
        } else if armies[territoryId] == nil {
            armies[territoryId] = .standard(for: faction)
        } else {
            // Find any owned friendly state without enemy army
            if let fallback = CampaignMapCatalog.territories.map(\.id).first(where: { owners[$0] == faction && (armies[$0] == nil || armies[$0]?.faction == faction) }) {
                if var ex = armies[fallback] {
                    ex.merge(with: .standard(for: faction))
                    armies[fallback] = ex
                } else {
                    armies[fallback] = .standard(for: faction)
                }
            }
        }
    }

    func canRecruitArmy(for faction: Faction) -> Int? {
        guard gold(for: faction) >= 5 else { return nil }
        // Prefer friendly Fort without max stack, else any friendly state
        let friendly = CampaignMapCatalog.territories.filter { owners[$0.id] == faction }
        if let fort = friendly.first(where: { $0.hasFort && (armies[$0.id] == nil || armies[$0.id]!.totalStrength < 27) }) {
            return fort.id
        }
        if let open = friendly.first(where: { armies[$0.id] == nil || armies[$0.id]!.totalStrength < 27 }) {
            return open.id
        }
        return nil
    }

    @discardableResult
    func recruitArmy(for faction: Faction) -> Int? {
        guard let targetId = canRecruitArmy(for: faction) else { return nil }
        addGold(-5, to: faction)
        spawnOrReinforce(at: targetId, faction: faction)
        addScore(350, to: faction)
        if playerMode.isHuman(faction) {
            _ = PersistenceManager.shared.unlockMedal("paymaster_baron")
        }
        return targetId
    }

    // Attempt to move army from `fromId` to neighbor `toId`
    func executeArmyMove(from fromId: Int, to toId: Int) -> PendingEncounter? {
        guard var moving = armies[fromId],
              moving.faction == activeFaction,
              !moving.movedThisTurn,
              !moving.stunnedByStorm else {
            return nil
        }
        let def = CampaignMapCatalog.territories[fromId]
        guard def.neighbors.contains(toId) else { return nil }

        let targetDef = CampaignMapCatalog.territories[toId]
        let targetOwner = owners[toId]

        // Case 1: Friendly stack -> Merge!
        if var friendly = armies[toId], friendly.faction == activeFaction {
            armies.removeValue(forKey: fromId)
            friendly.merge(with: moving)
            friendly.movedThisTurn = true
            armies[toId] = friendly
            if friendly.infantry == 3 && friendly.cavalry == 3 && friendly.cannons == 3 && playerMode.isHuman(activeFaction) {
                _ = PersistenceManager.shared.unlockMedal("grand_army")
            }
            return nil
        }

        // Case 2: Enemy Fort territory -> Side-Scrolling Fort Assault!
        if targetDef.hasFort && targetOwner == activeFaction.opponent {
            return .fortAssault(
                fromId: fromId,
                toId: toId,
                attacker: moving,
                defenderFaction: activeFaction.opponent,
                defenderArmy: armies[toId]
            )
        }

        // Case 3: Enemy army present -> Tactical Field Battle!
        if let defender = armies[toId], defender.faction != activeFaction {
            return .fieldBattle(fromId: fromId, toId: toId, attacker: moving, defender: defender)
        }

        // Case 4: Unoccupied territory -> March in and claim!
        armies.removeValue(forKey: fromId)
        moving.movedThisTurn = true
        armies[toId] = moving
        if owners[toId] != activeFaction {
            owners[toId] = activeFaction
            addScore(250, to: activeFaction)
        }
        return nil
    }

    func resolveEncounterVictory(
        encounter: PendingEncounter,
        winner: Faction,
        survivingWinnerArmy: ArmyStack?
    ) {
        switch encounter {
        case .fieldBattle(let fromId, let toId, _, _):
            armies.removeValue(forKey: fromId)
            if winner == activeFaction {
                var victor = survivingWinnerArmy ?? ArmyStack(faction: winner, infantry: 1, cavalry: 0, cannons: 0)
                victor.movedThisTurn = true
                armies[toId] = victor
                owners[toId] = winner
                addScore(900, to: winner)
            } else {
                let defVictor = survivingWinnerArmy ?? ArmyStack(faction: winner, infantry: 1, cavalry: 0, cannons: 0)
                armies[toId] = defVictor
                owners[toId] = winner
                addScore(750, to: winner)
            }

        case .fortAssault(let fromId, let toId, var attacker, let defFaction, let defArmy):
            if winner == attacker.faction {
                armies.removeValue(forKey: fromId)
                attacker.movedThisTurn = true
                armies[toId] = attacker
                owners[toId] = attacker.faction
                addScore(1200, to: attacker.faction)
            } else {
                // Repelled from fort ramparts: attacker loses 1 unit or retreats
                if attacker.infantry > 1 {
                    attacker.infantry -= 1
                    attacker.movedThisTurn = true
                    armies[fromId] = attacker
                } else {
                    armies.removeValue(forKey: fromId)
                }
                if let d = defArmy {
                    armies[toId] = d
                }
                owners[toId] = defFaction
                addScore(600, to: defFaction)
            }

        case .trainHeist(let raider, let owner, let gold, _):
            if winner == raider {
                addGold(gold, to: raider)
                addScore(1000, to: raider)
            } else {
                addGold(gold, to: owner)
                addScore(500, to: owner)
            }
        }
    }

    func endTurn() {
        if activeFaction == .grayCorps {
            turnNumber += 1
        }
        activeFaction = activeFaction.opponent
    }

    // MARK: - AI Strategic Planner

    func chooseNextAIAction() -> (recruit: Bool, move: (from: Int, to: Int)?) {
        if canRecruitArmy(for: activeFaction) != nil {
            return (true, nil)
        }

        let movable = armies.filter { $0.value.faction == activeFaction && !$0.value.movedThisTurn && !$0.value.stunnedByStorm }
        var bestMove: (from: Int, to: Int)? = nil
        var bestScore: Int = -9999

        for (fromId, stack) in movable {
            let neighbors = CampaignMapCatalog.territories[fromId].neighbors
            for toId in neighbors {
                let targetDef = CampaignMapCatalog.territories[toId]
                let targetOwner = owners[toId]
                var score = 0

                if let other = armies[toId] {
                    if other.faction == activeFaction {
                        if stack.totalStrength + other.totalStrength <= 18 {
                            score = 18
                        } else {
                            score = -40
                        }
                    } else {
                        // Attack evaluation
                        let diff = stack.totalStrength - other.totalStrength
                        let aggression = aiDifficulty == .general ? 4 : (aiDifficulty == .colonel ? 1 : -2)
                        score = 45 + (diff + aggression) * 10
                        if targetDef.hasFort { score += 20 }
                    }
                } else {
                    // Empty territory!
                    if targetOwner != activeFaction {
                        score = 65
                        if targetDef.isCoastalPort { score += 30 }
                        if targetDef.hasFort { score += 28 }
                        if targetDef.isRailStation { score += 15 }
                    } else {
                        // Move closer to enemy front line
                        let frontDist = minimumDistanceToEnemy(from: toId, faction: activeFaction)
                        let curDist = minimumDistanceToEnemy(from: fromId, faction: activeFaction)
                        score = (curDist - frontDist) * 16
                    }
                }

                if score > bestScore {
                    bestScore = score
                    bestMove = (fromId, toId)
                }
            }
        }

        if bestScore > 5 {
            return (false, bestMove)
        }
        return (false, nil)
    }

    private func minimumDistanceToEnemy(from startId: Int, faction: Faction) -> Int {
        var visited: Set<Int> = [startId]
        var queue: [(Int, Int)] = [(startId, 0)]
        while !queue.isEmpty {
            let (curr, dist) = queue.removeFirst()
            if owners[curr] != faction || (armies[curr] != nil && armies[curr]?.faction != faction) {
                return dist
            }
            for nb in CampaignMapCatalog.territories[curr].neighbors where !visited.contains(nb) {
                visited.insert(nb)
                queue.append((nb, dist + 1))
            }
        }
        return 6
    }
}
