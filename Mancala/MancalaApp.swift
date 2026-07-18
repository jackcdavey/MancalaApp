import SwiftUI

@main struct MancalaApp: App {
    #if os(visionOS)
    @State private var spatialBoard = SpatialBoardModel()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(visionOS)
                .environment(spatialBoard)
                #endif
        }

        #if os(visionOS)
        // The board lives in its own volume: the system handle beneath it
        // moves it anywhere in the room (including vertically) and snaps it
        // onto real surfaces like a tabletop.
        WindowGroup(id: SpatialBoardModel.windowID) {
            SpatialBoardView(model: spatialBoard)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.85, height: 0.4, depth: 0.5, in: .meters)
        #endif
    }
}
