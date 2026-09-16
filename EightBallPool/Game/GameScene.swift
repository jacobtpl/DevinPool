import SpriteKit
import UIKit

final class GameScene: SKScene {
    weak var model: GameModel?

    /// Space reserved for the SwiftUI HUD (in points, scene coordinates match view points).
    var hudInsets = UIEdgeInsets(top: 150, left: 14, bottom: 140, right: 14) {
        didSet { if hudInsets != oldValue { rebuildIfNeeded() } }
    }

    private struct LayoutKey: Equatable {
        var size: CGSize
        var insets: UIEdgeInsets
    }
    private var lastLayoutKey: LayoutKey?

    private(set) var geometry: TableGeometry?
    private var engine: PhysicsEngine?

    private var balls: [Ball] = []
    private var ballNodes: [Int: SKSpriteNode] = [:]
    private var shadowNodes: [Int: SKSpriteNode] = [:]

    private let tableLayer = SKNode()
    private let ballLayer = SKNode()
    private let overlayLayer = SKNode()

    private let aimLine = SKShapeNode()
    private let ghostBall = SKShapeNode()
    private let objectLine = SKShapeNode()
    private let deflectionLine = SKShapeNode()
    private let cueStick = SKNode()

    private var rules = EightBallRules()
    private var shot = ShotRecord()
    private var ballsBeforeShot: [Int] = []
    private var phase: GamePhase = .aiming {
        didSet { model?.phase = phase }
    }

    private var aimDirection = CGVector(dx: 0, dy: 1)
    private var draggingCue = false
    private var lastAimTouch: CGPoint?
    private var lastUpdate: TimeInterval = 0

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private var hapticCooldown: TimeInterval = 0

