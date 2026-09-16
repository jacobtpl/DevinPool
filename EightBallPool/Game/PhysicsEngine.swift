import CoreGraphics

struct Pocket {
    let center: CGPoint
    let radius: CGFloat
    let isCorner: Bool
}

/// One straight piece of cushion face (a nose or a jaw).
struct CushionSegment {
    let a: CGPoint
    let b: CGPoint
}

/// A run of cushion between two pockets: jaw → nose → jaw, listed in order so it can be filled as a polygon.
struct CushionPiece {
    /// Face points from the first jaw tip, along the nose, to the last jaw tip.
    let face: [CGPoint]
    /// Unit normal pointing away from the felt (into the rail).
    let outward: CGVector
}

struct TableGeometry {
    /// Playing surface bounded by the cushion noses.
    let felt: CGRect
    let ballRadius: CGFloat

    /// Distance from the felt corner to the corner-pocket cushion nose along each rail.
    /// Gives a mouth of ~4.2 ball radii measured nose to nose (a 4.5" mouth on a 2.25" ball).
    var cornerNoseOffset: CGFloat { ballRadius * 3.0 }
    /// Half the side-pocket mouth measured nose to nose (~5.2" on a 2.25" ball).
    var sideNoseHalf: CGFloat { ballRadius * 2.2 }
    /// Corner jaws are cut at ~142° to the rail (38° into the pocket); side jaws at ~103° (13° flare).
    var cornerJawAngle: CGFloat { 38 * .pi / 180 }
    var sideJawAngle: CGFloat { 13 * .pi / 180 }
    var cornerJawLength: CGFloat { ballRadius * 1.6 }
    var sideJawLength: CGFloat { ballRadius * 1.5 }

    var pockets: [Pocket] {
        let r = ballRadius
        let c = r * 1.0
        return [
            Pocket(center: CGPoint(x: felt.minX - c, y: felt.minY - c), radius: r * 2.2, isCorner: true),
            Pocket(center: CGPoint(x: felt.maxX + c, y: felt.minY - c), radius: r * 2.2, isCorner: true),
            Pocket(center: CGPoint(x: felt.minX - c, y: felt.maxY + c), radius: r * 2.2, isCorner: true),
            Pocket(center: CGPoint(x: felt.maxX + c, y: felt.maxY + c), radius: r * 2.2, isCorner: true),
            Pocket(center: CGPoint(x: felt.minX - r * 1.6, y: felt.midY), radius: r * 1.8, isCorner: false),
            Pocket(center: CGPoint(x: felt.maxX + r * 1.6, y: felt.midY), radius: r * 1.8, isCorner: false),
        ]
    }

    /// Six cushion pieces: two short rails and the four halves of the long rails either side of the side pockets.
    var cushions: [CushionPiece] {
        let f = felt
        let cn = cornerNoseOffset
        let sn = sideNoseHalf
        let cj = cornerJawLength, sj = sideJawLength
        let ca = cornerJawAngle, sa = sideJawAngle

        func cornerJaw(from nose: CGPoint, alongRail: CGVector, outward: CGVector) -> CGPoint {
            // Leaves the nose heading toward the corner, bent `ca` into the rail.
            CGPoint(x: nose.x + (alongRail.dx * cos(ca) + outward.dx * sin(ca)) * cj,
                    y: nose.y + (alongRail.dy * cos(ca) + outward.dy * sin(ca)) * cj)
        }
        func sideJaw(from nose: CGPoint, towardPocket: CGVector, outward: CGVector) -> CGPoint {
            // Nearly straight back into the rail, flared `sa` toward the pocket centre.
            CGPoint(x: nose.x + (outward.dx * cos(sa) + towardPocket.dx * sin(sa)) * sj,
                    y: nose.y + (outward.dy * cos(sa) + towardPocket.dy * sin(sa)) * sj)
        }

        var pieces: [CushionPiece] = []

        // Bottom rail (outward -y) and top rail (outward +y).
        for (y, out) in [(f.minY, CGVector(dx: 0, dy: -1)), (f.maxY, CGVector(dx: 0, dy: 1))] {
            let left = CGPoint(x: f.minX + cn, y: y)
            let right = CGPoint(x: f.maxX - cn, y: y)
            pieces.append(CushionPiece(face: [
                cornerJaw(from: left, alongRail: CGVector(dx: -1, dy: 0), outward: out),
                left, right,
                cornerJaw(from: right, alongRail: CGVector(dx: 1, dy: 0), outward: out),
            ], outward: out))
        }

        // Left rail (outward -x) and right rail (outward +x), split by the side pocket.
        for (x, out) in [(f.minX, CGVector(dx: -1, dy: 0)), (f.maxX, CGVector(dx: 1, dy: 0))] {
            let lowerCorner = CGPoint(x: x, y: f.minY + cn)
            let lowerSide = CGPoint(x: x, y: f.midY - sn)
            pieces.append(CushionPiece(face: [
                cornerJaw(from: lowerCorner, alongRail: CGVector(dx: 0, dy: -1), outward: out),
                lowerCorner, lowerSide,
                sideJaw(from: lowerSide, towardPocket: CGVector(dx: 0, dy: 1), outward: out),
            ], outward: out))

            let upperSide = CGPoint(x: x, y: f.midY + sn)
            let upperCorner = CGPoint(x: x, y: f.maxY - cn)
            pieces.append(CushionPiece(face: [
                sideJaw(from: upperSide, towardPocket: CGVector(dx: 0, dy: -1), outward: out),
                upperSide, upperCorner,
                cornerJaw(from: upperCorner, alongRail: CGVector(dx: 0, dy: 1), outward: out),
            ], outward: out))
        }
        return pieces
    }

