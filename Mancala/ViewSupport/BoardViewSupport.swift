import SwiftUI

struct FlyingStone: Equatable {
    var position: CGPoint
    let colorIndex: Int
}

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

extension View {
    func recordCellFrame(id: Int) -> some View {
        anchorPreference(key: CellFramePreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }

    func playerFacingRotation(_ degrees: Double) -> some View {
        rotationEffect(.degrees(degrees))
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: degrees)
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
