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
    /// Follow/draw: surface slip velocity relative to the cloth (speed units). Friction converts it into velocity.
    var spin: CGVector = .zero
    /// English: rim speed about the vertical axis (speed units); positive is counter-clockwise from above.
    var sideSpin: CGFloat = 0
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
    var spinMagnitude: CGFloat { (spin.dx * spin.dx + spin.dy * spin.dy).squareRoot() }
    var isActive: Bool { isMoving || spinMagnitude > 0 }

    /// Rolls the ball for `dt`: a ball rolling without slipping turns about `z × v / r`; follow/draw slip
    /// adds to that, and english turns it about the vertical axis.
    func roll(dt: CGFloat, radius: CGFloat) {
        let vx = velocity.dx + spin.dx
        let vy = velocity.dy + spin.dy
        let omega = SIMD3<Float>(Float(-vy / radius), Float(vx / radius), Float(sideSpin / radius))
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
