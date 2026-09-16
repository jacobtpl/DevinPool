import Foundation

struct ShotResult {
    var message: String
    var ballInHand = false
    var winner: Int?
    var respotEight = false
}

/// Turn/foul logic for a two player game of 8-ball (simplified WPA rules).
final class EightBallRules {
    private(set) var currentPlayer = 1
    private(set) var groups: [Int: BallGroup] = [:]
    private(set) var isBreakShot = true
    private(set) var winner: Int?

    var isOpenTable: Bool { groups.isEmpty }

    func opponent(of player: Int) -> Int { 3 - player }

    func group(of player: Int) -> BallGroup? { groups[player] }

    func name(_ player: Int) -> String { "Player \(player)" }

    func reset() {
        currentPlayer = 1
        groups = [:]
        isBreakShot = true
        winner = nil
    }

    /// True when the player has cleared their group and is shooting at the 8.
    func isOnEight(_ player: Int, ballsOnTable: [Int]) -> Bool {
        guard let g = groups[player] else { return false }
        return !ballsOnTable.contains { groupOf($0) == g }
    }

    func resolve(shot: ShotRecord, ballsBefore: [Int]) -> ShotResult {
        let shooter = currentPlayer
        let opp = opponent(of: shooter)
        var foulReason: String?

        if shot.cueBallPotted {
            foulReason = "Scratch"
        } else if shot.firstHit == nil {
            foulReason = "No ball contacted"
        } else if !isOpenTable, let first = shot.firstHit, let g = groups[shooter] {
            if first == 8 {
                if !isOnEight(shooter, ballsOnTable: ballsBefore) { foulReason = "Hit the 8 ball first" }
            } else if groupOf(first) != g {
                foulReason = "Hit opponent's ball first"
            }
        }

        let pottedObjects = shot.potted.filter { $0 != 0 && $0 != 8 }
        var result = ShotResult(message: "")

        if shot.potted.contains(8) {
            if isBreakShot {
                result.respotEight = true
            } else {
                let clearedBefore = isOnEight(shooter, ballsOnTable: ballsBefore)
                let legal = clearedBefore && foulReason == nil
                let w = legal ? shooter : opp
                winner = w
                result.winner = w
                if legal {
                    result.message = "\(name(shooter)) sinks the 8 ball and wins!"
                } else if foulReason == "Scratch" {
                    result.message = "\(name(shooter)) scratched on the 8 ball. \(name(opp)) wins!"
                } else if !clearedBefore {
                    result.message = "\(name(shooter)) sank the 8 ball too early. \(name(opp)) wins!"
                } else {
                    result.message = "\(name(shooter)) fouled on the 8 ball. \(name(opp)) wins!"
                }
                return result
            }
        }

        let wasBreak = isBreakShot
        isBreakShot = false

        var assignedMessage: String?
        if isOpenTable && !wasBreak && foulReason == nil,
           let first = pottedObjects.first, let g = groupOf(first) {
            groups[shooter] = g
            groups[opp] = g.other
            assignedMessage = "\(name(shooter)) is \(g.rawValue.lowercased())"
        }

        if let foulReason {
            currentPlayer = opp
            result.ballInHand = true
            result.message = "Foul: \(foulReason). \(name(opp)) has ball in hand"
            return result
        }

        let legalPot: Bool
        if let g = groups[shooter] {
            legalPot = pottedObjects.contains { groupOf($0) == g }
        } else {
            legalPot = !pottedObjects.isEmpty
        }

        if legalPot {
            if let assignedMessage {
                result.message = "\(assignedMessage). Shoot again!"
            } else if result.respotEight {
                result.message = "8 ball re-spotted. \(name(shooter)) shoots again"
            } else {
                result.message = "Nice shot! \(name(shooter)) shoots again"
            }
        } else {
            currentPlayer = opp
            if result.respotEight {
                result.message = "8 ball re-spotted. \(name(opp))'s turn"
            } else {
                result.message = "\(name(opp))'s turn"
            }
        }
        return result
    }
}
