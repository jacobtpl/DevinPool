import SceneKit
import SwiftUI

/// Hosts the SceneKit view and forwards raw touches to the controller.
struct GameSceneView: UIViewRepresentable {
    let controller: GameController

    func makeUIView(context: Context) -> TouchSCNView {
        let view = TouchSCNView(frame: .zero)
        view.scene = controller.table.scene
        view.pointOfView = controller.table.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.isJitteringEnabled = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.controller = controller
        controller.view = view
        controller.start()
        return view
    }

    func updateUIView(_ uiView: TouchSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: TouchSCNView, coordinator: ()) {
        uiView.controller?.stop()
    }
}

final class TouchSCNView: SCNView {
    weak var controller: GameController?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        controller?.touchBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        controller?.touchMoved(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touchEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        controller?.touchEnded()
    }
}
