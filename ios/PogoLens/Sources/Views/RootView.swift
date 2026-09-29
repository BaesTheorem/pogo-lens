import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: BoxStore
    @StateObject private var scanner = Scanner()
    @State private var showSettings = false
    @State private var exportMessage: String?
    @State private var liveMessage: String?
    @State private var query = ""
    @Environment(\.scenePhase) private var scenePhase

    private var shown: [ScannedPokemon] {
        let q = GameDB.norm(query)
        let list = store.pokemon.sorted { $0.scannedAt > $1.scannedAt }
        return q.isEmpty ? list : list.filter { GameDB.norm($0.displayName).contains(q) || GameDB.norm($0.nameOnScreen).contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await scanner.scanNew(into: store) }
                    } label: {
                        HStack {
                            Image(systemName: "viewfinder")
                            Text(scanner.isScanning ? (scanner.progress.isEmpty ? "Scanning" : scanner.progress) : "Scan new screenshots")
                            Spacer()
                            if scanner.isScanning { ProgressView() }
                        }
                    }
                    .disabled(scanner.isScanning)
                    if !scanner.lastReport.isEmpty {
                        Text(scanner.lastReport).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let m = exportMessage { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    if let e = store.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                } footer: {
                    Text("In Pokémon GO, open a Pokémon and screenshot it. Screenshot its appraisal too for exact IVs. Then come back and scan.")
                }

                LiveScanSection(message: $liveMessage)
                if let liveMessage { Section { Text(liveMessage).font(.footnote).foregroundStyle(.secondary) } }

                Section("\(store.pokemon.count) Pokémon" + (store.lastScan.map { ", last scan \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")) {
                    ForEach(shown) { mon in
                        NavigationLink(value: mon.id) { PokemonRow(mon: mon) }
                    }
                    .onDelete { idx in idx.map { shown[$0].id }.forEach(store.remove) }
                }
            }
            .searchable(text: $query, prompt: "Species or nickname")
            .navigationTitle("Pogo Lens")
            .navigationDestination(for: UUID.self) { id in
                if let mon = store.pokemon.first(where: { $0.id == id }) { PokemonDetailView(mon: mon) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        do { let url = try store.exportCSV(); exportMessage = "Exported \(url.lastPathComponent)" + (CloudFolderSync.isConfigured ? " to \(CloudFolderSync.displayName ?? "sync folder")" : " to this app's Documents") }
                        catch { exportMessage = error.localizedDescription }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(store.pokemon.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let report = LiveMerge.run(into: store) { liveMessage = report }
            }
        }
    }
}

struct PokemonRow: View {
    let mon: ScannedPokemon

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mon.displayName).fontWeight(.medium)
                Text([mon.fastMove, mon.chargedMoves.joined(separator: " / ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " + "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("CP \(mon.cp)").monospacedDigit()
                HStack(spacing: 6) {
                    Text(mon.ivText)
                    if let p = mon.ivPercent { Text(String(format: "%.0f%%", p)).foregroundStyle(p >= 100 ? .orange : .secondary) }
                    Text("L\(mon.levelText)")
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if !mon.notes.isEmpty { Image(systemName: "exclamationmark.circle").foregroundStyle(.yellow) }
        }
    }
}
