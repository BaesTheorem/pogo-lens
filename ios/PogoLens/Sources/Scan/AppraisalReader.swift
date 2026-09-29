import Foundation
import CoreGraphics

/// Reads the three IV bars on the appraisal screen from pixels: each bar is 15 segments, filled
/// segments are warm orange (red at 15), empty ones pale grey. Layout is found from the OCR'd
/// "Attack", "Defense" and "HP" labels, so it does not depend on the device's exact geometry.
/// This needs calibration against real screenshots; the debug string carries what it saw.
struct AppraisalReading: Codable {
    let atk: Int
    let def: Int
    let sta: Int
    let confidence: Double
    let debug: String
}

enum AppraisalReader {
    static func read(image: CGImage, boxes: [TextBox]) -> AppraisalReading? {
        guard let px = PixelBuffer(image) else { return nil }
        var values: [String: (Int, Double, String)] = [:]
        for label in ["attack", "defense", "hp"] {
            guard let box = boxes.first(where: { $0.norm == label && $0.y > 0.3 }) else { continue }
            if let v = readBar(px, labelBox: box) { values[label] = v }
        }
        guard let a = values["attack"], let d = values["defense"], let h = values["hp"] else { return nil }
        let conf = min(a.1, d.1, h.1)
        return AppraisalReading(atk: a.0, def: d.0, sta: h.0, confidence: conf, debug: "atk:\(a.2) def:\(d.2) hp:\(h.2)")
    }

    /// Scan the label's row to the right; count filled vs empty segment pixels.
    private static func readBar(_ px: PixelBuffer, labelBox: TextBox) -> (Int, Double, String)? {
        let rowsToTry = [labelBox.midY, labelBox.midY + labelBox.height * 0.9, labelBox.midY + labelBox.height * 1.8]
        var best: (Int, Double, String)?
        for rowFrac in rowsToTry {
            let y = Int(rowFrac * Double(px.height))
            guard y >= 0, y < px.height else { continue }
            let startX = Int(min(0.95, labelBox.maxX + 0.01) * Double(px.width))
            var filled = 0, empty = 0, firstBar = -1, lastBar = -1
            for x in stride(from: startX, to: Int(0.97 * Double(px.width)), by: 2) {
                let c = px.rgb(x, y)
                switch classify(c) {
                case .filled: filled += 1; if firstBar < 0 { firstBar = x }; lastBar = x
                case .empty: empty += 1; if firstBar < 0 { firstBar = x }; lastBar = x
                case .other: break
                }
            }
            let total = filled + empty
            guard total >= 40 else { continue }
            let fraction = Double(filled) / Double(total)
            let iv = Int((fraction * 15).rounded())
            let span = lastBar - firstBar
            let confidence = min(1.0, Double(total) * 2 / Double(max(span, 1)))  // how much of the span was bar-coloured
            let dbg = "y\(y) filled\(filled) empty\(empty) span\(span)"
            if best == nil || confidence > best!.1 { best = (min(15, max(0, iv)), confidence, dbg) }
        }
        return best
    }

    private enum Segment { case filled, empty, other }

    private static func classify(_ c: (r: Int, g: Int, b: Int)) -> Segment {
        let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b)
        let sat = maxC - minC
        // Orange (approx 255,150,40) or red/pink (approx 240,60,80) fills.
        if c.r > 170 && sat > 90 && c.r >= c.g && c.r > c.b { return .filled }
        // Pale grey empty segments.
        if minC > 170 && sat < 30 { return .empty }
        return .other
    }
}

/// RGBA8 copy of an image so single pixels can be sampled cheaply.
struct PixelBuffer {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        width = image.width; height = image.height
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buf
    }

    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        guard i >= 0, i + 2 < data.count else { return (0, 0, 0) }
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}
