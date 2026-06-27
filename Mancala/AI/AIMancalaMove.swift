import FoundationModels

@Generable
struct AIMancalaMove {
    @Guide(description: "One legal pit index from the provided legal pit list", .range(0...12))
    var pitIndex: Int
}