    private var cueBall: Ball? { balls.first { $0.isCue } }
    private var ballsOnTable: [Int] { balls.filter { !$0.isPocketed }.map(\.number) }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1)
        if tableLayer.parent == nil {
            addChild(tableLayer)
            addChild(ballLayer)
            addChild(overlayLayer)
            tableLayer.zPosition = 0
            ballLayer.zPosition = 10
            overlayLayer.zPosition = 20
            setupOverlayNodes()
        }
        rebuildIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildIfNeeded()
    }

    private func rebuildIfNeeded() {
        guard size.width > 50, size.height > 50, tableLayer.parent != nil else { return }
        let key = LayoutKey(size: size, insets: hudInsets)
        if key == lastLayoutKey { return }
        lastLayoutKey = key

        let oldGeometry = geometry
        layoutTable()
        guard let old = oldGeometry, let new = geometry, !balls.isEmpty else {
            newGame()
            return
        }
        // Keep the game in progress: map ball positions from the old felt onto the new one.
        for ball in balls {
            let u = (ball.position.x - old.felt.minX) / old.felt.width
            let v = (ball.position.y - old.felt.minY) / old.felt.height
            ball.position = CGPoint(x: new.felt.minX + u * new.felt.width, y: new.felt.minY + v * new.felt.height)
            let scale = new.ballRadius / old.ballRadius
            ball.velocity = CGVector(dx: ball.velocity.dx * scale, dy: ball.velocity.dy * scale)
        }
        createBallNodes(new)
        buildCueStick(new)
        syncNodes()
    }

    private func layoutTable() {
        let available = CGRect(
            x: hudInsets.left,
            y: hudInsets.bottom,
            width: size.width - hudInsets.left - hudInsets.right,
            height: size.height - hudInsets.top - hudInsets.bottom
        )
        let railFraction: CGFloat = 0.1
        // Felt is 1:2, surrounded by rails; fit the whole thing in `available`.
        var feltWidth = available.width / (1 + 2 * railFraction)
        var feltHeight = feltWidth * 2
        if feltHeight + 2 * railFraction * feltWidth > available.height {
            feltWidth = available.height / (2 + 2 * railFraction)
            feltHeight = feltWidth * 2
        }
        let felt = CGRect(
            x: available.midX - feltWidth / 2,
            y: available.midY - feltHeight / 2,
            width: feltWidth,
            height: feltHeight
        )
        let geo = TableGeometry(felt: felt, ballRadius: feltWidth / 34)
        geometry = geo
        engine = PhysicsEngine(geometry: geo)
        drawTable(geo, railWidth: feltWidth * railFraction)
    }

    private func drawTable(_ geo: TableGeometry, railWidth: CGFloat) {
        tableLayer.removeAllChildren()
        let felt = geo.felt

        let frame = SKShapeNode(rect: felt.insetBy(dx: -railWidth, dy: -railWidth), cornerRadius: railWidth * 0.8)
        frame.fillColor = UIColor(red: 0.36, green: 0.21, blue: 0.11, alpha: 1)
        frame.strokeColor = UIColor(red: 0.22, green: 0.12, blue: 0.06, alpha: 1)
        frame.lineWidth = 2
        frame.zPosition = 0
        tableLayer.addChild(frame)

        // Cloth runs under the cushions and into the pocket mouths.
        let cushionDepth = railWidth * 0.45
        let surface = SKShapeNode(rect: felt.insetBy(dx: -cushionDepth, dy: -cushionDepth))
        surface.fillColor = UIColor(red: 0.10, green: 0.50, blue: 0.26, alpha: 1)
        surface.strokeColor = .clear
        surface.zPosition = 1
        tableLayer.addChild(surface)

        for p in geo.pockets {
            let hole = SKShapeNode(circleOfRadius: p.radius * 0.95)
            hole.position = p.center
            hole.fillColor = UIColor(white: 0.02, alpha: 1)
            hole.strokeColor = UIColor(white: 0.3, alpha: 0.5)
            hole.lineWidth = 1
            hole.zPosition = 2
            tableLayer.addChild(hole)
        }

        let cushionColor = UIColor(red: 0.05, green: 0.34, blue: 0.17, alpha: 1)
        let noseColor = UIColor(red: 0.03, green: 0.26, blue: 0.13, alpha: 1)
        for piece in geo.cushions {
            // Face points, then back along the rail side deep enough to cover the jaws.
            let out = piece.outward
            func beyondFelt(_ p: CGPoint) -> CGFloat {
                (p.x - felt.midX) * out.dx + (p.y - felt.midY) * out.dy - (out.dx != 0 ? felt.width : felt.height) / 2
            }
            let depth = max(cushionDepth, piece.face.map(beyondFelt).max() ?? 0) + 1
            let path = CGMutablePath()
            path.addLines(between: piece.face)
            for p in piece.face.reversed() {
                let push = depth - beyondFelt(p)
                path.addLine(to: CGPoint(x: p.x + out.dx * push, y: p.y + out.dy * push))
            }
            path.closeSubpath()
            let cushion = SKShapeNode(path: path)
            cushion.fillColor = cushionColor
            cushion.strokeColor = noseColor
            cushion.lineWidth = 1.5
            cushion.lineJoin = .round
            cushion.zPosition = 3
            tableLayer.addChild(cushion)
        }

        // Head string and foot spot.
        let headLine = SKShapeNode()
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: felt.minX, y: geo.headSpot.y))
        headPath.addLine(to: CGPoint(x: felt.maxX, y: geo.headSpot.y))
        headLine.path = headPath
        headLine.strokeColor = UIColor(white: 1, alpha: 0.10)
        headLine.lineWidth = 1
        headLine.zPosition = 3
        tableLayer.addChild(headLine)

        let footDot = SKShapeNode(circleOfRadius: geo.ballRadius * 0.22)
        footDot.position = geo.footSpot
        footDot.fillColor = UIColor(white: 1, alpha: 0.25)
        footDot.strokeColor = .clear
        footDot.zPosition = 3
        tableLayer.addChild(footDot)

        // Rail diamonds.
        let diamondColor = UIColor(red: 0.93, green: 0.88, blue: 0.75, alpha: 0.9)
        let diamondOffset = railWidth * 0.72
        for i in 1...3 {
            let y = felt.minY + felt.height * CGFloat(i) / 8
            let y2 = felt.maxY - felt.height * CGFloat(i) / 8
            for yy in [y, y2] {
                for x in [felt.minX - diamondOffset, felt.maxX + diamondOffset] {
                    tableLayer.addChild(diamond(at: CGPoint(x: x, y: yy), size: railWidth * 0.22, color: diamondColor))
                }
            }
        }
        for i in 1...3 {
            let x = felt.minX + felt.width * CGFloat(i) / 4
            for y in [felt.minY - diamondOffset, felt.maxY + diamondOffset] {
                tableLayer.addChild(diamond(at: CGPoint(x: x, y: y), size: railWidth * 0.22, color: diamondColor))
            }
        }

    }

    private func diamond(at point: CGPoint, size: CGFloat, color: UIColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size))
        path.addLine(to: CGPoint(x: size * 0.6, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -size))
        path.addLine(to: CGPoint(x: -size * 0.6, y: 0))
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.position = point
        node.fillColor = color
        node.strokeColor = .clear
        node.zPosition = 1
        return node
    }

    private func setupOverlayNodes() {
        aimLine.strokeColor = UIColor(white: 1, alpha: 0.75)
        aimLine.lineWidth = 1.5
        aimLine.zPosition = 1
        overlayLayer.addChild(aimLine)

        ghostBall.strokeColor = UIColor(white: 1, alpha: 0.8)
        ghostBall.fillColor = UIColor(white: 1, alpha: 0.12)
        ghostBall.lineWidth = 1.2
        ghostBall.zPosition = 1
        overlayLayer.addChild(ghostBall)

        objectLine.strokeColor = UIColor(white: 1, alpha: 0.55)
        objectLine.lineWidth = 1.5
        objectLine.zPosition = 1
        overlayLayer.addChild(objectLine)

        deflectionLine.strokeColor = UIColor(white: 1, alpha: 0.35)
        deflectionLine.lineWidth = 1.2
        deflectionLine.zPosition = 1
        overlayLayer.addChild(deflectionLine)

        cueStick.zPosition = 5
        overlayLayer.addChild(cueStick)
    }

    private func buildCueStick(_ geo: TableGeometry) {
        cueStick.removeAllChildren()
        let r = geo.ballRadius
        let length = r * 26
        let tipWidth = r * 0.55
        let buttWidth = r * 1.0

        let shaft = SKShapeNode()
        let shaftPath = CGMutablePath()
        shaftPath.move(to: CGPoint(x: 0, y: -tipWidth / 2))
        shaftPath.addLine(to: CGPoint(x: length * 0.62, y: -(tipWidth + (buttWidth - tipWidth) * 0.62) / 2))
        shaftPath.addLine(to: CGPoint(x: length * 0.62, y: (tipWidth + (buttWidth - tipWidth) * 0.62) / 2))
        shaftPath.addLine(to: CGPoint(x: 0, y: tipWidth / 2))
        shaftPath.closeSubpath()
        shaft.path = shaftPath
        shaft.fillColor = UIColor(red: 0.87, green: 0.72, blue: 0.48, alpha: 1)
        shaft.strokeColor = UIColor(red: 0.55, green: 0.40, blue: 0.22, alpha: 1)
        shaft.lineWidth = 0.8
        cueStick.addChild(shaft)

        let butt = SKShapeNode()
        let buttPath = CGMutablePath()
        let midW = tipWidth + (buttWidth - tipWidth) * 0.62
        buttPath.move(to: CGPoint(x: length * 0.62, y: -midW / 2))
        buttPath.addLine(to: CGPoint(x: length, y: -buttWidth / 2))
        buttPath.addLine(to: CGPoint(x: length, y: buttWidth / 2))
        buttPath.addLine(to: CGPoint(x: length * 0.62, y: midW / 2))
        buttPath.closeSubpath()
        butt.path = buttPath
        butt.fillColor = UIColor(red: 0.22, green: 0.10, blue: 0.06, alpha: 1)
        butt.strokeColor = UIColor(red: 0.12, green: 0.05, blue: 0.03, alpha: 1)
        butt.lineWidth = 0.8
        cueStick.addChild(butt)

        let ferrule = SKShapeNode(rect: CGRect(x: 0, y: -tipWidth / 2, width: r * 0.5, height: tipWidth))
        ferrule.fillColor = UIColor(white: 0.95, alpha: 1)
        ferrule.strokeColor = .clear
        cueStick.addChild(ferrule)

        let tip = SKShapeNode(rect: CGRect(x: -r * 0.18, y: -tipWidth / 2, width: r * 0.18, height: tipWidth))
        tip.fillColor = UIColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1)
        tip.strokeColor = .clear
        cueStick.addChild(tip)
    }

    // MARK: - Game lifecycle

    func newGame() {
        guard let geo = geometry else { return }
        rules.reset()
        shot = ShotRecord()
        draggingCue = false
        aimDirection = CGVector(dx: 0, dy: 1)

        balls = rackBalls(geo)
        createBallNodes(geo)
        buildCueStick(geo)
        phase = .aiming
        model?.message = "Player 1 to break — drag to rotate the cue, pull the power bar down to shoot"
        syncModel()
        syncNodes()
    }

    private func createBallNodes(_ geo: TableGeometry) {
        ballLayer.removeAllChildren()
        ballNodes.removeAll()
        shadowNodes.removeAll()

        let diameter = geo.ballRadius * 2
        let shadowTexture = BallTextures.shadowTexture(diameter: diameter)
        for ball in balls {
            let shadow = SKSpriteNode(texture: shadowTexture)
            shadow.size = CGSize(width: diameter * 1.5, height: diameter * 1.5)
            shadow.zPosition = 0
            shadow.isHidden = ball.isPocketed
            ballLayer.addChild(shadow)
            shadowNodes[ball.number] = shadow

            let node = SKSpriteNode(texture: BallTextures.sphereMap(number: ball.number))
            node.size = CGSize(width: diameter, height: diameter)
            node.shader = BallTextures.sphereShader
            BallTextures.applyRotation(ball.orientation, to: node)
            node.zPosition = 1
            node.isHidden = ball.isPocketed
            ballLayer.addChild(node)
            ballNodes[ball.number] = node
        }
    }

    private func rackBalls(_ geo: TableGeometry) -> [Ball] {
        let r = geo.ballRadius
        let rows: [[Int]] = [
            [1],
            [11, 2],
            [3, 8, 10],
            [12, 4, 13, 5],
            [6, 14, 7, 15, 9],
        ]
        var result: [Ball] = [Ball(number: 0, position: geo.headSpot)]
        let apex = geo.footSpot
        let rowSpacing = r * 2 * 0.8660254 + 0.3
        for (rowIndex, row) in rows.enumerated() {
            let y = apex.y + CGFloat(rowIndex) * rowSpacing
            for (i, number) in row.enumerated() {
                let x = apex.x + (CGFloat(i) - CGFloat(row.count - 1) / 2) * (r * 2 + 0.3)
                result.append(Ball(number: number, position: CGPoint(x: x, y: y)))
            }
        }
        for ball in result { ball.randomizeOrientation() }
        return result
    }

    func shoot(power: CGFloat, spin: CGPoint = .zero) {
        guard let engine, let cue = cueBall, !cue.isPocketed,
              phase == .aiming || phase == .ballInHand else { return }
        let clamped = min(max(power, 0), 1)
        phase = .shooting
        draggingCue = false
        lastAimTouch = nil
        ballsBeforeShot = ballsOnTable
        shot = ShotRecord()

        let speed = engine.minShotSpeed + (engine.maxShotSpeed - engine.minShotSpeed) * clamped * clamped
        let direction = aimDirection
        let pullback = engine.geometry.ballRadius * (0.6 + clamped * 7)
        let follow = min(max(spin.y, -1), 1) / GameModel.maxSpinOffset
        let english = min(max(spin.x, -1), 1) / GameModel.maxSpinOffset

        let strike = SKAction.moveBy(x: direction.dx * pullback, y: direction.dy * pullback, duration: 0.09)
        strike.timingMode = .easeIn
        cueStick.run(.sequence([strike, .run { [weak self] in
            guard let self else { return }
            cue.velocity = CGVector(dx: direction.dx * speed, dy: direction.dy * speed)
            cue.spin = CGVector(dx: direction.dx * speed * follow * 1.1, dy: direction.dy * speed * follow * 1.1)
            cue.sideSpin = speed * english * 0.6
            self.cueStick.isHidden = true
            self.mediumHaptic.impactOccurred(intensity: 0.4 + 0.6 * clamped)
            self.phase = .ballsMoving
            self.model?.message = ""
        }]))
    }

    private func endShot() {
        guard let geo = geometry else { return }
        let result = rules.resolve(shot: shot, ballsBefore: ballsBeforeShot)

        if result.respotEight, let eight = balls.first(where: { $0.isEight }) {
            restore(eight, at: freeSpot(near: geo.footSpot, searchUp: true))
        }

        if let cue = cueBall, cue.isPocketed {
            restore(cue, at: freeSpot(near: geo.headSpot, searchUp: false))
        }

        if let winner = result.winner {
            phase = .gameOver(winner: winner)
        } else if result.ballInHand {
            phase = .ballInHand
        } else {
            phase = .aiming
        }
        model?.message = result.message
        aimDirection = defaultAimDirection()
        syncModel()
    }

    private func defaultAimDirection() -> CGVector {
        guard let cue = cueBall else { return CGVector(dx: 0, dy: 1) }
        // Aim at the nearest object ball (or the 8 when the shooter is on it).
        let group = rules.group(of: rules.currentPlayer)
        let onEight = rules.isOnEight(rules.currentPlayer, ballsOnTable: ballsOnTable)
        let targets = balls.filter { b in
            guard !b.isPocketed, !b.isCue else { return false }
            if onEight { return b.isEight }
            if let group { return b.group == group }
            return !b.isEight
        }
        guard let target = targets.min(by: { hypot($0.position.x - cue.position.x, $0.position.y - cue.position.y) < hypot($1.position.x - cue.position.x, $1.position.y - cue.position.y) }) else {
            return CGVector(dx: 0, dy: 1)
        }
        let dx = target.position.x - cue.position.x
        let dy = target.position.y - cue.position.y
        let len = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private func restore(_ ball: Ball, at position: CGPoint) {
        ball.isPocketed = false
        ball.velocity = .zero
        ball.position = position
        if let node = ballNodes[ball.number], let shadow = shadowNodes[ball.number] {
            node.removeAllActions()
            node.isHidden = false
            node.alpha = 0
            node.setScale(1)
            node.run(.fadeIn(withDuration: 0.25))
            shadow.isHidden = false
            shadow.alpha = 1
        }
    }

    private func freeSpot(near start: CGPoint, searchUp: Bool) -> CGPoint {
        guard let geo = geometry else { return start }
        let step = geo.ballRadius * 0.5 * (searchUp ? 1 : -1)
        var candidate = start
        for _ in 0..<400 {
            if isFree(candidate) { return geo.clampInside(candidate) }
            candidate.y += step
            if candidate.y > geo.felt.maxY - geo.ballRadius || candidate.y < geo.felt.minY + geo.ballRadius {
                candidate.y = start.y
                candidate.x += geo.ballRadius * 0.5
            }
        }
        return geo.clampInside(start)
    }

    private func isFree(_ p: CGPoint, ignoring ignored: Ball? = nil) -> Bool {
        guard let geo = geometry else { return true }
        let minDist = geo.ballRadius * 2 + 0.5
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
            let remaining: [Int]
            if let group {
                remaining = onTable.filter { groupOf($0) == group }.sorted()
            } else {
                remaining = []
            }
            return PlayerStatus(number: player, group: group, remaining: remaining)
        }
    }

    // MARK: - Frame update

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat = lastUpdate == 0 ? 1.0 / 60.0 : CGFloat(min(currentTime - lastUpdate, 1.0 / 30.0))
        lastUpdate = currentTime
        hapticCooldown = max(0, hapticCooldown - TimeInterval(dt))

        if phase == .ballsMoving, let engine {
            let events = engine.step(dt: dt, balls: balls, shot: &shot)
            for ball in balls where !ball.isPocketed && ball.isActive {
                ball.roll(dt: dt, radius: engine.geometry.ballRadius)
            }
            for ball in events.potted { animatePocket(ball) }
            if events.strongestCollision > engine.geometry.ballRadius * 4, hapticCooldown == 0 {
                let intensity = min(1, events.strongestCollision / engine.maxShotSpeed + 0.3)
                lightHaptic.impactOccurred(intensity: intensity)
                hapticCooldown = 0.05
            }
            if !balls.contains(where: { !$0.isPocketed && $0.isActive }) {
                endShot()
            }
        }

        syncNodes()
        updateOverlay()
    }

    private func animatePocket(_ ball: Ball) {
        mediumHaptic.impactOccurred(intensity: 0.8)
        guard let node = ballNodes[ball.number], let shadow = shadowNodes[ball.number] else { return }
        shadow.isHidden = true
        node.position = ball.position
        node.run(.sequence([
            .group([.scale(to: 0.55, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            .run { node.isHidden = true },
        ]))
    }

    private func syncNodes() {
        guard let geo = geometry else { return }
        for ball in balls where !ball.isPocketed {
            if let node = ballNodes[ball.number] {
                node.position = ball.position
                BallTextures.applyRotation(ball.orientation, to: node)
            }
            shadowNodes[ball.number]?.position = CGPoint(x: ball.position.x + geo.ballRadius * 0.18,
                                                         y: ball.position.y - geo.ballRadius * 0.28)
        }
    }

    private func updateOverlay() {
        guard let engine, let geo = geometry, let cue = cueBall, !cue.isPocketed,
              phase == .aiming || phase == .ballInHand || phase == .shooting else {
            aimLine.isHidden = true
            ghostBall.isHidden = true
            objectLine.isHidden = true
            deflectionLine.isHidden = true
            if phase != .shooting { cueStick.isHidden = true }
            return
        }
        let r = geo.ballRadius
        let prediction = engine.predict(from: cue.position, direction: aimDirection, balls: balls)

        let path = CGMutablePath()
        path.move(to: cue.position)
        path.addLine(to: prediction.cueEnd)
        aimLine.path = path
        aimLine.isHidden = false

        ghostBall.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        ghostBall.position = prediction.cueEnd
        ghostBall.isHidden = false

        if let hit = prediction.hitBall, let dir = prediction.objectDirection {
            let objPath = CGMutablePath()
            objPath.move(to: hit.position)
            objPath.addLine(to: CGPoint(x: hit.position.x + dir.dx * r * 7, y: hit.position.y + dir.dy * r * 7))
            objectLine.path = objPath
            objectLine.isHidden = false
            if let deflect = prediction.cueDeflection {
                let dPath = CGMutablePath()
                dPath.move(to: prediction.cueEnd)
                dPath.addLine(to: CGPoint(x: prediction.cueEnd.x + deflect.dx * r * 3.5,
                                          y: prediction.cueEnd.y + deflect.dy * r * 3.5))
                deflectionLine.path = dPath
                deflectionLine.isHidden = false
            } else {
                deflectionLine.isHidden = true
            }
        } else {
            objectLine.isHidden = true
            deflectionLine.isHidden = true
        }

        if phase != .shooting {
            let power = min(max(model?.power ?? 0, 0), 1)
            let gap = r * (1.6 + power * 7)
            let english = (model?.spin.x ?? 0) * r * 0.7
            let right = CGVector(dx: aimDirection.dy, dy: -aimDirection.dx)
            cueStick.isHidden = false
            cueStick.zRotation = atan2(-aimDirection.dy, -aimDirection.dx)
            cueStick.position = CGPoint(x: cue.position.x - aimDirection.dx * gap + right.dx * english,
                                        y: cue.position.y - aimDirection.dy * gap + right.dy * english)
        }
    }

    // MARK: - Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let geo = geometry, let cue = cueBall,
              phase == .aiming || phase == .ballInHand else { return }
        let p = touch.location(in: self)
        if phase == .ballInHand, hypot(p.x - cue.position.x, p.y - cue.position.y) < geo.ballRadius * 3.5 {
            draggingCue = true
            return
        }
        lastAimTouch = p
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, phase == .aiming || phase == .ballInHand else { return }
        let p = touch.location(in: self)
        if draggingCue {
            placeCue(at: p)
        } else if let last = lastAimTouch {
            rotateAim(from: last, to: p)
            lastAimTouch = p
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        draggingCue = false
        lastAimTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        draggingCue = false
        lastAimTouch = nil
    }

    /// Rotates the aim by the angle the finger sweeps around the cue ball, so touching down never
    /// snaps the cue. Close to the ball the sweep angle is ill-defined, so the drag is treated as a
    /// sideways swipe instead; the two blend so there is no discontinuity.
    private func rotateAim(from a: CGPoint, to b: CGPoint) {
        guard let cue = cueBall, let geo = geometry else { return }
        let r = geo.ballRadius
        let ax = a.x - cue.position.x, ay = a.y - cue.position.y
        let bx = b.x - cue.position.x, by = b.y - cue.position.y
        let distance = max(hypot(bx, by), 0.001)

        var sweep = atan2(by, bx) - atan2(ay, ax)
        if sweep > .pi { sweep -= 2 * .pi } else if sweep < -.pi { sweep += 2 * .pi }

        // Sideways swipe relative to the current aim: a full swipe across the table turns ~90°.
        let right = CGVector(dx: aimDirection.dy, dy: -aimDirection.dx)
        let lateral = (b.x - a.x) * right.dx + (b.y - a.y) * right.dy
        let swipe = -lateral / geo.felt.width * (.pi / 2)

        let near = r * 3, far = r * 9
        let blend = min(max((distance - near) / (far - near), 0), 1)
        let delta = sweep * blend + swipe * (1 - blend)

        let current = atan2(aimDirection.dy, aimDirection.dx) + delta
        aimDirection = CGVector(dx: cos(current), dy: sin(current))
    }

    private func placeCue(at p: CGPoint) {
        guard let cue = cueBall, let geo = geometry else { return }
        let target = geo.clampInside(p)
        if isFree(target, ignoring: cue) {
            cue.position = target
        }
    }
}
