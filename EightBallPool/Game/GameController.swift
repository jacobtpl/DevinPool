import SceneKit
import UIKit

enum CameraMode: Equatable {
    /// Player's eye view from behind the cue ball, looking down the cue.
    case pov
    /// Straight down onto the table.
    case overhead
}

/// Runs the game: rules, physics, input and the camera, and keeps the SceneKit scene in sync.
/// World units are ball radii (7 ft table: felt 34 × 68).
@MainActor
final class GameController {
    weak var model: GameModel?
    weak var view: SCNView?

    let geometry = TableGeometry(felt: CGRect(x: -17, y: -34, width: 34, height: 68), ballRadius: 1)
    let engine: PhysicsEngine
    let table: TableScene

    private var balls: [Ball] = []
    private var rules = EightBallRules()
    private var shot = ShotRecord()
    private var ballsBeforeShot: [Int] = []
    private(set) var phase: GamePhase = .aiming {
        didSet { model?.phase = phase }
    }

    private var aimDirection = CGVector(dx: 0, dy: 1)
    private var shotOrigin = CGPoint.zero
    private var draggingCue = false
    private var lastTouch: CGPoint?

    /// Eye height above the cloth in the POV view (ball radii); drag vertically to change it.
    private var eyeHeight: CGFloat = 11
    private var cameraPosition = simd_float3(0, 40, 60)
    private var cameraTarget = simd_float3(0, 0, 0)
    private var cameraUp = simd_float3(0, 1, 0)
    private var cameraSnapped = false

    private var displayLink: CADisplayLink?
    private var lastUpdate: CFTimeInterval = 0
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private var hapticCooldown: TimeInterval = 0

    private var cueBall: Ball? { balls.first { $0.isCue } }
    private var ballsOnTable: [Int] { balls.filter { !$0.isPocketed }.map(\.number) }

    init() {
        engine = PhysicsEngine(geometry: geometry)
        table = TableScene(geometry: geometry)
        newGame()
    }

