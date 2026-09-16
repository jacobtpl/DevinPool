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
    @Published var isOpenTable = true

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
        scene.shoot(power: power)
        power = 0
    }

    func newGame() {
        power = 0
        scene.newGame()
    }
}
