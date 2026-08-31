import SwiftUI
import SpriteKit

struct GameView: View {
    @State private var scene: SKScene = {
        // Debug hooks (NS_KIT / autofire testing) jump straight into a match.
        let env = ProcessInfo.processInfo.environment
        let skipMenu = env["NS_KIT"] != nil || env["NS_AUTOFIRE"] != nil || env["NS_AUTOWALK"] != nil
        let scene: SKScene = skipMenu ? GameScene() : MenuScene()
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60)
            .ignoresSafeArea()
            .persistentSystemOverlays(.hidden)
    }
}
