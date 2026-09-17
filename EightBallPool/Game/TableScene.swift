import SceneKit
import simd
import UIKit

/// SceneKit content: table, balls, cue, aim guide, lights and camera. World units are ball radii
/// (1 unit = 28.575 mm); the table plane is y = 0 with the physics x axis → x and the physics y axis
/// (up the table) → −z.
final class TableScene {
    let scene = SCNScene()
    let geometry: TableGeometry
    let cameraNode = SCNNode()
    let cueNode = SCNNode()
    private(set) var ballNodes: [Int: SCNNode] = [:]

    private let ballRoot = SCNNode()
    private let aimLine = SCNNode()
    private let objectLine = SCNNode()
    private let deflectionLine = SCNNode()
    private let ghostBall = SCNNode()

    /// Physics-frame (x, y, z-up) → scene-frame (x, y-up, −z) rotation.
    static let toScene = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

    /// Height of the lamps above the cloth (ball radii); the overhead camera sits below them.
    static let lampHeight: CGFloat = 92

    static let feltColor = UIColor(red: 0.09, green: 0.47, blue: 0.24, alpha: 1)
    static let cushionColor = UIColor(red: 0.06, green: 0.36, blue: 0.18, alpha: 1)
    static let woodColor = UIColor(red: 0.33, green: 0.18, blue: 0.09, alpha: 1)
    static let darkWood = UIColor(red: 0.20, green: 0.11, blue: 0.06, alpha: 1)

    /// Nose-to-rail-wood depth of the rubber and the rail wood beyond it.
    static let cushionDepth: CGFloat = 1.8
    static let railWidth: CGFloat = 4.2
    static let cushionHeight: CGFloat = 1.45

    init(geometry: TableGeometry) {
        self.geometry = geometry
        scene.background.contents = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        buildTable()
        buildLights()
        buildCue()
        buildGuide()
        scene.rootNode.addChildNode(ballRoot)

        let camera = SCNCamera()
        camera.fieldOfView = 66
        camera.projectionDirection = .vertical
        camera.zNear = 0.3
        camera.zFar = 600
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Coordinates

    static func scenePoint(_ p: CGPoint, height: CGFloat) -> SCNVector3 {
        SCNVector3(Float(p.x), Float(height), Float(-p.y))
    }

    static func tablePoint(_ v: SCNVector3) -> CGPoint {
        CGPoint(x: CGFloat(v.x), y: CGFloat(-v.z))
    }

    static func sceneVector(_ v: CGVector) -> simd_float3 {
        simd_float3(Float(v.dx), 0, Float(-v.dy))
    }

    // MARK: - Table

    private func buildTable() {
        let felt = geometry.felt
        let r = geometry.ballRadius
        let depth = Self.cushionDepth
        let rail = Self.railWidth
        let h = Self.cushionHeight

        // Cloth, running under the cushions and rails so pocket mouths show cloth.
        let clothRect = felt.insetBy(dx: -(depth + rail), dy: -(depth + rail))
        let cloth = SCNBox(width: clothRect.width, height: 0.4, length: clothRect.height, chamferRadius: 0)
        cloth.firstMaterial = material(Self.feltColor, roughness: 0.95)
        let clothNode = SCNNode(geometry: cloth)
        clothNode.position = SCNVector3(Float(clothRect.midX), -0.2, Float(-clothRect.midY))
        scene.rootNode.addChildNode(clothNode)

        // Pockets: dark wells sunk into the cloth.
        for p in geometry.pockets {
            let well = SCNCylinder(radius: p.radius * 0.95, height: 6)
            well.firstMaterial = material(UIColor(white: 0.02, alpha: 1), roughness: 1)
            well.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: well)
            node.position = Self.scenePoint(p.center, height: -2.99)
            scene.rootNode.addChildNode(node)
            let rim = SCNTorus(ringRadius: p.radius * 0.95, pipeRadius: 0.12)
            rim.firstMaterial = material(UIColor(white: 0.12, alpha: 1), roughness: 0.6)
            let rimNode = SCNNode(geometry: rim)
            rimNode.position = Self.scenePoint(p.center, height: 0.02)
            scene.rootNode.addChildNode(rimNode)
        }

        // Cushions: the physics cushion faces extruded up to the nose height, filled back to the rail wood.
        for piece in geometry.cushions {
            let out = piece.outward
            func beyondFelt(_ p: CGPoint) -> CGFloat {
                (p.x - felt.midX) * out.dx + (p.y - felt.midY) * out.dy - (out.dx != 0 ? felt.width : felt.height) / 2
            }
            let path = UIBezierPath()
            path.move(to: piece.face[0])
            for p in piece.face.dropFirst() { path.addLine(to: p) }
            for p in piece.face.reversed() {
                let push = depth + 0.2 - beyondFelt(p)
                path.addLine(to: CGPoint(x: p.x + out.dx * push, y: p.y + out.dy * push))
            }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: h)
            shape.chamferRadius = 0.25
            shape.chamferMode = .front
            shape.firstMaterial = material(Self.cushionColor, roughness: 0.9)
            let node = SCNNode(geometry: shape)
            node.simdOrientation = Self.toScene
            node.position = SCNVector3(0, Float(h / 2), 0)
            scene.rootNode.addChildNode(node)
        }

