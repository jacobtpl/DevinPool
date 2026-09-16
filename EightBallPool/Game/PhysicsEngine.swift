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

/// Rigid-sphere billiard physics in the table plane. Each ball carries a full angular velocity and every
/// interaction is a Coulomb friction impulse through the contact point, so follow/draw/english, the
/// slide-to-roll transition, throw, spin transfer and cushion running/reverse english all fall out of
/// measured coefficients rather than tuning knobs. Sources:
///   - D. Alciatore, billiards.colostate.edu — physical-property constants (FAQ), TP A.14 (throw and the
///     speed-dependent ball-ball friction fit), TP A.31 / B.1 (squirt), TP B.2 (rolling and spin resistance).
///   - Mathavan, Jackson & Parkin, "A theoretical analysis of billiard ball dynamics under cushion
///     impacts", Proc. IMechE C 224 (2010) — the ball-cushion impact model and its fitted coefficients.
///   - W. Marlow, *The Physics of Pocket Billiards* (1995) — ball-ball friction data behind the A.14 fit.
///
/// Not modelled: the ball leaving the cloth (jumps, hops off a hard cushion hit), masse/swerve from cue
/// elevation, cushion deformation above ~2.5 m/s normal speed, and the tiny cloth "ball turn".
final class PhysicsEngine {
    let geometry: TableGeometry

    let substep: CGFloat = 1.0 / 480.0

    /// A 2.25" ball (radius 28.575 mm, 6 oz); everything else is derived from it.
    static let realBallRadius: CGFloat = 0.028575

    /// Cloth (Alciatore FAQ ranges: sliding 0.15–0.4, rolling 0.005–0.015, spin-down 5–15 rad/s²).
    let slidingFriction: CGFloat = 0.20
    let rollingFriction: CGFloat = 0.01
    /// Deceleration of a ball spinning in place, rad/s² (TP B.2 spin-down measurements).
    let spinDeceleration: CGFloat = 10

    /// Ball-ball restitution (FAQ 0.92–0.98). Friction follows Alciatore's fit to Marlow's data
    /// (TP A.14): μ = 0.009951 + 0.108·e^(−1.088·v_rel), v_rel in m/s — slow rubbing grips harder.
    let ballRestitution: CGFloat = 0.95
    func ballFriction(relativeSurfaceSpeed v: CGFloat) -> CGFloat {
        0.009951 + 0.108 * exp(-1.088 * v * PhysicsEngine.realBallRadius / geometry.ballRadius)
    }

    /// Cushion (Mathavan 2010 model and its fitted values): rubber restitution 0.98 and ball-rubber
    /// friction 0.14, with the nose gripping the ball at height 7R/5. Most of the speed a rebound
    /// loses comes from friction at the nose and the cloth, not from the rubber.
    let cushionRestitution: CGFloat = 0.98
    let cushionFriction: CGFloat = 0.14
    let cushionNoseHeight: CGFloat = 1.4

    /// Cue: ball-to-shaft-endmass ratio for squirt (TP A.31; ~19 gives 3° at a half-radius offset) and
    /// ball-to-cue mass ratio (6 oz / 19 oz) for the speed lost to spin on off-centre hits.
    let squirtMassRatio: CGFloat = 19
    let ballToCueMass: CGFloat = 6.0 / 19.0
    /// Beyond this offset a chalked tip (μ ≈ 0.6) slips off the ball: b/R = μ/√(1+μ²) ≈ 0.5.
    static let miscueOffset: CGFloat = 0.5

    /// Gravity in table units per second squared.
    let gravity: CGFloat
    private let stopSpeed: CGFloat

    private let cushionSegments: [CushionSegment]
    private let pockets: [Pocket]

    init(geometry: TableGeometry) {
        self.geometry = geometry
        cushionSegments = geometry.cushionSegments
        pockets = geometry.pockets
        gravity = 9.81 * geometry.ballRadius / PhysicsEngine.realBallRadius
        stopSpeed = geometry.ballRadius * 0.5
    }

    /// ~9 m/s, a hard break.
    var maxShotSpeed: CGFloat { geometry.ballRadius * 320 }
    /// ~0.35 m/s.
    var minShotSpeed: CGFloat { geometry.ballRadius * 12 }

    /// State of the cue ball the instant the tip leaves it. `tipOffset` is the strike point in ball radii
    /// (x right, y up as the shooter sees it) and `speed` is what a centre hit with this stroke would give.
    /// The tip imparts ω = 5·v·offset / (2r) (a 0.4r high hit starts with natural roll); the energy that
    /// goes into spin comes out of speed, and side offset squirts the ball away from the tip side.
    func strike(_ cue: Ball, direction d: CGVector, speed: CGFloat, tipOffset: CGPoint) {
        let r = geometry.ballRadius
        let dir = squirtedDirection(d, tipOffset: tipOffset)
        let b2 = tipOffset.x * tipOffset.x + tipOffset.y * tipOffset.y
        let v = speed * (1 + ballToCueMass) / (1 + ballToCueMass * (1 + 2.5 * b2))
        cue.velocity = CGVector(dx: dir.dx * v, dy: dir.dy * v)
        let spinRate = 2.5 * v / r
        // Topspin turns about z × dir; right english is counter-clockwise from above.
        cue.angularVelocity = SIMD3<Double>(
            Double(-dir.dy * spinRate * tipOffset.y),
            Double(dir.dx * spinRate * tipOffset.y),
            Double(spinRate * tipOffset.x)
        )
    }

