enum FoundationModelAIMoveProvider {
    static var isAvailable: Bool {
        false
    }

    static var availabilityMessage: String? {
        "AI play uses local heuristics on this OS version."
    }

    static func choosePit(prompt: String) async throws -> Int {
        throw FoundationModelAIMoveError.unavailable
    }
}

enum FoundationModelAIMoveError: Error {
    case unavailable
}
