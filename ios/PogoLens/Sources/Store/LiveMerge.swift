import Foundation

/// Folds the broadcast extension's log into the box when the app comes back to the foreground.
@MainActor
enum LiveMerge {
    static func run(into store: BoxStore) -> String? {
        let recs = LiveLog.drain()
        guard !recs.isEmpty else { return nil }
        var summaries = 0, appraisals = 0, moves = 0
        for rec in recs.sorted(by: { $0.at < $1.at }) {
            switch rec.kind {
            case .summary:
                if let mon = BoxBuilder.build(rec.reading, at: rec.at, asset: "live-\(Int(rec.at.timeIntervalSince1970 * 1000))") {
                    store.upsertLive(mon)
                    summaries += 1
                }
            case .appraisal:
                if let iv = rec.appraisal, store.attachAppraisal(iv, cp: rec.reading.cp, name: rec.reading.name, asset: "live-appraisal", at: rec.at) {
                    appraisals += 1
                }
            case .moves:
                if store.attachMoves(fast: rec.reading.fastMove, charged: rec.reading.chargedMoves, at: rec.at) { moves += 1 }
            case .list, .unknown:
                break
            }
            if let dust = rec.reading.stardustTotal { store.stardust = dust }
        }
        store.save()
        var report = "Live scan: \(summaries) Pokémon, \(appraisals) appraisals, \(moves) move lists."
        if store.autoExport, !store.pokemon.isEmpty, summaries + appraisals + moves > 0 {
            do { report += " Exported \(try store.exportCSV().lastPathComponent)." }
            catch { report += " Export failed: \(error.localizedDescription)" }
        }
        return report
    }
}
