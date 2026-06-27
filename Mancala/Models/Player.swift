enum Player: String, Equatable {
    case playerOne
    case playerTwo

    var name: String {
        switch self {
        case .playerOne: "Player 1"
        case .playerTwo: "Player 2"
        }
    }

    var shortName: String {
        switch self {
        case .playerOne: "P1"
        case .playerTwo: "P2"
        }
    }

    var opponent: Player {
        switch self {
        case .playerOne: .playerTwo
        case .playerTwo: .playerOne
        }
    }
}
