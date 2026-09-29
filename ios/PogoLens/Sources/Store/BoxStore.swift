import Foundation

/// The scanned box: persisted in the app's Documents folder (visible in Files), exported as a
/// Poke Genie-dialect CSV the Mac-side `pogo` CLI already reads.
@MainActor
final class BoxStore: ObservableObject {
    @Published var pokemon: [ScannedPokemon] = []
    @Published var lastScan: Date? { didSet { UserDefaults.standard.set(lastScan, forKey: "pl-last-scan") } }
    @Published var autoExport: Bool { didSet { UserDefaults.standard.set(autoExport, forKey: "pl-auto-export") } }
    @Published var debugExport: Bool { didSet { UserDefaults.standard.set(debugExport, forKey: "pl-debug-export") } }
    @Published var lastError: String?

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pogolens-box.json")
    }()

    init() {
        let d = UserDefaults.standard
        lastScan = d.object(forKey: "pl-last-scan") as? Date
        autoExport = d.object(forKey: "pl-auto-export") as? Bool ?? true
        debugExport = d.object(forKey: "pl-debug-export") as? Bool ?? false
        if let raw = try? Data(contentsOf: fileURL), let list = try? JSONDecoder().decode([ScannedPokemon].self, from: raw) {
            pokemon = list
        }
    }

    func save() {
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(pokemon).write(to: fileURL, options: .atomic)
        } catch { lastError = error.localizedDescription }
    }

    /// Same screenshot scanned again replaces its earlier reading; otherwise append.
    func upsert(_ mon: ScannedPokemon) {
        if let i = pokemon.firstIndex(where: { $0.assetIdentifier == mon.assetIdentifier }) {
            var kept = mon
            kept.id = pokemon[i].id
            if pokemon[i].ivExact, pokemon[i].appraisalAssetIdentifier != nil, let a = pokemon[i].atk, let d = pokemon[i].def, let s = pokemon[i].sta {
                kept.adoptAppraisal(atk: a, def: d, sta: s, asset: pokemon[i].appraisalAssetIdentifier!)
            }
            pokemon[i] = kept
        } else {
            pokemon.append(mon)
        }
    }

    /// An appraisal screenshot belongs to the most recent summary taken within ten minutes
    /// before it that has no exact IVs yet. Returns false when nothing fits.
    func attachAppraisal(_ iv: AppraisalReading, asset: String, at when: Date) -> Bool {
        let window = when.addingTimeInterval(-600)...when.addingTimeInterval(120)
        guard let i = pokemon.indices
            .filter({ window.contains(pokemon[$0].scannedAt) && !(pokemon[$0].ivExact && pokemon[$0].appraisalAssetIdentifier != nil) })
            .max(by: { pokemon[$0].scannedAt < pokemon[$1].scannedAt }) else { return false }
        pokemon[i].adoptAppraisal(atk: iv.atk, def: iv.def, sta: iv.sta, asset: asset)
        if iv.confidence < 0.5 { pokemon[i].notes.append("appraisal bars read with low confidence (\(iv.debug))") }
        return true
    }

    func setSpecies(_ key: String, for id: UUID) {
        guard let i = pokemon.firstIndex(where: { $0.id == id }), let s = GameDB.shared.species(key: key) else { return }
        pokemon[i].speciesKey = key
        pokemon[i].speciesCandidates = []
        pokemon[i].notes.removeAll { $0.contains("species") || $0.contains("form") }
        if let hp = pokemon[i].hpMax ?? pokemon[i].hp {
            let db = GameDB.shared
            let levels = pokemon[i].dust.map { db.levels(forDust: $0) } ?? []
            let found = Formula.solve(s, cp: pokemon[i].cp, hp: hp, levels: levels.isEmpty ? db.allLevels.filter { $0 <= 51 } : levels, db: db)
            if pokemon[i].appraisalAssetIdentifier == nil { pokemon[i].adoptCandidates(found) } else { pokemon[i].candidates = found }
        }
        save()
    }

    func toggle(_ flag: WritableKeyPath<ScannedPokemon, Bool>, for id: UUID) {
        guard let i = pokemon.firstIndex(where: { $0.id == id }) else { return }
        pokemon[i][keyPath: flag].toggle()
        save()
    }

    func remove(_ id: UUID) {
        pokemon.removeAll { $0.id == id }
        save()
    }

    func clear() {
        pokemon = []
        lastScan = nil
        save()
    }

    // MARK: export

    static let csvHeader = ["Index", "Name", "Form", "Pokemon", "Gender", "CP", "HP", "Atk IV", "Def IV", "Sta IV", "IV Avg",
                            "Level Min", "Level Max", "Quick Move", "Charge Move", "Charge Move 2", "Lucky", "Shadow/Purified",
                            "Favorite", "Rank # (G)", "Name (G)", "Nickname", "Dust", "IV Exact", "Candidates", "Scan Date", "Source"]

    func csvText() -> String {
        var lines = [BoxStore.csvHeader.joined(separator: ",")]
        let iso = ISO8601DateFormatter()
        for (n, m) in pokemon.enumerated() {
            let s = m.species
            let levels = Set(m.candidates.map(\.level)).sorted()
            let nick = s.map { GameDB.norm(m.nameOnScreen) == GameDB.norm($0.name) ? "" : m.nameOnScreen } ?? ""
            let row: [String] = [
                String(n + 1), s?.name ?? m.nameOnScreen, s?.form ?? "", s.map { String($0.id) } ?? "",
                m.gender == "m" ? "\u{2642}" : (m.gender == "f" ? "\u{2640}" : ""),
                String(m.cp), m.hpMax.map(String.init) ?? "",
                m.atk.map(String.init) ?? "", m.def.map(String.init) ?? "", m.sta.map(String.init) ?? "",
                m.ivPercent.map { String(format: "%.1f", $0) } ?? "",
                levels.first.map { String($0) } ?? "", levels.last.map { String($0) } ?? "",
                m.fastMove ?? "", m.chargedMoves.first ?? "", m.chargedMoves.count > 1 ? m.chargedMoves[1] : "",
                m.lucky ? "1" : "0", m.shadow ? "1" : (m.purified ? "2" : "0"), m.favorite ? "1" : "0",
                "", "", nick, m.dust.map(String.init) ?? "", m.ivExact ? "1" : "0", String(m.candidates.count),
                iso.string(from: m.scannedAt), "pogolens",
            ]
            lines.append(row.map(BoxStore.csvCell).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvCell(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Into the sync folder when one is chosen, else into Documents (visible in Files).
    func exportCSV() throws -> URL {
        let stamp = Self.stamp()
        let name = "pogolens-\(stamp).csv"
        let data = Data(csvText().utf8)
        if CloudFolderSync.isConfigured {
            return try CloudFolderSync.write(data, fileName: name)
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Raw OCR boxes for one screenshot, so the parsers can be tuned on the Mac.
    func writeDebug(shot: String, kind: ScreenKind, boxes: [TextBox]) {
        struct Dump: Codable { let asset: String; let kind: ScreenKind; let boxes: [TextBox] }
        let safe = shot.replacingOccurrences(of: "/", with: "_")
        guard let data = try? JSONEncoder().encode(Dump(asset: shot, kind: kind, boxes: boxes)) else { return }
        _ = try? CloudFolderSync.write(data, fileName: "pogolens-debug-\(safe).json")
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }
}
