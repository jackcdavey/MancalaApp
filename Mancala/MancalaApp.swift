import SwiftUI

/// App-wide branding.
enum AppInfo {
    /// The user-facing app name, shown in-app wherever the app refers to
    /// itself. The home-screen/app-switcher name is set separately via
    /// `INFOPLIST_KEY_CFBundleDisplayName` in the build settings — keep the
    /// two in sync when renaming.
    static let name = "Mancoola"
}

#if os(visionOS)
/// Resize limits for the main window, in points. Unlike iPad, a visionOS
/// window can be dragged to any proportions at all, and the game's layout only
/// stays honest across a range: below the minimum the board, score strip, and
/// status panel start fighting over the same vertical space, and above the
/// maximum the fixed-width content column just floats in empty glass. The
/// resting size opens the window in the portrait shape the layout is designed
/// around.
private enum MainWindowSize {
    static let restingWidth: CGFloat = 760
    static let restingHeight: CGFloat = 1000
    static let minWidth: CGFloat = 620
    static let minHeight: CGFloat = 700
    static let maxWidth: CGFloat = 1400
    static let maxHeight: CGFloat = 1500
}
#endif

@main struct MancalaApp: App {
    #if os(visionOS)
    @State private var spatialBoard = SpatialBoardModel()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(visionOS)
                .environment(spatialBoard)
                .frame(
                    minWidth: MainWindowSize.minWidth,
                    idealWidth: MainWindowSize.restingWidth,
                    maxWidth: MainWindowSize.maxWidth,
                    minHeight: MainWindowSize.minHeight,
                    idealHeight: MainWindowSize.restingHeight,
                    maxHeight: MainWindowSize.maxHeight
                )
                #endif
        }
        #if os(visionOS)
        .defaultSize(width: MainWindowSize.restingWidth, height: MainWindowSize.restingHeight)
        .windowResizability(.contentSize)
        #endif

        #if os(visionOS)
        // The board lives in its own volume: the system handle beneath it
        // moves it anywhere in the room (including vertically) and snaps it
        // onto real surfaces like a tabletop. Resizing the volume resizes the
        // board with it — `SpatialBoardView` fits the board to the bounds and
        // carries the limits that bound the resize.
        WindowGroup(id: SpatialBoardModel.windowID) {
            SpatialBoardView(model: spatialBoard)
        }
        .windowStyle(.volumetric)
        .defaultSize(
            width: Double(SpatialBoardModel.VolumeSize.resting.x),
            height: Double(SpatialBoardModel.VolumeSize.resting.y),
            depth: Double(SpatialBoardModel.VolumeSize.resting.z),
            in: .meters
        )
        .windowResizability(.contentSize)
        #endif
    }
}