    /// Every cushion face as collidable line segments.
    var cushionSegments: [CushionSegment] {
        cushions.flatMap { piece in
            zip(piece.face, piece.face.dropFirst()).map { CushionSegment(a: $0, b: $1) }
        }
    }

    var headSpot: CGPoint { CGPoint(x: felt.midX, y: felt.minY + felt.height * 0.25) }
    var footSpot: CGPoint { CGPoint(x: felt.midX, y: felt.minY + felt.height * 0.75) }

    /// How far a ball centre sits beyond the cushion nose line (0 when on the felt).
    func overhang(_ p: CGPoint) -> CGFloat {
        max(felt.minX - p.x, p.x - felt.maxX, felt.minY - p.y, p.y - felt.maxY, 0)
    }

    func clampInside(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, felt.minX + ballRadius), felt.maxX - ballRadius),
            y: min(max(p.y, felt.minY + ballRadius), felt.maxY - ballRadius)
        )
    }
}

struct ShotRecord {
    var firstHit: Int?
    var potted: [Int] = []

    var cueBallPotted: Bool { potted.contains(0) }
}

struct StepEvents {
    var potted: [Ball] = []
    var strongestCollision: CGFloat = 0
}

final class PhysicsEngine {
    let geometry: TableGeometry

    let ballRestitution: CGFloat = 0.94
    let cushionRestitution: CGFloat = 0.72
    let substep: CGFloat = 1.0 / 480.0

    private let rollingDeceleration: CGFloat
    private let damping: CGFloat = 0.38
    private let stopSpeed: CGFloat

    /// Rate (1/s) at which cloth friction removes slip; the ball picks up `spinTransfer` of the removed slip as velocity.
    private let spinFriction: CGFloat = 3.0
    private let spinTransfer: CGFloat = 0.35
    private let sideSpinDecay: CGFloat = 0.5
    private let cushionSideSpinKick: CGFloat = 0.55
    private let cushionSideSpinRetained: CGFloat = 0.5

    private let cushionSegments: [CushionSegment]
    private let pockets: [Pocket]

    init(geometry: TableGeometry) {
        self.geometry = geometry
        cushionSegments = geometry.cushionSegments
        pockets = geometry.pockets
        rollingDeceleration = geometry.ballRadius * 5.0
        stopSpeed = geometry.ballRadius * 0.5
    }

    var maxShotSpeed: CGFloat { geometry.ballRadius * 320 }
    var minShotSpeed: CGFloat { geometry.ballRadius * 12 }

    func step(dt: CGFloat, balls: [Ball], shot: inout ShotRecord) -> StepEvents {
        var events = StepEvents()
        var remaining = dt
        while remaining > 0 {
            let h = min(substep, remaining)
            remaining -= h
            integrate(h, balls: balls)
            resolveBallCollisions(balls: balls, shot: &shot, events: &events)
            resolveCushions(balls: balls)
            detectPockets(balls: balls, shot: &shot, events: &events)
        }
        return events
    }

