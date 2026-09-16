import CoreGraphics

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
}

func groupOf(_ number: Int) -> BallGroup? {
    switch number {
    case 1...7: return .solids
    case 9...15: return .stripes
    default: return nil
    }
}