    /// Squirt (TP A.31 eq. 13): the tip grips the ball, so the sideways reaction of the shaft's endmass
    /// pushes the ball off line by tan α = (5/2)·b·√(1−b²) / (1 + m_r + (5/2)·b²), b in ball radii.
    func squirtAngle(tipOffset: CGPoint) -> CGFloat {
        let b = min(max(tipOffset.x, -1), 1)
        return atan(2.5 * b * (1 - b * b).squareRoot() / (1 + squirtMassRatio + 2.5 * b * b))
    }

    /// Direction the cue ball actually leaves the tip in, for the aim guide.
    func squirtedDirection(_ d: CGVector, tipOffset: CGPoint) -> CGVector {
        let squirt = squirtAngle(tipOffset: tipOffset)
        return CGVector(dx: d.dx * cos(squirt) - d.dy * sin(squirt),
                        dy: d.dx * sin(squirt) + d.dy * cos(squirt))
    }

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

    /// Cloth contact. The contact point slips at u = v − r(ω × ẑ); while it does, friction μs·g acts on
    /// the centre against u and its torque spins the ball up, so u shrinks at 7/2·μs·g along a fixed
    /// line (the classic result behind stun, stop, follow and draw). Once u = 0 the ball rolls, held
    /// there by ω = ẑ × v / r and slowed only by rolling resistance. English decays at a constant rate.
    private func integrate(_ h: CGFloat, balls: [Ball]) {
        let r = geometry.ballRadius
        let g = gravity
        let slipDecel = 3.5 * slidingFriction * g
        let spinDecel = spinDeceleration

        for b in balls where !b.isPocketed && (b.isSpinning || b.isMoving) {
            var wx = CGFloat(b.angularVelocity.x)
            var wy = CGFloat(b.angularVelocity.y)
            var wz = CGFloat(b.angularVelocity.z)

            if wz != 0 {
                let mag = max(abs(wz) - spinDecel * h, 0)
                wz = mag == 0 ? 0 : (wz < 0 ? -mag : mag)
            }

            let ux = b.velocity.dx - r * wy
            let uy = b.velocity.dy + r * wx
            let slip = hypot(ux, uy)

            if slip > stopSpeed * 0.05 {
                let removed = min(slip, slipDecel * h)
                let f = removed / slip
                // Centre decelerates by 2/7 of the removed slip; the rest goes into spin.
                b.velocity.dx -= ux * f * (2.0 / 7.0)
                b.velocity.dy -= uy * f * (2.0 / 7.0)
                if removed >= slip {
                    wx = -b.velocity.dy / r
                    wy = b.velocity.dx / r
                } else {
                    wx -= (5.0 / 7.0) * uy * f / r
                    wy += (5.0 / 7.0) * ux * f / r
                }
            } else {
                let speed = b.speed
                let newSpeed = speed - rollingFriction * g * h
                if newSpeed <= stopSpeed {
                    b.velocity = .zero
                    wx = 0
                    wy = 0
                } else {
                    let scale = newSpeed / speed
                    b.velocity.dx *= scale
                    b.velocity.dy *= scale
                    wx = -b.velocity.dy / r
                    wy = b.velocity.dx / r
                }
            }

            b.angularVelocity = SIMD3<Double>(Double(wx), Double(wy), Double(wz))
            b.position.x += b.velocity.dx * h
            b.position.y += b.velocity.dy * h
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

                // Throw (TP A.14): the contact patches rub with relative velocity u = Δv − r(ωa+ωb)×n,
                // whose in-plane part comes from the cut angle and both balls' english and whose vertical
                // part comes from follow/draw. Friction acts along −u, capped at μ(|u|)·Jn or the impulse
                // that stops the rubbing (|u|/7: 1/m each for translation, 5/2m each for rotation). The
                // in-plane part throws the object ball and swaps english; the vertical part trades
                // follow/draw between the balls.
                let tx = -ny, ty = nx
                let wa = a.angularVelocity, wb = b.angularVelocity
                let ut = rvx * tx + rvy * ty - r * CGFloat(wa.z + wb.z)
                let uz = -r * (CGFloat(wa.x + wb.x) * ny - CGFloat(wa.y + wb.y) * nx)
                let slip = hypot(ut, uz)
                if slip > 0 {
                    let j = min(ballFriction(relativeSurfaceSpeed: slip) * impulse, slip / 7)
                    let jt = j * ut / slip, jz = j * uz / slip
                    a.velocity.dx += tx * jt
                    a.velocity.dy += ty * jt
                    b.velocity.dx -= tx * jt
                    b.velocity.dy -= ty * jt
                    let k = 2.5 / r
                    let dw = SIMD3<Double>(Double(k * jz * ny), Double(-k * jz * nx), Double(k * jt))
                    a.angularVelocity += dw
                    b.angularVelocity += dw
                }

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
                if vn < 0 { bounce(b, normal: n, normalSpeed: vn) }
            }
        }
    }

    /// Cushion impact, Mathavan, Jackson & Parkin (2010). The nose touches the ball at height 7R/5,
    /// so the contact normal is tilted θ = asin(2/5) above horizontal, and the impact is integrated
    /// over the normal impulse P rather than time: at each increment Coulomb friction acts at the nose
    /// (μw, against the slip there) and at the cloth (μs, against the slip there, driven by the
    /// downward component of the nose force). Compression runs until the normal velocity is gone;
    /// restitution returns e² of the compression work. This reproduces the measured rebound speeds
    /// and angles for stun, rolling, running and reverse english, and the rail-induced english.
    /// Frame (paper's): ŷ into the cushion (= −`n`), x̂ = ŷ × ẑ along the rail, ẑ up.
    private func bounce(_ b: Ball, normal n: CGVector, normalSpeed vn: CGFloat) {
        let r = geometry.ballRadius
        let sinT = cushionNoseHeight - 1
        let cosT = (1 - sinT * sinT).squareRoot()
        let xh = CGVector(dx: -n.dy, dy: n.dx)
        let yh = CGVector(dx: -n.dx, dy: -n.dy)
        let muW = cushionFriction, muS = slidingFriction

        var vx = b.velocity.dx * xh.dx + b.velocity.dy * xh.dy
        var vy = -vn
        let w = b.angularVelocity
        var wx = CGFloat(w.x) * xh.dx + CGFloat(w.y) * xh.dy
        var wy = CGFloat(w.x) * yh.dx + CGFloat(w.y) * yh.dy
        var wz = CGFloat(w.z)

        let k = 2.5 / r
        func advance(_ dP: CGFloat) -> CGFloat {
            // Slip at the nose (I) and at the cloth (C); friction opposes each.
            let vxI = vx + wy * r * sinT - wz * r * cosT
            let vyI = -vy * sinT + wx * r
            let vxC = vx - wy * r
            let vyC = vy + wx * r
            let sI = hypot(vxI, vyI), sC = hypot(vxC, vyC)
            let cI = sI > 0 ? vxI / sI : 0, sinI = sI > 0 ? vyI / sI : 0
            let cC = sC > 0 ? vxC / sC : 0, sinC = sC > 0 ? vyC / sC : 0
            // Normal force at the cloth that the tilted nose force presses down with.
            let cloth = sinT + muW * sinI * cosT
            vx -= (muW * cI + muS * cC * cloth) * dP
            vy -= (cosT - muW * sinT * sinI + muS * sinC * cloth) * dP
            wx -= k * (muW * sinI + muS * sinC * cloth) * dP
            wy -= k * (muW * cI * sinT - muS * cC * cloth) * dP
            wz += k * (muW * cI * cosT) * dP
            return dP * abs(vy) * cosT
        }

        let steps = 400
        var work: CGFloat = 0
        let dP = vy / CGFloat(steps)
        var guardCount = 0
        while vy > 0, guardCount < steps * 4 {
            work += advance(dP)
            guardCount += 1
        }
        let target = cushionRestitution * cushionRestitution * work
        var returned: CGFloat = 0
        guardCount = 0
        while returned < target, guardCount < steps * 4 {
            let remaining = target - returned
            let stepWork = dP * max(abs(vy), 1e-9) * cosT
            returned += advance(stepWork > remaining ? dP * remaining / stepWork : dP)
            guardCount += 1
        }

        b.velocity = CGVector(dx: vx * xh.dx + vy * yh.dx, dy: vx * xh.dy + vy * yh.dy)
        b.angularVelocity = SIMD3<Double>(
            Double(wx * xh.dx + wy * yh.dx),
            Double(wx * xh.dy + wy * yh.dy),
            Double(wz)
        )
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
                b.stop()
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
            // Same impulses as `resolveBallCollisions` for a stun cue ball at a typical 1.5 m/s, so the
            // guide includes cut-induced throw (english and speed effects are left to the player).
            let dot = dx * n.dx + dy * n.dy
            let tx = -n.dy, ty = n.dx
            let impulse = (1 + ballRestitution) * dot * 0.5
            let slip = -(dx * tx + dy * ty)
            let typicalSpeed = 1.5 * geometry.ballRadius / PhysicsEngine.realBallRadius
            let mu = ballFriction(relativeSurfaceSpeed: abs(slip) * typicalSpeed)
            let jt = min(mu * impulse, abs(slip) / 7) * (slip < 0 ? -1 : 1)
            let ox = n.dx * impulse - tx * jt, oy = n.dy * impulse - ty * jt
            let ol = max(hypot(ox, oy), 0.0001)
            prediction.objectDirection = CGVector(dx: ox / ol, dy: oy / ol)
            let cx = dx - n.dx * impulse + tx * jt, cy = dy - n.dy * impulse + ty * jt
            let cl = hypot(cx, cy)
            if cl > 0.05 {
                prediction.cueDeflection = CGVector(dx: cx / cl, dy: cy / cl)
            }
        }
        return prediction
    }
}