    private func integrate(_ h: CGFloat, balls: [Ball]) {
        for b in balls where !b.isPocketed && b.isActive {
            b.position.x += b.velocity.dx * h
            b.position.y += b.velocity.dy * h

            if b.sideSpin != 0 {
                b.sideSpin *= max(0, 1 - sideSpinDecay * h)
                if abs(b.sideSpin) < stopSpeed * 0.1 { b.sideSpin = 0 }
            }

            var spinMag = b.spinMagnitude
            if spinMag > 0 {
                let removed = min(1, spinFriction * h)
                b.velocity.dx += b.spin.dx * removed * spinTransfer
                b.velocity.dy += b.spin.dy * removed * spinTransfer
                b.spin.dx *= 1 - removed
                b.spin.dy *= 1 - removed
                spinMag = b.spinMagnitude
                if spinMag < stopSpeed * 0.2 {
                    b.spin = .zero
                    spinMag = 0
                }
            }

            let speed = b.speed
            guard speed > 0 else { continue }
            let newSpeed = speed - (rollingDeceleration + speed * damping) * h
            if newSpeed <= stopSpeed {
                if spinMag == 0 { b.velocity = .zero }
                continue
            }
            let scale = newSpeed / speed
            b.velocity.dx *= scale
            b.velocity.dy *= scale
        }
    }

    private func resolveBallCollisions(balls: [Ball], shot: inout ShotRecord, events: inout StepEvents) {
        let r = geometry.ballRadius
        let diameter = r * 2
        let active = balls.filter { !$0.isPocketed }
        for i in 0..<active.count {
            let a = active[i]
            for j in (i + 1)..<active.count {
                let b = active[j]
                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distSq = dx * dx + dy * dy
                if distSq >= diameter * diameter || distSq == 0 { continue }
                let dist = distSq.squareRoot()
                let nx = dx / dist
                let ny = dy / dist

                let overlap = diameter - dist
                a.position.x -= nx * overlap * 0.5
                a.position.y -= ny * overlap * 0.5
                b.position.x += nx * overlap * 0.5
                b.position.y += ny * overlap * 0.5

                let rvx = b.velocity.dx - a.velocity.dx
                let rvy = b.velocity.dy - a.velocity.dy
                let relNormal = rvx * nx + rvy * ny
                if relNormal >= 0 { continue }

                let impulse = -(1 + ballRestitution) * relNormal * 0.5
                a.velocity.dx -= nx * impulse
                a.velocity.dy -= ny * impulse
                b.velocity.dx += nx * impulse
                b.velocity.dy += ny * impulse

                events.strongestCollision = max(events.strongestCollision, -relNormal)
                if shot.firstHit == nil {
                    if a.isCue { shot.firstHit = b.number } else if b.isCue { shot.firstHit = a.number }
                }
            }
        }
    }

    /// Circle-vs-segment collision against every cushion face. Segment end points act as rounded
    /// nose tips, which is what makes balls rattle in the jaws.
    private func resolveCushions(balls: [Ball]) {
        let r = geometry.ballRadius
        let felt = geometry.felt
        let margin = r * 1.05
        for b in balls where !b.isPocketed {
            // Balls well inside the felt cannot touch a cushion; skip the segment tests.
            let p = b.position
            if p.x - felt.minX > margin, felt.maxX - p.x > margin, p.y - felt.minY > margin, felt.maxY - p.y > margin {
                continue
            }
            for seg in cushionSegments {
                let abx = seg.b.x - seg.a.x, aby = seg.b.y - seg.a.y
                let apx = b.position.x - seg.a.x, apy = b.position.y - seg.a.y
                let lenSq = abx * abx + aby * aby
                let t = lenSq > 0 ? min(max((apx * abx + apy * aby) / lenSq, 0), 1) : 0
                let cx = seg.a.x + abx * t, cy = seg.a.y + aby * t
                let dx = b.position.x - cx, dy = b.position.y - cy
                let distSq = dx * dx + dy * dy
                if distSq >= r * r || distSq == 0 { continue }
                let dist = distSq.squareRoot()
                let n = CGVector(dx: dx / dist, dy: dy / dist)
                b.position.x += n.dx * (r - dist)
                b.position.y += n.dy * (r - dist)
                let vn = b.velocity.dx * n.dx + b.velocity.dy * n.dy
                if vn < 0 {
                    b.velocity.dx -= (1 + cushionRestitution) * vn * n.dx
                    b.velocity.dy -= (1 + cushionRestitution) * vn * n.dy
                    applySideSpin(to: b, normal: n)
                }
            }
        }
    }

