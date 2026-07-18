#if !os(visionOS)
import RealityKit
import SwiftUI

/// SwiftUI host for the 3D board. Renders the RealityKit scene, forwards
/// observed game state into `BoardScene`, and routes entity taps back to the
/// game flow. Count labels are 3D text meshes managed by `BoardScene`
/// (RealityView attachments are not available on iOS).
struct Board3DView: View {
    let pits: [Int]
    let playablePits: Set<Int>
    let hintedPit: Int?
    let currentStoreIndex: Int?
    let flipped: Bool
    let isPortrait: Bool
    let showLabels: Bool
    let isDarkMode: Bool
    let boardMaterial: BoardMaterialStyle
    let scene: BoardScene

    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.camera = .virtual
                let sceneRoot = await scene.buildRoot()
                content.add(sceneRoot)
                syncScene(viewSize: geometry.size)
            } update: { _ in
                syncScene(viewSize: geometry.size)
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        var entity: Entity? = value.entity
                        while let current = entity {
                            if let pit = current.components[PitIndexComponent.self]?.index {
                                scene.onPitTapped?(pit)
                                return
                            }
                            entity = current.parent
                        }
                    }
            )
        }
        .accessibilityLabel("Mancala board")
    }

    private func syncScene(viewSize: CGSize) {
        scene.sync(
            pits: pits,
            playable: playablePits,
            hinted: hintedPit,
            currentStore: currentStoreIndex,
            flipped: flipped,
            portrait: isPortrait,
            viewSize: viewSize,
            showLabels: showLabels,
            dark: isDarkMode,
            material: boardMaterial
        )
    }
}
#endif
