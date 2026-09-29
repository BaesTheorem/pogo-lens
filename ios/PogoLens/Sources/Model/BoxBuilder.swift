import Foundation

/// Turns a summary-screen reading into a box record: species match (by name, or by typing and
/// moves when the name is a nickname) and the CP/HP/dust solve for level and IVs.
enum BoxBuilder {
    static func build(_ r: SummaryReading, at when: Date, asset: String) -> ScannedPokemon? {
        let db = GameDB.shared
        guard let cp = r.cp, let name = r.name else { return nil }
        var mon = ScannedPokemon(scannedAt: when, assetIdentifier: asset, nameOnScreen: name, cp: cp)
        mon.gender = r.gender; mon.hp = r.hp; mon.hpMax = r.hpMax; mon.dust = r.dust; mon.candy = r.candy
        mon.evolveCandy = r.evolveCandy; mon.candyOnHand = r.candyOnHand; mon.candyXL = r.candyXL; mon.megaEnergy = r.megaEnergy
        mon.caughtDate = r.caughtDate
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
            mon.speciesKey = base.key
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
