#if os(visionOS)
import RealityKit
import SwiftUI
import simd

/// Shared bridge between the main window (game logic, chrome) and the board
/// volume. Owned by the app so both scenes see the same `BoardScene`;
/// `ContentView` pushes game state in and receives pit taps.
@Observable
@MainActor
final class SpatialBoardModel {
    static let windowID = "SpatialBoard"

    let scene = BoardScene()

    /// True while the board volume is open; the main window swaps its board
    /// for a placeholder and routes stone animations to `scene`.
    var isOpen = false
}

/// Equatable snapshot of everything the spatial board mirrors, so
/// `ContentView` can sync the scene from a single `onChange`.
struct SpatialBoardSyncState: Equatable {
    var pits: [Int]
    var playable: Set<Int>
    var hinted: Int?
    var currentStore: Int?
    var showLabels: Bool
    var dark: Bool
    var material: BoardMaterialStyle
}

/// Volumetric-window content: the life-size board resting on the volume's
/// floor. The system handle under the volume moves it anywhere in the room —
/// including vertically — and snaps it onto real surfaces. Pits play by
/// reaching out and touching them or by gaze + pinch.
struct SpatialBoardView: View {
    let model: SpatialBoardModel

    /// Carries the board so it can be seated on the volume's floor; the
    /// scene root itself keeps the board origin at the slab's top face.
    @State private var boardHolder = Entity()

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let sceneRoot = await model.scene.buildRoot()
                boardHolder.addChild(sceneRoot)
                content.add(boardHolder)
                seatBoard(content: content, proxy: proxy)
            } update: { content in
                seatBoard(content: content, proxy: proxy)
            }
            .gesture(pitTapGesture)
            .gesture(pitTouchGesture)
        }
        .onAppear { model.isOpen = true }
        .onDisappear { model.isOpen = false }
    }

    /// Rest the slab's underside on the bottom of the volume, so the board
    /// sits on the baseplate and on whatever surface the volume snaps to.
    private func seatBoard(content: RealityViewContent, proxy: GeometryProxy3D) {
        let bounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
        boardHolder.position = SIMD3(0, bounds.min.y + BoardLayout3D.thickness, 0)
    }

    /// Gaze + pinch (and system-recognized pokes).
    private var pitTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                playPit(startingAt: value.entity)
            }
    }

    /// Direct touch: a fingertip pressed onto a pit ends as a touch-kind
    /// spatial event rather than always registering as a tap, so treat a
    /// completed touch on a pit as a play. When the system also recognizes
    /// the poke as a tap, `animateMove`'s in-progress guard drops the
    /// duplicate.
    private var pitTouchGesture: some Gesture {
        SpatialEventGesture()
            .onEnded { events in
                for event in events where event.kind == .touch && event.phase == .ended {
                    if let entity = event.targetedEntity {
                        playPit(startingAt: entity)
                    }
                }
            }
    }

    private func playPit(startingAt entity: Entity) {
        var current: Entity? = entity
        while let entity = current {
            if let pit = entity.components[PitIndexComponent.self]?.index {
                model.scene.onPitTapped?(pit)
                return
            }
            current = entity.parent
        }
    }
}
#endif
