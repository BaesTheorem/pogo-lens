import Foundation

/// A species or form row from pogoapi's stats tables, bundled as gamedata.json.
struct Species: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let form: String
    let atk: Int
    let def: Int
    let sta: Int
    let types: [String]

    var key: String { "\(id)-\(form)" }
    var isBaseForm: Bool { form == "Normal" || form.isEmpty }
    var displayName: String { isBaseForm ? name : "\(name) (\(form))" }
}

struct CPMEntry: Codable {
    let level: Double
    let multiplier: Double
}

struct Moveset: Codable {
    let fast: [String]
    let charged: [String]
}

struct GameData: Codable {
    let species: [Species]
    let cpm: [CPMEntry]
    let dust: [Int]
    let dust_levels: [String: [Double]]
    let fast_moves: [String]
    let charged_moves: [String]
    let movesets: [String: Moveset]
    let types: [String]
}

/// gamedata.json with the lookups the scanner needs, built once at launch.
final class GameDB {
    static let shared = GameDB()

    let data: GameData
    private let cpmByLevel: [Double: Double]
    private let speciesByName: [String: [Species]]
    private let fastByNorm: [String: String]
    private let chargedByNorm: [String: String]
    private let typeByNorm: [String: String]

    private init() {
        let override = ProcessInfo.processInfo.environment["POGOLENS_GAMEDATA"].map { URL(fileURLWithPath: $0) }
        guard let url = override ?? Bundle.main.url(forResource: "gamedata", withExtension: "json"),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(GameData.self, from: raw) else {
            fatalError("gamedata.json is missing from the bundle; run scripts/refresh-data.py")
        }
        data = decoded
        cpmByLevel = Dictionary(uniqueKeysWithValues: decoded.cpm.map { ($0.level, $0.multiplier) })
        var byName: [String: [Species]] = [:]
        for s in decoded.species { byName[GameDB.norm(s.name), default: []].append(s) }
        speciesByName = byName
        fastByNorm = Dictionary(decoded.fast_moves.map { (GameDB.norm($0), $0) }, uniquingKeysWith: { a, _ in a })
        chargedByNorm = Dictionary(decoded.charged_moves.map { (GameDB.norm($0), $0) }, uniquingKeysWith: { a, _ in a })
        typeByNorm = Dictionary(uniqueKeysWithValues: decoded.types.map { (GameDB.norm($0), $0) })
    }

    static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func multiplier(level: Double) -> Double? { cpmByLevel[level] }
    var allLevels: [Double] { data.cpm.map(\.level).sorted() }

    func levels(forDust dust: Int) -> [Double] { data.dust_levels[String(dust)] ?? [] }
    var dustTiers: Set<Int> { Set(data.dust) }

    /// Every form whose species name matches, base form first.
    func species(named raw: String) -> [Species] {
        let hits = speciesByName[GameDB.norm(raw)] ?? []
        return hits.sorted { a, b in a.isBaseForm && !b.isBaseForm }
    }

    func species(key: String) -> Species? { data.species.first { $0.key == key } }

    func moveset(for s: Species) -> Moveset? { data.movesets[s.key] ?? data.movesets["\(s.id)-Normal"] }

    /// Exact match after normalising; OCR drops hyphens and spaces the same way.
    func fastMove(matching text: String) -> String? { fastByNorm[GameDB.norm(text)] }
    func chargedMove(matching text: String) -> String? { chargedByNorm[GameDB.norm(text)] }
    func type(matching text: String) -> String? { typeByNorm[GameDB.norm(text)] }

    /// Species whose typing and movepool fit what the summary screen showed. Used when the
    /// name on screen is a nickname.
    func speciesMatching(types: [String], fast: String?, charged: [String]) -> [Species] {
        let wanted = Set(types.map(GameDB.norm))
        return data.species.filter { s in
            let have = Set(s.types.map(GameDB.norm))
            guard wanted.isEmpty || wanted == have else { return false }
            guard let ms = moveset(for: s) else { return fast == nil && charged.isEmpty }
            if let f = fast, !ms.fast.contains(f) { return false }
            return charged.allSatisfy { ms.charged.contains($0) }
        }
    }
}