    // MARK: - Lifecycle

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastUpdate = 0
    }

    func newGame() {
        rules.reset()
        shot = ShotRecord()
        draggingCue = false
        aimDirection = CGVector(dx: 0, dy: 1)
        balls = rackBalls()
        table.setBalls(balls)
        phase = .aiming
        model?.cameraMode = .pov
        model?.message = "Player 1 to break — drag to aim, pull the power bar down to shoot"
        cameraSnapped = false
        syncModel()
    }

    private func rackBalls() -> [Ball] {
        let r = geometry.ballRadius
        let rows: [[Int]] = [[1], [11, 2], [3, 8, 10], [12, 4, 13, 5], [6, 14, 7, 15, 9]]
        var result: [Ball] = [Ball(number: 0, position: geometry.headSpot)]
        let apex = geometry.footSpot
        let rowSpacing = r * 2 * 0.8660254 + 0.02
        for (rowIndex, row) in rows.enumerated() {
            let y = apex.y + CGFloat(rowIndex) * rowSpacing
            for (i, number) in row.enumerated() {
                let x = apex.x + (CGFloat(i) - CGFloat(row.count - 1) / 2) * (r * 2 + 0.02)
                result.append(Ball(number: number, position: CGPoint(x: x, y: y)))
            }
        }
        for ball in result { ball.randomizeOrientation() }
        return result
    }

    // MARK: - Shooting

    func shoot(power: CGFloat, spin: CGPoint) {
        guard let cue = cueBall, !cue.isPocketed, phase == .aiming || phase == .ballInHand else { return }
        let clamped = min(max(power, 0), 1)
        phase = .shooting
        draggingCue = false
        lastTouch = nil
        ballsBeforeShot = ballsOnTable
        shot = ShotRecord()
        shotOrigin = cue.position

        let speed = engine.minShotSpeed + (engine.maxShotSpeed - engine.minShotSpeed) * clamped * clamped
        let direction = aimDirection
        let pullback = geometry.ballRadius * (0.6 + clamped * 7)
        let tip = CGPoint(x: min(max(spin.x, -GameModel.maxSpinOffset), GameModel.maxSpinOffset),
                          y: min(max(spin.y, -GameModel.maxSpinOffset), GameModel.maxSpinOffset))

        table.placeCue(cueBall: cue.position, aim: direction, gap: pullback, tipOffset: tip)
        table.strokeCue(along: direction, distance: pullback, duration: 0.09) { [weak self] in
            guard let self, self.phase == .shooting else { return }
            self.engine.strike(cue, direction: direction, cueSpeed: speed, tipOffset: tip)
            self.table.hideCue()
            self.mediumHaptic.impactOccurred(intensity: 0.4 + 0.6 * clamped)
            self.phase = .ballsMoving
            self.model?.message = ""
        }
    }

    private func endShot() {
        let result = rules.resolve(shot: shot, ballsBefore: ballsBeforeShot)
        for ball in balls { ball.stop() }

        if result.respotEight, let eight = balls.first(where: { $0.isEight }) {
            restore(eight, at: freeSpot(near: geometry.footSpot, searchUp: true))
        }
        if let cue = cueBall, cue.isPocketed {
            restore(cue, at: freeSpot(near: geometry.headSpot, searchUp: false))
        }

        if let winner = result.winner {
            phase = .gameOver(winner: winner)
        } else if result.ballInHand {
            phase = .ballInHand
            model?.cameraMode = .overhead
        } else {
            phase = .aiming
        }
        model?.message = result.message
        aimDirection = defaultAimDirection()
        syncModel()
    }

    private func defaultAimDirection() -> CGVector {
        guard let cue = cueBall else { return CGVector(dx: 0, dy: 1) }
        let group = rules.group(of: rules.currentPlayer)
        let onEight = rules.isOnEight(rules.currentPlayer, ballsOnTable: ballsOnTable)
        let targets = balls.filter { b in
            guard !b.isPocketed, !b.isCue else { return false }
            if onEight { return b.isEight }
            if let group { return b.group == group }
            return !b.isEight
        }
        func dist(_ b: Ball) -> CGFloat { hypot(b.position.x - cue.position.x, b.position.y - cue.position.y) }
        guard let target = targets.min(by: { dist($0) < dist($1) }) else { return CGVector(dx: 0, dy: 1) }
        let dx = target.position.x - cue.position.x, dy = target.position.y - cue.position.y
        let len = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private func restore(_ ball: Ball, at position: CGPoint) {
        ball.isPocketed = false
        ball.stop()
        ball.position = position
        table.restoreBall(ball)
    }

    private func freeSpot(near start: CGPoint, searchUp: Bool) -> CGPoint {
        let step = geometry.ballRadius * 0.5 * (searchUp ? 1 : -1)
        var candidate = start
        for _ in 0..<400 {
            if isFree(candidate) { return geometry.clampInside(candidate) }
            candidate.y += step
            if candidate.y > geometry.felt.maxY - geometry.ballRadius || candidate.y < geometry.felt.minY + geometry.ballRadius {
                candidate.y = start.y
                candidate.x += geometry.ballRadius * 0.5
            }
        }
        return geometry.clampInside(start)
    }

    private func isFree(_ p: CGPoint, ignoring ignored: Ball? = nil) -> Bool {
        let minDist = geometry.ballRadius * 2 + 0.02
        for b in balls where !b.isPocketed && b !== ignored {
            if hypot(b.position.x - p.x, b.position.y - p.y) < minDist { return false }
        }
        return true
    }

    private func syncModel() {
        guard let model else { return }
        let onTable = ballsOnTable
        model.currentPlayer = rules.currentPlayer
        model.isOpenTable = rules.isOpenTable
        model.players = [1, 2].map { player in
            let group = rules.group(of: player)
            let remaining = group.map { g in onTable.filter { groupOf($0) == g }.sorted() } ?? []
            return PlayerStatus(number: player, group: group, remaining: remaining)
        }
    }

    // MARK: - Frame update

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt: CGFloat = lastUpdate == 0 ? 1.0 / 60.0 : CGFloat(min(now - lastUpdate, 1.0 / 30.0))
        lastUpdate = now
        hapticCooldown = max(0, hapticCooldown - TimeInterval(dt))

        if phase == .ballsMoving {
            let events = engine.step(dt: dt, balls: balls, shot: &shot)
            for ball in balls where !ball.isPocketed && ball.isSpinning {
                ball.roll(dt: dt)
            }
            for ball in events.potted {
                mediumHaptic.impactOccurred(intensity: 0.8)
                table.dropBall(ball)
            }
            if events.strongestCollision > geometry.ballRadius * 4, hapticCooldown == 0 {
                lightHaptic.impactOccurred(intensity: min(1, events.strongestCollision / engine.maxShotSpeed + 0.3))
                hapticCooldown = 0.05
            }
            if !balls.contains(where: { !$0.isPocketed && $0.isActive }) {
                endShot()
            }
        }

        table.sync(balls)
        updateGuideAndCue()
        updateCamera(dt: dt)
    }

    private func updateGuideAndCue() {
        guard let cue = cueBall, !cue.isPocketed, phase == .aiming || phase == .ballInHand || phase == .shooting else {
            table.hideGuide()
            if phase != .shooting { table.hideCue() }
            return
        }
        let tip = model?.spin ?? .zero
        if model?.showGuide == true, phase != .shooting {
            let launch = engine.squirtedDirection(aimDirection, tipOffset: tip)
            table.showGuide(from: cue.position, prediction: engine.predict(from: cue.position, direction: launch, balls: balls))
        } else {
            table.hideGuide()
        }

        if phase != .shooting {
            let power = min(max(model?.power ?? 0, 0), 1)
            table.placeCue(cueBall: cue.position, aim: aimDirection, gap: geometry.ballRadius * (0.6 + power * 7), tipOffset: tip)
        }
    }

    // MARK: - Camera

    private func updateCamera(dt: CGFloat) {
        let (position, target, up) = desiredCamera()
        if cameraSnapped {
            let k = Float(1 - exp(-6 * dt))
            cameraPosition += (position - cameraPosition) * k
            cameraTarget += (target - cameraTarget) * k
            cameraUp = simd_normalize(cameraUp + (up - cameraUp) * k)
        } else {
            cameraPosition = position
            cameraTarget = target
            cameraUp = up
            cameraSnapped = true
        }
        table.cameraNode.simdPosition = cameraPosition
        table.cameraNode.simdLook(at: cameraTarget, up: cameraUp, localFront: simd_float3(0, 0, -1))
    }

    private func desiredCamera() -> (simd_float3, simd_float3, simd_float3) {
        let felt = geometry.felt
        let centre = simd_float3(Float(felt.midX), 0, Float(-felt.midY))
        let mode = model?.cameraMode ?? .pov
        let cuePos = (cueBall.map { $0.isPocketed ? shotOrigin : $0.position }) ?? geometry.headSpot
        let aim = TableScene.sceneVector(aimDirection)

        switch (mode, phase) {
        case (.overhead, _):
            return (centre + simd_float3(0, 80, 0), centre, simd_float3(0, 0, -1))
        case (.pov, .ballsMoving):
            // Stand up and watch: behind where the shot was played, high enough to see the whole table.
            let origin = simd_float3(Float(shotOrigin.x), 0, Float(-shotOrigin.y))
            return (origin - aim * 24 + simd_float3(0, 40, 0), centre, simd_float3(0, 1, 0))
        default:
            let ball = simd_float3(Float(cuePos.x), 0, Float(-cuePos.y))
            let height = Float(eyeHeight)
            // Down in the stance: eye behind and above the cue ball, sighting along the cue toward the far
            // end of the table so the ball sits in the lower part of the frame.
            let back = 14 + height * 0.5
            let eye = ball - aim * back + simd_float3(0, height, 0)
            let look = ball + aim * 20
            return (eye, look, simd_float3(0, 1, 0))
        }
    }

    // MARK: - Touch input (points in the SCNView)

    func touchBegan(at p: CGPoint) {
        guard let cue = cueBall, phase == .aiming || phase == .ballInHand else { return }
        lastTouch = p
        if phase == .ballInHand, model?.cameraMode == .overhead, let t = tablePoint(at: p),
           hypot(t.x - cue.position.x, t.y - cue.position.y) < geometry.ballRadius * 3.5 {
            draggingCue = true
        }
    }

    func touchMoved(to p: CGPoint) {
        guard phase == .aiming || phase == .ballInHand, let last = lastTouch else { return }
        defer { lastTouch = p }
        if draggingCue {
            if let t = tablePoint(at: p) { placeCue(at: t) }
            return
        }
        switch model?.cameraMode ?? .pov {
        case .pov:
            guard let view else { return }
            // Walk around the ball: a full-width swipe turns 70°; a full-height swipe spans the eye range.
            let yaw = -(p.x - last.x) / view.bounds.width * (70 * .pi / 180)
            let angle = atan2(aimDirection.dy, aimDirection.dx) + yaw
            aimDirection = CGVector(dx: cos(angle), dy: sin(angle))
            eyeHeight = min(max(eyeHeight + (p.y - last.y) / view.bounds.height * 24, 5), 30)
        case .overhead:
            if let a = tablePoint(at: last), let b = tablePoint(at: p) { rotateAim(from: a, to: b) }
        }
    }

    func touchEnded() {
        draggingCue = false
        lastTouch = nil
    }

    /// Where a screen point lands on the plane of the ball centres.
    private func tablePoint(at p: CGPoint) -> CGPoint? {
        guard let view else { return nil }
        let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let dy = far.y - near.y
        guard abs(dy) > 1e-6 else { return nil }
        let t = (Float(geometry.ballRadius) - near.y) / dy
        guard t > 0 else { return nil }
        return TableScene.tablePoint(SCNVector3(near.x + (far.x - near.x) * t, 0, near.z + (far.z - near.z) * t))
    }

    /// Rotates the aim by the angle the finger sweeps around the cue ball (table coordinates), blending
    /// into a sideways swipe close to the ball where the sweep angle is ill-defined.
    private func rotateAim(from a: CGPoint, to b: CGPoint) {
        guard let cue = cueBall else { return }
        let r = geometry.ballRadius
        let ax = a.x - cue.position.x, ay = a.y - cue.position.y
        let bx = b.x - cue.position.x, by = b.y - cue.position.y
        let distance = max(hypot(bx, by), 0.001)

        var sweep = atan2(by, bx) - atan2(ay, ax)
        if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }

        let right = CGVector(dx: aimDirection.dy, dy: -aimDirection.dx)
        let lateral = (b.x - a.x) * right.dx + (b.y - a.y) * right.dy
        let swipe = -lateral / geometry.felt.width * (.pi / 2)

        let near = r * 3, far = r * 9
        let blend = min(max((distance - near) / (far - near), 0), 1)
        let delta = sweep * blend + swipe * (1 - blend)
        let current = atan2(aimDirection.dy, aimDirection.dx) + delta
        aimDirection = CGVector(dx: cos(current), dy: sin(current))
    }

    private func placeCue(at p: CGPoint) {
        guard let cue = cueBall else { return }
        let target = geometry.clampInside(p)
        if isFree(target, ignoring: cue) { cue.position = target }
    }
}
