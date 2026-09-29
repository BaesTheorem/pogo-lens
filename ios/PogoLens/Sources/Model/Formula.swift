import Foundation

/// The game's CP and HP formulas and the IV solver, the same math as the Mac-side pogo CLI.
enum Formula {
    struct Candidate: Codable, Hashable {
        let level: Double
        let atk: Int
        let def: Int
        let sta: Int
        var percent: Double { Double(atk + def + sta) / 45 * 100 }
    }

    static func cp(_ s: Species, ivs: (Int, Int, Int), cpm: Double) -> Int {
        let a = Double(s.atk + ivs.0)
        let d = (Double(s.def + ivs.1)).squareRoot()
        let h = (Double(s.sta + ivs.2)).squareRoot()
        return max(10, Int(floor(a * d * h * cpm * cpm / 10)))
    }

    static func hp(_ s: Species, iv: Int, cpm: Double) -> Int {
        max(10, Int(floor(Double(s.sta + iv) * cpm)))
    }

    /// Every (level, atk, def, sta) that yields exactly this CP and HP at the given levels.
    static func solve(_ s: Species, cp: Int, hp: Int, levels: [Double], db: GameDB) -> [Candidate] {
        var out: [Candidate] = []
        for level in levels {
            guard let m = db.multiplier(level: level) else { continue }
            let staIVs = (0...15).filter { Formula.hp(s, iv: $0, cpm: m) == hp }
            if staIVs.isEmpty { continue }
            for st in staIVs {
                for a in 0...15 {
                    for d in 0...15 where Formula.cp(s, ivs: (a, d, st), cpm: m) == cp {
                        out.append(Candidate(level: level, atk: a, def: d, sta: st))
                    }
                }
            }
        }
        return out
    }
}
