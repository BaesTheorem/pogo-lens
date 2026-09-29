import SwiftUI

struct PokemonDetailView: View {
    @EnvironmentObject var store: BoxStore
    let mon: ScannedPokemon

    private var live: ScannedPokemon { store.pokemon.first { $0.id == mon.id } ?? mon }

    var body: some View {
        let m = live
        List {
            Section {
                LabeledContent("Name on screen", value: m.nameOnScreen)
                LabeledContent("Species", value: m.species?.displayName ?? "not recognised")
                if !m.speciesCandidates.isEmpty {
                    Picker("Pick species", selection: Binding(get: { m.speciesKey ?? "" }, set: { store.setSpecies($0, for: m.id) })) {
                        Text("choose").tag("")
                        ForEach(m.speciesCandidates, id: \.self) { key in
                            Text(GameDB.shared.species(key: key)?.displayName ?? key).tag(key)
                        }
                    }
                }
                LabeledContent("CP", value: String(m.cp))
                LabeledContent("HP", value: m.hpMax.map { "\(m.hp ?? $0) / \($0)" } ?? "?")
                LabeledContent("Level", value: m.levelText)
                LabeledContent("IVs", value: m.ivText + (m.ivPercent.map { String(format: "  %.1f%%", $0) } ?? ""))
                if !m.ivExact, m.candidates.count > 1 {
                    Text("\(m.candidates.count) IV combinations fit. Screenshot the appraisal screen and scan again for exact values.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Moves and stats") {
                LabeledContent("Fast", value: m.fastMove ?? "?")
                LabeledContent("Charged", value: m.chargedMoves.isEmpty ? "?" : m.chargedMoves.joined(separator: ", "))
                LabeledContent("Types", value: m.types.isEmpty ? "?" : m.types.joined(separator: " / "))
                LabeledContent("Power-up", value: m.dust.map { "\($0) dust" + (m.candy.map { ", \($0) candy" } ?? "") } ?? "?")
                if let c = m.candyOnHand { LabeledContent("Candy on hand", value: String(c) + (m.candyXL.map { ", \($0) XL" } ?? "")) }
                if let e = m.evolveCandy { LabeledContent("Evolve", value: "\(e) candy") }
                if let me = m.megaEnergy { LabeledContent("Mega energy", value: String(me)) }
                if let d = m.caughtDate { LabeledContent("Caught", value: d) }
                if let w = m.weightKg { LabeledContent("Weight", value: String(format: "%.2f kg", w)) }
                if let h = m.heightM { LabeledContent("Height", value: String(format: "%.2f m", h)) }
                LabeledContent("Gender", value: m.gender == "m" ? "\u{2642}" : (m.gender == "f" ? "\u{2640}" : "?"))
            }
            Section("Tags (not read from the screen yet)") {
                Toggle("Lucky", isOn: Binding(get: { m.lucky }, set: { _ in store.toggle(\.lucky, for: m.id) }))
                Toggle("Shadow", isOn: Binding(get: { m.shadow }, set: { _ in store.toggle(\.shadow, for: m.id) }))
                Toggle("Purified", isOn: Binding(get: { m.purified }, set: { _ in store.toggle(\.purified, for: m.id) }))
                Toggle("Favorite", isOn: Binding(get: { m.favorite }, set: { _ in store.toggle(\.favorite, for: m.id) }))
            }
            if !m.candidates.isEmpty {
                Section("IV candidates") {
                    ForEach(Array(m.candidates.prefix(30).enumerated()), id: \.offset) { _, c in
                        Text("L\(c.level == c.level.rounded() ? String(Int(c.level)) : String(c.level))  \(c.atk)/\(c.def)/\(c.sta)  \(String(format: "%.1f%%", c.percent))").monospacedDigit()
                    }
                }
            }
            if !m.notes.isEmpty {
                Section("Notes") { ForEach(m.notes, id: \.self) { Text($0).font(.footnote) } }
            }
            Section {
                LabeledContent("Scanned", value: m.scannedAt.formatted(date: .abbreviated, time: .shortened))
                Button("Remove from box", role: .destructive) { store.remove(m.id) }
            }
        }
        .navigationTitle(m.species?.name ?? m.nameOnScreen)
        .navigationBarTitleDisplayMode(.inline)
    }
}
