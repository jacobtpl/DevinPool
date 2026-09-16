import Combine
import SpriteKit
import SwiftUI

enum GamePhase: Equatable {
    case aiming
    case ballInHand
    case shooting
    case ballsMoving
    case gameOver(winner: Int)
}

struct PlayerStatus {
    var number: Int
    var group: BallGroup?
    var remaining: [Int]
}

@MainActor
final class GameModel: ObservableObject {
    @Published var phase: GamePhase = .aiming
    @Published var currentPlayer = 1
    @Published var players: [PlayerStatus] = [
        PlayerStatus(number: 1, group: nil, remaining: []),
        PlayerStatus(number: 2, group: nil, remaining: []),
    ]
    @Published var message = "Player 1 to break"
    @Published var power: CGFloat = 0
    /// Cue-tip offset on the cue ball as seen from behind the cue: x = english (right positive), y = follow (+) / draw (-).
    @Published var spin: CGPoint = .zero
    @Published var isOpenTable = true

    static let maxSpinOffset: CGFloat = 0.8

    var canShoot: Bool { phase == .aiming || phase == .ballInHand }

    var winner: Int? {
        if case .gameOver(let w) = phase { return w }
        return nil
    }

    lazy var scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        scene.model = self
        return scene
    }()

    func shoot() {
        guard canShoot, power > 0.03 else {
            power = 0
            return
        }
        scene.shoot(power: power, spin: spin)
        power = 0
        spin = .zero
    }

    func setSpin(_ offset: CGPoint) {
        let len = hypot(offset.x, offset.y)
        let limit = Self.maxSpinOffset
        spin = len > limit ? CGPoint(x: offset.x / len * limit, y: offset.y / len * limit) : offset
    }

    func newGame() {
        power = 0
        spin = .zero
        scene.newGame()
    }
}
