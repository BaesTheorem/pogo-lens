import Foundation

enum ScreenKind: String, Codable { case summary, appraisal, moves, list, unknown }

/// What a Pokémon summary screen shows in text. Everything is optional: OCR misses lines, and a
/// screenshot taken scrolled down (the moves list) has no CP at the top.
struct SummaryReading: Codable {
    var name: String?
    var gender: String?
    var cp: Int?
    var hp: Int?
    var hpMax: Int?
    var dust: Int?
    var candy: Int?
    var evolveCandy: Int?
    var candyOnHand: Int?
    var candyXL: Int?
    var megaEnergy: Int?
    var stardustTotal: Int?
    var caughtDate: String?
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
        let labels = ["attack", "defense", "hp"].filter { l in boxes.contains { $0.norm == l && $0.y > 0.5 && $0.x < 0.3 } }.count
        if labels >= 2 { return .appraisal }
        // The storage list shows a CP label over every sprite; a summary has exactly one, up top.
        let cpLabels = boxes.filter { $0.text.range(of: #"(?i)^\s*CP\s*[\d,]{2,5}\s*$"#, options: .regularExpression) != nil }
        if cpLabels.count >= 3 { return .list }
        if cpValue(boxes) != nil, hpLine(boxes) != nil { return .summary }
        if moveBoxes(boxes).count >= 2 { return .moves }
        return .unknown
    }

    /// "82 / 82 HP", or "HP" beside "82 / 82". A bare pair in the middle column counts too, which
    /// keeps the caught-date "06/26" at the right edge from posing as the HP line.
    static func hpLine(_ boxes: [TextBox]) -> (box: TextBox, now: Int, max: Int)? {
        let hpRegex = try! NSRegularExpression(pattern: #"(\d{1,4})\s*/\s*(\d{1,4})"#)
        for b in boxes where b.y > 0.2 {
            guard let m = hpRegex.firstMatch(in: b.text, range: NSRange(b.text.startIndex..., in: b.text)),
                  let r1 = Range(m.range(at: 1), in: b.text), let r2 = Range(m.range(at: 2), in: b.text) else { continue }
            let labelled = b.norm.contains("hp") || boxes.contains { $0.norm == "hp" && sameRow($0, b) }
            let now = Int(b.text[r1]) ?? 0, max = Int(b.text[r2]) ?? 0
            if labelled || (now <= max && max > 9 && b.midX > 0.3 && b.midX < 0.7) { return (b, now, max) }
        }
        return nil
    }

    /// A line that can be a Pokémon's name or nickname: letters, not a CP label, a measurement,
    /// a date, or a button caption caught mid-transition.
    static func plausibleName(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: CharacterSet.whitespaces)
        if t.filter({ $0.isLetter }).count < 3 { return false }
        if t.range(of: #"(?i)^\s*cp\s*\d"#, options: .regularExpression) != nil { return false }
        if t.range(of: #"(?i)^[\d.,]+\s*(m|kg)$"#, options: .regularExpression) != nil { return false }
        let n = GameDB.norm(t)
        if n.contains("pokedex") || ["cp", "hp", "powerup", "evolve", "weight", "height", "stardust"].contains(n) { return false }
        return true
    }

    static func int(_ s: String) -> Int? {
        let digits = s.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    static func sameRow(_ a: TextBox, _ b: TextBox) -> Bool { abs(a.midY - b.midY) < 0.02 }

    static func cpBox(_ boxes: [TextBox]) -> TextBox? {
        boxes.first { b in
            b.y < 0.3 && b.text.range(of: #"(?i)^\s*CP\s*[\d,]{1,5}\s*$"#, options: .regularExpression) != nil
        }
    }

    /// "CP 2345", "CP2,345", or a "CP" box with the number in the next box on the same row.
    static func cpValue(_ boxes: [TextBox]) -> Int? {
        if let b = cpBox(boxes), let v = int(b.text), v >= 10, v <= 9999 { return v }
        for b in boxes where b.y < 0.3 && b.norm == "cp" {
            if let n = boxes.first(where: { sameRow($0, b) && $0.x >= b.maxX - 0.01 && int($0.text) != nil }),
               let v = int(n.text), v >= 10, v <= 9999 { return v }
        }
        return nil
    }

    /// Boxes that are a known move name, top to bottom, with whether it is a fast move.
    static func moveBoxes(_ boxes: [TextBox]) -> [(TextBox, String, Bool)] {
        boxes.filter { $0.y > 0.2 }.compactMap { b in
            if let f = db.fastMove(matching: b.text) { return (b, f, true) }
            if let c = db.chargedMove(matching: b.text) { return (b, c, false) }
            return nil
        }.sorted { $0.0.y < $1.0.y }
    }

    /// The numeric box just above a label (the summary screen stacks value over caption).
    static func valueAbove(_ label: TextBox, in boxes: [TextBox]) -> Int? {
        boxes.filter { b in
            b != label && label.y - b.maxY > -0.005 && label.y - b.maxY < 0.045
                && b.x < label.maxX && b.maxX > label.x && int(b.text) != nil
        }
        .min { abs(label.y - $0.maxY) < abs(label.y - $1.maxY) }
        .flatMap { int($0.text) }
    }

    static func parseSummary(_ boxes: [TextBox]) -> SummaryReading {
        var r = SummaryReading()
        r.cp = cpValue(boxes)
        let cpTop = cpBox(boxes)

        var hpBox: TextBox?
        if let hp = hpLine(boxes) { r.hp = hp.now; r.hpMax = hp.max; hpBox = hp.box }
        let hpY = hpBox?.y ?? 0.62

        // Name: the tallest lettered line in the middle column between the CP and the HP line.
        let nameFloor = (cpTop?.maxY ?? 0.1) + 0.02
        let nameZone = boxes.filter { b in
            guard b.y > nameFloor, b.y < hpY, b.midX > 0.3, b.midX < 0.7, plausibleName(b.text) else { return false }
            let t = b.text.trimmingCharacters(in: CharacterSet.whitespaces)
            return db.type(matching: t) == nil && db.fastMove(matching: t) == nil && db.chargedMove(matching: t) == nil
        }
        if let nameBox = nameZone.max(by: { $0.height < $1.height }) {
            var t = nameBox.text.trimmingCharacters(in: CharacterSet.whitespaces)
            if t.contains("\u{2642}") { r.gender = "m"; t = t.replacingOccurrences(of: "\u{2642}", with: "") }
            if t.contains("\u{2640}") { r.gender = "f"; t = t.replacingOccurrences(of: "\u{2640}", with: "") }
            r.name = t.trimmingCharacters(in: CharacterSet.whitespaces)
        }
        for b in boxes where b.text == "\u{2642}" || b.text == "\u{2640}" { r.gender = b.text == "\u{2642}" ? "m" : "f" }

        // Caught date sits in the right column as "2022" over "06/26".
        let right = boxes.filter { $0.midX > 0.8 && $0.y > 0.25 && $0.y < 0.5 }
        if let year = right.first(where: { $0.text.range(of: #"^\d{4}$"#, options: .regularExpression) != nil }),
           let md = right.first(where: { $0.text.range(of: #"^\d{2}/\d{2}$"#, options: .regularExpression) != nil }) {
            let parts = md.text.split(separator: "/")
            r.caughtDate = "\(year.text)-\(parts[0])-\(parts[1])"
        }

        // Types come as one line, "GRASS / POISON"; weight and height as "8.17kg" and "0.78m".
        for b in boxes where b.y > 0.3 {
            for token in b.text.split(whereSeparator: { "/,".contains($0) }) {
                if let t = db.type(matching: String(token)), !r.types.contains(t) { r.types.append(t) }
            }
            if let m = b.text.range(of: #"(?i)([\d.]+)\s*kg"#, options: .regularExpression) {
                r.weightKg = Double(String(b.text[m]).filter { $0.isNumber || $0 == "." })
            } else if let m = b.text.range(of: #"(?i)^([\d.]+)\s*m$"#, options: .regularExpression) {
                r.heightM = Double(String(b.text[m]).filter { $0.isNumber || $0 == "." })
            }
        }

        // Moves are listed fast first, charged below, under the GYMS & RAIDS / TRAINER BATTLES tabs.
        for (_, name, isFast) in moveBoxes(boxes) {
            if isFast, r.fastMove == nil { r.fastMove = name } else if !isFast, !r.chargedMoves.contains(name) { r.chargedMoves.append(name) }
        }

        // Resources: the number above each caption. Stardust total, species candy, XL candy, mega energy.
        for label in boxes where label.y > 0.5 {
            let n = label.norm
            if n == "stardust" { r.stardustTotal = valueAbove(label, in: boxes) }
            else if n.hasSuffix("candyxl") { r.candyXL = valueAbove(label, in: boxes) }
            else if n.hasSuffix("candy") { r.candyOnHand = valueAbove(label, in: boxes) }
            else if n.hasSuffix("megaenergy") { r.megaEnergy = valueAbove(label, in: boxes) }
        }

        // Power-up cost and candy on the POWER UP row; evolve candy on the EVOLVE row.
        let tiers = db.dustTiers
        if let pu = boxes.first(where: { $0.norm == "powerup" }) {
            for b in boxes where b != pu && sameRow(b, pu) && b.x > pu.maxX - 0.02 {
                guard let v = int(b.text) else { continue }
                if tiers.contains(v) { r.dust = v } else if v <= 30, r.candy == nil { r.candy = v }
            }
        }
        if r.dust == nil, let dustBox = boxes.first(where: { $0.y > 0.62 && int($0.text).map(tiers.contains) == true }) {
            r.dust = int(dustBox.text)  // no POWER UP label read; fall back to any tier-valued number low on the screen
        }
        if let ev = boxes.first(where: { $0.norm == "evolve" }) {
            r.evolveCandy = boxes.first { $0 != ev && sameRow($0, ev) && $0.x > ev.maxX - 0.02 && (int($0.text) ?? 999) <= 400 }.flatMap { int($0.text) }
        }

        if r.name == nil { r.notes.append("name not read") }
        if r.cp == nil { r.notes.append("CP not read") }
        if r.hp == nil { r.notes.append("HP not read") }
        if r.dust == nil { r.notes.append("power-up dust not read; level left open") }
        if r.fastMove == nil { r.notes.append("moves below the fold; screenshot the scrolled-down view too") }
        return r
    }
}
