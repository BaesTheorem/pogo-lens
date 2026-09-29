import Foundation

/// Runs OCR over new screenshots and folds the readings into the box.
@MainActor
final class Scanner: ObservableObject {
    @Published var isScanning = false
    @Published var progress = ""
    @Published var lastReport = ""

    private let db = GameDB.shared

    func scanNew(into store: BoxStore, everything: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            try await ScreenshotSource.authorize()
        } catch {
            lastReport = error.localizedDescription
            return
        }
        let assets = ScreenshotSource.assets(since: everything ? nil : store.lastScan)
        if assets.isEmpty {
            lastReport = "No new screenshots since \(store.lastScan.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "ever")."
            return
        }
        var summaries = 0, appraisals = 0, skipped = 0
        for (i, asset) in assets.enumerated() {
            progress = "Reading screenshot \(i + 1) of \(assets.count)"
            guard let shot = await ScreenshotSource.load(asset) else { skipped += 1; continue }
            let boxes: [TextBox]
            do { boxes = try await TextRecognizer.recognize(shot.image) } catch { skipped += 1; continue }
            let kind = ScreenParser.classify(boxes)
            switch kind {
            case .summary:
                let reading = ScreenParser.parseSummary(boxes)
                if let mon = build(reading, shot: shot) {
                    store.upsert(mon)
                    summaries += 1
                } else { skipped += 1 }
            case .appraisal:
                if let iv = AppraisalReader.read(image: shot.image, boxes: boxes), store.attachAppraisal(iv, asset: shot.identifier, at: shot.created) {
                    appraisals += 1
                } else { skipped += 1 }
            case .unknown:
                skipped += 1
            }
            if store.debugExport { store.writeDebug(shot: shot.identifier, kind: kind, boxes: boxes) }
            store.lastScan = max(store.lastScan ?? .distantPast, shot.created)
        }
        store.save()
        if store.autoExport, store.pokemon.count > 0, summaries + appraisals > 0 {
            do { let url = try store.exportCSV(); lastReport = "Read \(summaries) Pokémon and \(appraisals) appraisals from \(assets.count) screenshots; exported to \(url.lastPathComponent)." }
            catch { lastReport = "Read \(summaries) Pokémon, \(appraisals) appraisals; export failed: \(error.localizedDescription)" }
        } else {
            lastReport = "Read \(summaries) Pokémon and \(appraisals) appraisals from \(assets.count) screenshots (\(skipped) were not Pokémon GO screens)."
        }
        progress = ""
    }

    private func build(_ r: SummaryReading, shot: Screenshot) -> ScannedPokemon? {
        guard let cp = r.cp, let name = r.name else { return nil }
        var mon = ScannedPokemon(scannedAt: shot.created, assetIdentifier: shot.identifier, nameOnScreen: name, cp: cp)
        mon.gender = r.gender; mon.hp = r.hp; mon.hpMax = r.hpMax; mon.dust = r.dust; mon.candy = r.candy
        mon.fastMove = r.fastMove; mon.chargedMoves = r.chargedMoves; mon.types = r.types
        mon.weightKg = r.weightKg; mon.heightM = r.heightM; mon.notes = r.notes

        var matches = db.species(named: name)
        if matches.isEmpty {
            matches = db.speciesMatching(types: r.types, fast: r.fastMove, charged: r.chargedMoves)
            if matches.count > 12 { matches = [] }
        }
        if !r.types.isEmpty, matches.count > 1 {
            let wanted = Set(r.types.map(GameDB.norm))
            let typed = matches.filter { Set($0.types.map(GameDB.norm)) == wanted }
            if !typed.isEmpty { matches = typed }
        }
        if matches.count == 1 {
            mon.speciesKey = matches[0].key
        } else if let base = matches.first(where: \.isBaseForm), matches.allSatisfy({ $0.id == base.id }) {
            mon.speciesKey = base.key  // same species, several forms: default to the base form
            if matches.count > 1 { mon.speciesCandidates = matches.map(\.key); mon.notes.append("form not read; base form assumed") }
        } else {
            mon.speciesCandidates = matches.map(\.key)
            mon.notes.append(matches.isEmpty ? "species not recognised (nickname?)" : "several species fit; pick one")
        }
        if let s = mon.species, let hp = r.hpMax ?? r.hp {
            let levels = r.dust.map { db.levels(forDust: $0) } ?? []
            let found = Formula.solve(s, cp: cp, hp: hp, levels: levels.isEmpty ? db.allLevels.filter { $0 <= 51 } : levels, db: db)
            mon.adoptCandidates(found)
            if found.isEmpty { mon.notes.append("no IV combination fits CP \(cp) and HP \(hp); check the species") }
        }
        return mon
    }
}
