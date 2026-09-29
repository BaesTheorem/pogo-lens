import Foundation

enum ScreenKind: String, Codable { case summary, appraisal, unknown }

/// What the Pokémon summary screen shows in text. Everything is optional: OCR misses lines.
struct SummaryReading {
    var name: String?
    var gender: String?
    var cp: Int?
    var hp: Int?
    var hpMax: Int?
    var dust: Int?
    var candy: Int?
    var fastMove: String?
    var chargedMoves: [String] = []
    var types: [String] = []
    var weightKg: Double?
    var heightM: Double?
    var notes: [String] = []
}

enum ScreenParser {
    static let db = GameDB.shared

    static func classify(_ boxes: [TextBox]) -> ScreenKind {
        let norms = Set(boxes.map(\.norm))
        let appraisalLabels = ["attack", "defense", "hp"].filter { norms.contains($0) }.count
        if appraisalLabels >= 2 { return .appraisal }
        if cpValue(boxes) != nil { return .summary }
        return .unknown
    }

    static func int(_ s: String) -> Int? {
        Int(s.filter { $0.isNumber })
    }

    /// "CP 2345", "CP2,345", or a "CP" box with the number in the next box on the same row.
    static func cpValue(_ boxes: [TextBox]) -> Int? {
        let top = boxes.filter { $0.y < 0.3 }
        for b in top {
            if let m = b.text.range(of: #"(?i)^\s*CP\s*([\d,]{1,5})\s*$"#, options: .regularExpression) {
                let digits = String(b.text[m]).filter { $0.isNumber }
                if let v = Int(digits), v >= 10, v <= 9999 { return v }
            }
        }
        for b in top where b.norm == "cp" {
            if let n = top.first(where: { abs($0.midY - b.midY) < 0.03 && $0.x >= b.maxX - 0.01 && int($0.text) != nil }),
               let v = int(n.text), v >= 10, v <= 9999 { return v }
        }
        return nil
    }

    static func parseSummary(_ boxes: [TextBox]) -> SummaryReading {
        var r = SummaryReading()
        r.cp = cpValue(boxes)

        // HP: "123 / 123 HP" or "HP 123/123"; also a bare "123 / 123" near an "HP" box.
        for b in boxes {
            if let m = try? NSRegularExpression(pattern: #"(\d{1,4})\s*/\s*(\d{1,4})"#).firstMatch(in: b.text, range: NSRange(b.text.startIndex..., in: b.text)),
               let r1 = Range(m.range(at: 1), in: b.text), let r2 = Range(m.range(at: 2), in: b.text) {
                let hasHP = b.norm.contains("hp") || boxes.contains { $0.norm == "hp" && abs($0.midY - b.midY) < 0.03 }
                if hasHP || b.y > 0.35 {
                    r.hp = Int(b.text[r1]); r.hpMax = Int(b.text[r2])
                    break
                }
            }
        }

        // Types, weight, height, moves, dust and candy from the lower half.
        var moveBoxes: [(TextBox, String, Bool)] = []
        for b in boxes where b.y > 0.3 {
            if let t = db.type(matching: b.text), !r.types.contains(t) { r.types.append(t); continue }
            if let m = b.text.range(of: #"(?i)([\d.]+)\s*kg"#, options: .regularExpression) {
                r.weightKg = Double(String(b.text[m]).filter { $0.isNumber || $0 == "." })
                continue
            }
            if let m = b.text.range(of: #"(?i)^([\d.]+)\s*m$"#, options: .regularExpression) {
                r.heightM = Double(String(b.text[m]).filter { $0.isNumber || $0 == "." })
                continue
            }
            if let f = db.fastMove(matching: b.text) { moveBoxes.append((b, f, true)); continue }
            if let c = db.chargedMove(matching: b.text) { moveBoxes.append((b, c, false)); continue }
        }
        // Moves read top to bottom: the fast move is listed first, charged moves below it.
        for (_, name, isFast) in moveBoxes.sorted(by: { $0.0.y < $1.0.y }) {
            if isFast, r.fastMove == nil { r.fastMove = name } else if !isFast, !r.chargedMoves.contains(name) { r.chargedMoves.append(name) }
        }

        // Power-up cost: a number from the stardust tier list in the bottom third, candy beside it.
        let tiers = db.dustTiers
        let bottom = boxes.filter { $0.y > 0.62 }
        if let dustBox = bottom.first(where: { int($0.text).map(tiers.contains) == true }) {
            r.dust = int(dustBox.text)
            if let candyBox = bottom.first(where: { $0 != dustBox && abs($0.midY - dustBox.midY) < 0.03 && (int($0.text) ?? 999) <= 30 }) {
                r.candy = int(candyBox.text)
            }
        }

        // Name: the tallest alphabetic line between the arc and the HP line.
        let hpY = boxes.first { $0.norm.contains("hp") || $0.text.contains("/") }?.y ?? 0.62
        let nameZone = boxes.filter { b in
            guard b.y > 0.28, b.y < hpY, b.midX > 0.2, b.midX < 0.8 else { return false }
            let t = b.text.trimmingCharacters(in: CharacterSet.whitespaces)
            guard t.contains(where: { $0.isLetter }) else { return false }
            if ["cp", "hp", "powerup", "evolve"].contains(b.norm) { return false }
            return db.type(matching: t) == nil && db.fastMove(matching: t) == nil && db.chargedMove(matching: t) == nil
        }
        if let nameBox = nameZone.max(by: { $0.height < $1.height }) {
            var t = nameBox.text.trimmingCharacters(in: CharacterSet.whitespaces)
            if t.contains("\u{2642}") { r.gender = "m"; t = t.replacingOccurrences(of: "\u{2642}", with: "") }
            if t.contains("\u{2640}") { r.gender = "f"; t = t.replacingOccurrences(of: "\u{2640}", with: "") }
            r.name = t.trimmingCharacters(in: CharacterSet.whitespaces)
        }
        for b in boxes where b.text == "\u{2642}" || b.text == "\u{2640}" {
            r.gender = b.text == "\u{2642}" ? "m" : "f"
        }
        if r.name == nil { r.notes.append("name not read") }
        if r.cp == nil { r.notes.append("CP not read") }
        if r.hp == nil { r.notes.append("HP not read") }
        if r.dust == nil { r.notes.append("power-up dust not read; level left open") }
        return r
    }
}