        // Rail wood: four planks around the cushions, with the pocket openings bitten out of them.
        let inner = felt.insetBy(dx: -depth, dy: -depth)
        let outer = inner.insetBy(dx: -rail, dy: -rail)
        let planks = [
            CGRect(x: outer.minX, y: inner.maxY, width: outer.width, height: rail),
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: rail),
            CGRect(x: outer.minX, y: inner.minY, width: rail, height: inner.height),
            CGRect(x: inner.maxX, y: inner.minY, width: rail, height: inner.height),
        ]
        let woodMaterial = material(Self.woodColor, roughness: 0.45)
        for plank in planks {
            let railShape = SCNShape(path: plankPath(plank), extrusionDepth: h + 0.6)
            railShape.chamferRadius = 0.25
            railShape.chamferMode = .front
            railShape.firstMaterial = woodMaterial
            let railNode = SCNNode(geometry: railShape)
            railNode.simdOrientation = Self.toScene
            railNode.position = SCNVector3(0, Float((h + 0.6) / 2 - 0.6), 0)
            scene.rootNode.addChildNode(railNode)
        }

        // Diamonds on the rails.
        let diamondMaterial = material(UIColor(red: 0.93, green: 0.88, blue: 0.75, alpha: 1), roughness: 0.3)
        let diamondOffset = depth + rail * 0.55
        func addDiamond(_ p: CGPoint) {
            let d = SCNBox(width: 0.55, height: 0.05, length: 0.55, chamferRadius: 0)
            d.firstMaterial = diamondMaterial
            let n = SCNNode(geometry: d)
            n.position = Self.scenePoint(p, height: h + 0.02)
            n.eulerAngles.y = .pi / 4
            scene.rootNode.addChildNode(n)
        }
        for i in 1...3 {
            let y1 = felt.minY + felt.height * CGFloat(i) / 8
            let y2 = felt.maxY - felt.height * CGFloat(i) / 8
            for y in [y1, y2] {
                addDiamond(CGPoint(x: felt.minX - diamondOffset, y: y))
                addDiamond(CGPoint(x: felt.maxX + diamondOffset, y: y))
            }
            let x = felt.minX + felt.width * CGFloat(i) / 4
            addDiamond(CGPoint(x: x, y: felt.minY - diamondOffset))
            addDiamond(CGPoint(x: x, y: felt.maxY + diamondOffset))
        }

        // Spots and head string on the cloth.
        let spot = SCNCylinder(radius: r * 0.2, height: 0.02)
        spot.firstMaterial = material(UIColor(white: 1, alpha: 0.5), roughness: 1)
        let spotNode = SCNNode(geometry: spot)
        spotNode.position = Self.scenePoint(geometry.footSpot, height: 0.01)
        scene.rootNode.addChildNode(spotNode)
        let headString = SCNBox(width: felt.width, height: 0.015, length: 0.08, chamferRadius: 0)
        headString.firstMaterial = material(UIColor(white: 1, alpha: 0.18), roughness: 1)
        let headNode = SCNNode(geometry: headString)
        headNode.position = Self.scenePoint(CGPoint(x: felt.midX, y: geometry.headSpot.y), height: 0.01)
        scene.rootNode.addChildNode(headNode)

        // Body, legs and floor.
        let bodyHeight: CGFloat = 5
        let body = SCNBox(width: outer.width - 1, height: bodyHeight, length: outer.height - 1, chamferRadius: 0.2)
        body.firstMaterial = material(Self.darkWood, roughness: 0.6)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(Float(outer.midX), Float(-bodyHeight / 2 - 0.3), Float(-outer.midY))
        scene.rootNode.addChildNode(bodyNode)

        let tableHeight: CGFloat = 27 // ~0.77 m
        for (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            let leg = SCNBox(width: 4, height: tableHeight - bodyHeight, length: 4, chamferRadius: 0.3)
            leg.firstMaterial = material(Self.darkWood, roughness: 0.6)
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(Float(outer.midX) + Float(sx) * Float(outer.width / 2 - 4),
                                          Float(-bodyHeight - (tableHeight - bodyHeight) / 2),
                                          Float(-(outer.midY + CGFloat(sy) * (outer.height / 2 - 5))))
            scene.rootNode.addChildNode(legNode)
        }

        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial = material(UIColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1), roughness: 1)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, Float(-tableHeight), 0)
        scene.rootNode.addChildNode(floorNode)

        // A dim room around the table so the view above the far rail isn't a void.
        let room = SCNBox(width: 260, height: 132, length: 320, chamferRadius: 0)
        let wall = SCNMaterial()
        wall.lightingModel = .physicallyBased
        wall.diffuse.contents = UIColor(red: 0.30, green: 0.22, blue: 0.18, alpha: 1)
        wall.roughness.contents = 1.0
        wall.cullMode = .front
        room.firstMaterial = wall
        let roomNode = SCNNode(geometry: room)
        roomNode.position = SCNVector3(0, Float(-tableHeight + 66), 0)
        roomNode.castsShadow = false
        scene.rootNode.addChildNode(roomNode)

        // The lamp shade over the table.
        let shade = SCNCone(topRadius: 3, bottomRadius: 9, height: 4)
        shade.firstMaterial = material(UIColor(red: 0.12, green: 0.32, blue: 0.22, alpha: 1), roughness: 0.4)
        shade.firstMaterial?.isDoubleSided = true
        for y in [felt.minY + felt.height * 0.3, felt.minY + felt.height * 0.7] {
            let node = SCNNode(geometry: shade)
            node.position = Self.scenePoint(CGPoint(x: felt.midX, y: y), height: Self.lampHeight + 2)
            node.castsShadow = false
            scene.rootNode.addChildNode(node)
            let cord = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 12))
            cord.geometry?.firstMaterial = material(.black, roughness: 1)
            cord.position = Self.scenePoint(CGPoint(x: felt.midX, y: y), height: Self.lampHeight + 10)
            scene.rootNode.addChildNode(cord)
        }
    }

    /// Outline of a rail plank with the pocket openings cut out: the rectangle is sampled densely and
    /// any vertex inside a pocket circle is pushed radially onto the circle, which traces the pocket arc.
    private func plankPath(_ rect: CGRect) -> UIBezierPath {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        let path = UIBezierPath()
        var first = true
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let steps = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 0.08))
            for s in 0..<steps {
                let t = CGFloat(s) / CGFloat(steps)
                var p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                for pocket in geometry.pockets {
                    let d = hypot(p.x - pocket.center.x, p.y - pocket.center.y)
                    if d < pocket.radius {
                        let k = d > 1e-6 ? pocket.radius / d : 1
                        p = CGPoint(x: pocket.center.x + (p.x - pocket.center.x) * k,
                                    y: pocket.center.y + (p.y - pocket.center.y) * k)
                    }
                }
                if first { path.move(to: p); first = false } else { path.addLine(to: p) }
            }
        }
        path.close()
        return path
    }

    private func material(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0
        return m
    }

    // MARK: - Lights

    private func buildLights() {
        let felt = geometry.felt
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 450
        ambient.color = UIColor(white: 0.9, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Two overhead lamps along the table, like a pool-hall fixture; one casts the shadows.
        for (i, y) in [felt.minY + felt.height * 0.3, felt.minY + felt.height * 0.7].enumerated() {
            let spot = SCNLight()
            spot.type = .spot
            spot.intensity = 2600
            spot.spotInnerAngle = 40
            spot.spotOuterAngle = 95
            spot.color = UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)
            spot.castsShadow = i == 0
            spot.shadowMode = .forward
            spot.shadowSampleCount = 8
            spot.shadowRadius = 3
            spot.shadowColor = UIColor(white: 0, alpha: 0.6)
            spot.shadowMapSize = CGSize(width: 2048, height: 2048)
            spot.zNear = 5
            spot.zFar = 120
            let node = SCNNode()
            node.light = spot
            node.position = Self.scenePoint(CGPoint(x: felt.midX, y: y), height: Self.lampHeight)
            node.look(at: Self.scenePoint(CGPoint(x: felt.midX, y: y), height: 0))
            scene.rootNode.addChildNode(node)
        }
    }

    // MARK: - Balls

    func setBalls(_ balls: [Ball]) {
        ballRoot.childNodes.forEach { $0.removeFromParentNode() }
        ballNodes.removeAll()
        let r = geometry.ballRadius
        for ball in balls {
            let sphere = SCNSphere(radius: r)
            sphere.segmentCount = 48
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = BallTextures.sphereMap(number: ball.number)
            m.roughness.contents = 0.18
            m.metalness.contents = 0
            sphere.firstMaterial = m
            let node = SCNNode(geometry: sphere)
            node.isHidden = ball.isPocketed
            ballRoot.addChildNode(node)
            ballNodes[ball.number] = node
        }
        sync(balls)
    }

    func sync(_ balls: [Ball]) {
        let r = geometry.ballRadius
        for ball in balls where !ball.isPocketed {
            guard let node = ballNodes[ball.number] else { continue }
            node.position = Self.scenePoint(ball.position, height: r)
            node.simdOrientation = Self.toScene * ball.orientation * Self.toScene.inverse
        }
    }

    func dropBall(_ ball: Ball) {
        guard let node = ballNodes[ball.number] else { return }
        node.position = Self.scenePoint(ball.position, height: geometry.ballRadius)
        node.runAction(.sequence([
            .move(by: SCNVector3(0, -3.5, 0), duration: 0.3),
            .run { $0.isHidden = true },
        ]))
    }

    func restoreBall(_ ball: Ball) {
        guard let node = ballNodes[ball.number] else { return }
        node.removeAllActions()
        node.opacity = 0
        node.isHidden = false
        node.position = Self.scenePoint(ball.position, height: geometry.ballRadius)
        node.runAction(.fadeIn(duration: 0.25))
    }

    // MARK: - Cue

    /// The cue points down its local −z axis with the tip at the origin, so placing it means putting
    /// the origin at the strike point and looking along the aim.
    private func buildCue() {
        let length: CGFloat = 50   // ~1.45 m
        let tipRadius: CGFloat = 0.23, buttRadius: CGFloat = 0.52
        let shaft = SCNCone(topRadius: tipRadius, bottomRadius: (tipRadius + buttRadius) / 2, height: length * 0.5)
        shaft.firstMaterial = material(UIColor(red: 0.88, green: 0.74, blue: 0.50, alpha: 1), roughness: 0.4)
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position = SCNVector3(0, 0, Float(0.6 + length * 0.25))
        shaftNode.eulerAngles.x = -.pi / 2
        cueNode.addChildNode(shaftNode)

        let butt = SCNCone(topRadius: (tipRadius + buttRadius) / 2, bottomRadius: buttRadius, height: length * 0.5)
        butt.firstMaterial = material(UIColor(red: 0.20, green: 0.09, blue: 0.05, alpha: 1), roughness: 0.35)
        let buttNode = SCNNode(geometry: butt)
        buttNode.position = SCNVector3(0, 0, Float(0.6 + length * 0.75))
        buttNode.eulerAngles.x = -.pi / 2
        cueNode.addChildNode(buttNode)

        let ferrule = SCNCylinder(radius: tipRadius, height: 0.45)
        ferrule.firstMaterial = material(UIColor(white: 0.95, alpha: 1), roughness: 0.3)
        let ferruleNode = SCNNode(geometry: ferrule)
        ferruleNode.position = SCNVector3(0, 0, 0.375)
        ferruleNode.eulerAngles.x = -.pi / 2
        cueNode.addChildNode(ferruleNode)

        let tip = SCNCylinder(radius: tipRadius, height: 0.15)
        tip.firstMaterial = material(UIColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1), roughness: 0.9)
        let tipNode = SCNNode(geometry: tip)
        tipNode.position = SCNVector3(0, 0, 0.075)
        tipNode.eulerAngles.x = -.pi / 2
        cueNode.addChildNode(tipNode)

        cueNode.isHidden = true
        scene.rootNode.addChildNode(cueNode)
    }

    /// Places the cue behind the ball: `gap` from the ball surface along −aim, offset sideways by the
    /// english and vertically by follow/draw, pitched up slightly so the butt clears the rail.
    func placeCue(cueBall: CGPoint, aim: CGVector, gap: CGFloat, tipOffset: CGPoint) {
        let r = geometry.ballRadius
        let forward = Self.sceneVector(aim)
        let right = simd_float3(-forward.z, 0, forward.x)
        let elevation: Float = 4 * .pi / 180
        let dir = simd_normalize(forward * cos(elevation) + simd_float3(0, sin(elevation), 0) * -1)
        let centre = simd_float3(Float(cueBall.x), Float(r), Float(-cueBall.y))
        let strike = centre + right * Float(tipOffset.x * r) + simd_float3(0, Float(tipOffset.y * r), 0)
        let origin = strike - forward * Float(r + gap)
        cueNode.simdPosition = origin
        cueNode.simdLook(at: origin - dir, up: simd_float3(0, 1, 0), localFront: simd_float3(0, 0, 1))
        cueNode.isHidden = false
    }

    func hideCue() { cueNode.isHidden = true }

    func strokeCue(along aim: CGVector, distance: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        let v = Self.sceneVector(aim) * Float(distance)
        let move = SCNAction.move(by: SCNVector3(v.x, v.y, v.z), duration: duration)
        move.timingMode = .easeIn
        cueNode.runAction(.sequence([move, .run { _ in DispatchQueue.main.async(execute: completion) }]))
    }

    // MARK: - Aim guide

    private func buildGuide() {
        for (node, alpha) in [(aimLine, 0.8), (objectLine, 0.6), (deflectionLine, 0.4)] {
            let cyl = SCNCylinder(radius: 0.07, height: 1)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = UIColor(white: 1, alpha: alpha)
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = false
            cyl.firstMaterial = m
            node.geometry = cyl
            node.isHidden = true
            scene.rootNode.addChildNode(node)
        }
        let sphere = SCNSphere(radius: geometry.ballRadius)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(white: 1, alpha: 0.28)
        m.isDoubleSided = true
        sphere.firstMaterial = m
        ghostBall.geometry = sphere
        ghostBall.isHidden = true
        scene.rootNode.addChildNode(ghostBall)
    }

    private func setLine(_ node: SCNNode, from a: CGPoint, to b: CGPoint) {
        let pa = simd_float3(Float(a.x), 0.08, Float(-a.y))
        let pb = simd_float3(Float(b.x), 0.08, Float(-b.y))
        let d = pb - pa
        let len = simd_length(d)
        guard len > 0.01, let cyl = node.geometry as? SCNCylinder else { node.isHidden = true; return }
        cyl.height = CGFloat(len)
        node.simdPosition = (pa + pb) / 2
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: d / len)
        node.isHidden = false
    }

    func showGuide(from cue: CGPoint, prediction: PhysicsEngine.AimPrediction) {
        let r = geometry.ballRadius
        setLine(aimLine, from: cue, to: prediction.cueEnd)
        ghostBall.position = Self.scenePoint(prediction.cueEnd, height: r)
        ghostBall.isHidden = false
        if let hit = prediction.hitBall, let dir = prediction.objectDirection {
            setLine(objectLine, from: hit.position,
                    to: CGPoint(x: hit.position.x + dir.dx * r * 7, y: hit.position.y + dir.dy * r * 7))
            if let deflect = prediction.cueDeflection {
                setLine(deflectionLine, from: prediction.cueEnd,
                        to: CGPoint(x: prediction.cueEnd.x + deflect.dx * r * 3.5, y: prediction.cueEnd.y + deflect.dy * r * 3.5))
            } else {
                deflectionLine.isHidden = true
            }
        } else {
            objectLine.isHidden = true
            deflectionLine.isHidden = true
        }
    }

    func hideGuide() {
        aimLine.isHidden = true
        objectLine.isHidden = true
        deflectionLine.isHidden = true
        ghostBall.isHidden = true
    }
}
