import Foundation

/// The app and its broadcast extension share one container and one defaults suite.
enum AppGroup {
    static let id = "group.com.alexhedtke.pogolens"
    static let broadcastExtension = "com.alexhedtke.pogolens.broadcast"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// One thing the live scanner saw: written by the extension, merged by the app.
struct LiveRecord: Codable {
    var at: Date
    var kind: ScreenKind
    var reading: SummaryReading
    var appraisal: AppraisalReading?
}

enum LiveLog {
    private static var file: URL? { AppGroup.container?.appendingPathComponent("live-scans.jsonl") }
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func append(_ rec: LiveRecord) {
        guard let file, var data = try? encoder.encode(rec) else { return }
        data.append(0x0A)
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    static var pendingCount: Int {
        guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }

    /// Everything logged so far; the log then starts over.
    static func drain() -> [LiveRecord] {
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return [] }
        let taken = file.deletingLastPathComponent().appendingPathComponent("live-scans-\(Int(Date().timeIntervalSince1970)).jsonl")
        guard (try? FileManager.default.moveItem(at: file, to: taken)) != nil,
              let text = try? String(contentsOf: taken, encoding: .utf8) else { return [] }
        let recs = text.split(separator: "\n").compactMap { try? decoder.decode(LiveRecord.self, from: Data($0.utf8)) }
        try? FileManager.default.removeItem(at: taken)
        return recs
    }
}
