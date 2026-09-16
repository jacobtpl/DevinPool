import CoreGraphics

struct TableGeometry {
    /// Playing surface bounded by the cushion noses.
    let felt: CGRect
    let ballRadius: CGFloat

    var pocketRadius: CGFloat { ballRadius * 2.1 }
    /// Capture radius for a ball that has already passed the cushion line into the jaws.
    var jawCaptureRadius: CGFloat { ballRadius * 3.0 }
    /// Length of cushion next to each felt corner that belongs to the corner pocket's jaws.
    var cornerMouth: CGFloat { ballRadius * 2.6 }
    /// Half-width of the side pocket opening along the long rails.
    var sideMouthHalf: CGFloat { ballRadius * 2.2 }

    var cornerPocketOffset: CGFloat { ballRadius * 0.4 }
    var sidePocketOffset: CGFloat { ballRadius * 0.6 }

    var pockets: [CGPoint] {
        let c = cornerPocketOffset
        let s = sidePocketOffset
        return [
            CGPoint(x: felt.minX - c, y: felt.minY - c),
            CGPoint(x: felt.maxX + c, y: felt.minY - c),
            CGPoint(x: felt.minX - c, y: felt.maxY + c),
            CGPoint(x: felt.maxX + c, y: felt.maxY + c),
            CGPoint(x: felt.minX - s, y: felt.midY),
            CGPoint(x: felt.maxX + s, y: felt.midY),
        ]
    }

    var headSpot: CGPoint { CGPoint(x: felt.midX, y: felt.minY + felt.height * 0.25) }
    var footSpot: CGPoint { CGPoint(x: felt.midX, y: felt.minY + felt.height * 0.75) }

    /// True when a ball touching a long (vertical) rail at this y is inside a pocket opening.
    func isMouthOnLongRail(y: CGFloat) -> Bool {
        y < felt.minY + cornerMouth || y > felt.maxY - cornerMouth || abs(y - felt.midY) < sideMouthHalf
    }

    /// True when a ball touching a short (horizontal) rail at this x is inside a corner pocket opening.
    func isMouthOnShortRail(x: CGFloat) -> Bool {
        x < felt.minX + cornerMouth || x > felt.maxX - cornerMouth
    }

    /// True once a ball's centre has crossed the cushion line (only possible inside a pocket opening).
    func isInJaws(_ p: CGPoint) -> Bool {
        let r = ballRadius * 0.5
        return p.x < felt.minX + r || p.x > felt.maxX - r || p.y < felt.minY + r || p.y > felt.maxY - r
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

    init(geometry: TableGeometry) {
        self.geometry = geometry
        rollingDeceleration = geometry.ballRadius * 5.0
        stopSpeed = geometry.ballRadius * 0.5
    }

    var maxShotSpeed: CGFloat { geometry.ballRadius * 160 }
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
        for b in balls where !b.isPocketed && b.isMoving {
            let speed = b.speed
            b.position.x += b.velocity.dx * h
            b.position.y += b.velocity.dy * h

            let newSpeed = speed - (rollingDeceleration + speed * damping) * h
            if newSpeed <= stopSpeed {
                b.velocity = .zero
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

    private func resolveCushions(balls: [Ball]) {
        let r = geometry.ballRadius
        let felt = geometry.felt
        for b in balls where !b.isPocketed {
            if !geometry.isMouthOnLongRail(y: b.position.y) {
                if b.position.x - r < felt.minX {
                    b.position.x = felt.minX + r
                    if b.velocity.dx < 0 { b.velocity.dx = -b.velocity.dx * cushionRestitution }
                } else if b.position.x + r > felt.maxX {
                    b.position.x = felt.maxX - r
                    if b.velocity.dx > 0 { b.velocity.dx = -b.velocity.dx * cushionRestitution }
                }
            }
            if !geometry.isMouthOnShortRail(x: b.position.x) {
                if b.position.y - r < felt.minY {
                    b.position.y = felt.minY + r
                    if b.velocity.dy < 0 { b.velocity.dy = -b.velocity.dy * cushionRestitution }
                } else if b.position.y + r > felt.maxY {
                    b.position.y = felt.maxY - r
                    if b.velocity.dy > 0 { b.velocity.dy = -b.velocity.dy * cushionRestitution }
                }
            }
        }
    }

    private func detectPockets(balls: [Ball], shot: inout ShotRecord, events: inout StepEvents) {
        let captureSq = geometry.pocketRadius * geometry.pocketRadius
        let jawCaptureSq = geometry.jawCaptureRadius * geometry.jawCaptureRadius
        for b in balls where !b.isPocketed {
            let pocket = nearestPocket(to: b.position)
            let dx = b.position.x - pocket.x
            let dy = b.position.y - pocket.y
            let distSq = dx * dx + dy * dy
            var captured = distSq < captureSq

            if !captured, geometry.isInJaws(b.position) {
                if distSq < jawCaptureSq {
                    captured = true
                } else {
                    // Angled jaws: funnel the ball towards the pocket centre.
                    let dist = distSq.squareRoot()
                    if !b.isMoving {
                        b.velocity = CGVector(dx: -dx / dist * stopSpeed * 4, dy: -dy / dist * stopSpeed * 4)
                    }
                    let speed = b.speed
                    let blend: CGFloat = 0.12
                    var vx = b.velocity.dx / speed * (1 - blend) - dx / dist * blend
                    var vy = b.velocity.dy / speed * (1 - blend) - dy / dist * blend
                    let len = max(hypot(vx, vy), 0.0001)
                    vx /= len
                    vy /= len
                    b.velocity = CGVector(dx: vx * speed, dy: vy * speed)
                }
            }

            if captured {
                b.position = pocket
                b.isPocketed = true
                b.velocity = .zero
                shot.potted.append(b.number)
                events.potted.append(b)
            }
        }
    }

    func nearestPocket(to p: CGPoint) -> CGPoint {
        geometry.pockets.min { a, b in
            hypot(a.x - p.x, a.y - p.y) < hypot(b.x - p.x, b.y - p.y)
        } ?? p
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
