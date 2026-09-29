import Foundation

/// One Pokémon read from a summary screenshot, with IVs filled in from its appraisal screenshot
/// when one was taken, or from the CP/HP/dust solver otherwise.
struct ScannedPokemon: Codable, Identifiable, Hashable {
    var id = UUID()
    var scannedAt: Date
    var assetIdentifier: String
    var appraisalAssetIdentifier: String?

    var nameOnScreen: String
    var speciesKey: String?
    var speciesCandidates: [String] = []   // when the name was a nickname and typing+moves left several options
    var gender: String?
    var cp: Int
    var hp: Int?
    var hpMax: Int?
    var dust: Int?
    var candy: Int?
    var evolveCandy: Int?
    var candyOnHand: Int?
    var candyXL: Int?
    var megaEnergy: Int?
    var caughtDate: String?
    var fastMove: String?
    var chargedMoves: [String] = []
    var types: [String] = []
    var weightKg: Double?
    var heightM: Double?

    var atk: Int?
    var def: Int?
    var sta: Int?
    var ivExact: Bool = false
    var candidates: [Formula.Candidate] = []

    var lucky = false
    var shadow = false
    var purified = false
    var favorite = false
    var notes: [String] = []

    var species: Species? { speciesKey.flatMap { GameDB.shared.species(key: $0) } }
    var displayName: String {
        if let s = species {
            let nick = GameDB.norm(nameOnScreen) == GameDB.norm(s.name) ? "" : " \u{201C}\(nameOnScreen)\u{201D}"
            return s.displayName + nick
        }
        return nameOnScreen
    }
    var ivPercent: Double? {
        guard let a = atk, let d = def, let s = sta else { return nil }
        return Double(a + d + s) / 45 * 100
    }
    var levelText: String {
        let levels = Set(candidates.map(\.level)).sorted()
        guard let lo = levels.first, let hi = levels.last else { return "?" }
        return lo == hi ? trim(lo) : "\(trim(lo))-\(trim(hi))"
    }
    var ivText: String {
        guard let a = atk, let d = def, let s = sta else { return "?" }
        return "\(a)/\(d)/\(s)" + (ivExact ? "" : "~")
    }

    private func trim(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(x) }

    /// Pick IVs from the solver's candidates: exact when only one combination fits, otherwise
    /// the median candidate with ivExact false so the CSV and the Mac side both know.
    mutating func adoptCandidates(_ found: [Formula.Candidate]) {
        candidates = found
        let ivSets = Set(found.map { [$0.atk, $0.def, $0.sta] })
        if ivSets.count == 1, let only = found.first {
            atk = only.atk; def = only.def; sta = only.sta; ivExact = true
        } else if !found.isEmpty {
            let sorted = found.sorted { $0.percent < $1.percent }
            let mid = sorted[sorted.count / 2]
            atk = mid.atk; def = mid.def; sta = mid.sta; ivExact = false
        }
    }

    /// Exact IVs from the appraisal bars narrow the level too.
    mutating func adoptAppraisal(atk a: Int, def d: Int, sta s: Int, asset: String) {
        atk = a; def = d; sta = s; ivExact = true
        appraisalAssetIdentifier = asset
        let narrowed = candidates.filter { $0.atk == a && $0.def == d && $0.sta == s }
        if !narrowed.isEmpty { candidates = narrowed }
    }
}