    /// English grips the cushion: friction on the spinning rim kicks the ball along the rail (`n` points into the table).
    private func applySideSpin(to b: Ball, normal n: CGVector) {
        guard b.sideSpin != 0 else { return }
        let kick = b.sideSpin * cushionSideSpinKick
        b.velocity.dx += -n.dy * kick
        b.velocity.dy += n.dx * kick
        b.sideSpin *= cushionSideSpinRetained
    }

    private func detectPockets(balls: [Ball], shot: inout ShotRecord, events: inout StepEvents) {
        for b in balls where !b.isPocketed {
            let pocket = nearestPocket(to: b.position)
            let dx = b.position.x - pocket.center.x
            let dy = b.position.y - pocket.center.y
            // A ball that has slipped past the jaw tips has nowhere else to go.
            let captured = dx * dx + dy * dy < pocket.radius * pocket.radius
                || geometry.overhang(b.position) > geometry.ballRadius * 1.2

            if captured {
                b.position = pocket.center
                b.isPocketed = true
                b.velocity = .zero
                b.spin = .zero
                b.sideSpin = 0
                shot.potted.append(b.number)
                events.potted.append(b)
            }
        }
    }

    func nearestPocket(to p: CGPoint) -> Pocket {
        pockets.min { a, b in
            hypot(a.center.x - p.x, a.center.y - p.y) < hypot(b.center.x - p.x, b.center.y - p.y)
        }!
    }

    // MARK: - Aim prediction

    struct AimPrediction {
        var cueEnd: CGPoint
        var hitBall: Ball?
        var objectDirection: CGVector?
        var cueDeflection: CGVector?
    }

    func predict(from origin: CGPoint, direction: CGVector, balls: [Ball]) -> AimPrediction {
        let r = geometry.ballRadius
        let felt = geometry.felt
        let dx = direction.dx
        let dy = direction.dy

        var tWall = CGFloat.greatestFiniteMagnitude
        if dx > 0 { tWall = min(tWall, (felt.maxX - r - origin.x) / dx) }
        if dx < 0 { tWall = min(tWall, (felt.minX + r - origin.x) / dx) }
        if dy > 0 { tWall = min(tWall, (felt.maxY - r - origin.y) / dy) }
        if dy < 0 { tWall = min(tWall, (felt.minY + r - origin.y) / dy) }
        tWall = max(tWall, 0)

        var tBest = tWall
        var hit: Ball?
        for b in balls where !b.isPocketed && !b.isCue {
            let ox = b.position.x - origin.x
            let oy = b.position.y - origin.y
            let proj = ox * dx + oy * dy
            if proj <= 0 { continue }
            let perpSq = ox * ox + oy * oy - proj * proj
            let reach = 4 * r * r
            if perpSq >= reach { continue }
            let t = proj - (reach - perpSq).squareRoot()
            if t > 0 && t < tBest {
                tBest = t
                hit = b
            }
        }

        let end = CGPoint(x: origin.x + dx * tBest, y: origin.y + dy * tBest)
        var prediction = AimPrediction(cueEnd: end)
        if let hit {
            prediction.hitBall = hit
            let nx = hit.position.x - end.x
            let ny = hit.position.y - end.y
            let len = max(hypot(nx, ny), 0.0001)
            let n = CGVector(dx: nx / len, dy: ny / len)
            prediction.objectDirection = n
            let dot = dx * n.dx + dy * n.dy
            let tx = dx - n.dx * dot
            let ty = dy - n.dy * dot
            let tl = hypot(tx, ty)
            if tl > 0.05 {
                prediction.cueDeflection = CGVector(dx: tx / tl, dy: ty / tl)
            }
        }
        return prediction
    }
}
