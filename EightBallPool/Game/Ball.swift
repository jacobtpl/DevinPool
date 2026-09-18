import CoreGraphics
import simd

enum BallGroup: String {
    case solids = "Solids"
    case stripes = "Stripes"

    var other: BallGroup { self == .solids ? .stripes : .solids }

    var numbers: ClosedRange<Int> { self == .solids ? 1...7 : 9...15 }
}

final class Ball {
    let number: Int
    var position: CGPoint
    var velocity: CGVector = .zero
    /// Angular velocity in rad/s. x/y are the horizontal axes (follow, draw and natural roll live here);
    /// z is english, positive counter-clockwise seen from above.
    var angularVelocity = SIMD3<Double>(repeating: 0)
    var isPocketed = false
    /// Local-to-world rotation used only for rendering the rolling ball.
    var orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))

    init(number: Int, position: CGPoint) {
        self.number = number
        self.position = position
    }

    var isCue: Bool { number == 0 }
    var isEight: Bool { number == 8 }

    var group: BallGroup? {
        switch number {
        case 1...7: return .solids
        case 9...15: return .stripes
        default: return nil
        }
    }

    var speed: CGFloat { (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot() }
    var isMoving: Bool { speed > 0 }
    /// Horizontal spin on a stationary ball is slip that friction will turn into motion, so it keeps the shot alive;
    /// pure english on a stopped ball does not.
    var isActive: Bool { isMoving || angularVelocity.x != 0 || angularVelocity.y != 0 }
    var isSpinning: Bool { simd_length_squared(angularVelocity) > 0 }

    func stop() {
        velocity = .zero
        angularVelocity = .zero
    }

    /// Turns the rendered orientation by the angular velocity over `dt`.
    func roll(dt: CGFloat) {
        let omega = SIMD3<Float>(angularVelocity)
        let rate = simd_length(omega)
        guard rate > 1e-4 else { return }
        let step = simd_quatf(angle: rate * Float(dt), axis: omega / rate)
        orientation = simd_normalize(step * orientation)
    }

    func randomizeOrientation() {
        let axis = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)))
        orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: axis)
    }
}

func groupOf(_ number: Int) -> BallGroup? {
    switch number {
    case 1...7: return .solids
    case 9...15: return .stripes
    default: return nil
    }
}
