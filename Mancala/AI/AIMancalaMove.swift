import FoundationModels

@Generable
struct AIMancalaMove {
    @Guide(description: "One legal Player 2 pit index from the provided legal pit list", .range(7...12))
    var pitIndex: Int
}
