import Foundation
import CoreGraphics
import CoreVideo

/// Reads the three IV bars on the appraisal screen from pixels.
///
/// Measured on an iPhone 16 Pro screenshot: each bar sits just under its label ("Attack",
/// "Defense", "HP"), left-aligned with it, about a third of the screen wide, as three chunks of
/// five points. The filled part is orange (242,166,78), red when the stat is maxed, the rest is
/// light grey (226,226,228), and the bar ends where the card's white background resumes. The
/// labels come from OCR, so nothing here depends on the device's exact geometry.
struct AppraisalReading: Codable {
    let atk: Int
    let def: Int
    let sta: Int
    let confidence: Double
    let debug: String
}

protocol PixelSampler {
    var width: Int { get }
    var height: Int { get }
    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int)
}

enum AppraisalReader {
    static func read(image: CGImage, boxes: [TextBox]) -> AppraisalReading? {
        guard let px = PixelBuffer(image) else { return nil }
        return read(px, boxes: boxes)
    }

    static func read(_ px: PixelSampler, boxes: [TextBox]) -> AppraisalReading? {
        var values: [String: (Int, Double, String)] = [:]
        for label in ["attack", "defense", "hp"] {
            guard let box = boxes.first(where: { $0.norm == label && $0.y > 0.4 && $0.x < 0.4 }) else { continue }
            if let v = readBar(px, labelBox: box) { values[label] = v }
        }
        guard let a = values["attack"], let d = values["defense"], let h = values["hp"] else { return nil }
        return AppraisalReading(atk: a.0, def: d.0, sta: h.0, confidence: min(a.1, d.1, h.1),
                                debug: "atk[\(a.2)] def[\(d.2)] hp[\(h.2)]")
    }

    private static func readBar(_ px: PixelSampler, labelBox: TextBox) -> (Int, Double, String)? {
        let w = Double(px.width), h = Double(px.height)
        let labelH = labelBox.height * h
        let x0 = max(0, Int((labelBox.x - 0.01) * w))
        let xLimit = min(px.width - 1, Int(min(1.0, labelBox.x + 0.6) * w))
        let whiteGap = max(6, Int(0.02 * w))
        var best: (Int, Double, String)?
        for f in [0.5, 0.65, 0.8, 0.35, 0.95] {
            let y = Int(labelBox.maxY * h + f * labelH)
            guard y >= 0, y < px.height else { continue }
            var x = x0
            while x < xLimit, classify(px.rgb(x, y)) == .other { x += 1 }  // white lead-in before the bar
            guard x < xLimit else { continue }
            let start = x
            var lastFilled = -1, filled = 0, empty = 0, whiteRun = 0, end = xLimit
            while x < xLimit {
                switch classify(px.rgb(x, y)) {
                case .other:
                    whiteRun += 1
                    if whiteRun >= whiteGap { end = x - whiteRun + 1; x = xLimit }
                case .filled:
                    whiteRun = 0; filled += 1; lastFilled = x
                case .empty:
                    whiteRun = 0; empty += 1
                }
                x += 1
            }
            let span = end - start
            guard span > Int(0.15 * w), span < Int(0.7 * w) else { continue }
            let coverage = Double(filled + empty) / Double(span)
            guard coverage > 0.6 else { continue }
            let fraction = lastFilled < 0 ? 0 : Double(lastFilled - start + 1) / Double(span)
            let iv = min(15, max(0, Int((fraction * 15).rounded())))
            let dbg = "y\(y) x\(start)-\(end) fill\(filled) grey\(empty) frac\(String(format: "%.2f", fraction))"
            if best == nil || coverage > best!.1 { best = (iv, coverage, dbg) }
        }
        return best
    }

    private enum Segment { case filled, empty, other }

    private static func classify(_ c: (r: Int, g: Int, b: Int)) -> Segment {
        if c.r > 200 && c.r - c.b > 90 && c.g < 200 { return .filled }      // orange, or red when maxed
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        if mn >= 195 && mx <= 242 && mx - mn < 16 { return .empty }        // unfilled grey, below card white
        return .other
    }
}

/// RGBA8 copy of an image so single pixels can be sampled cheaply.
struct PixelBuffer: PixelSampler {
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

/// A 32BGRA CVPixelBuffer (the broadcast extension's downscaled frame), copied out so the
/// buffer can be unlocked before the bars are read.
struct BGRABuffer: PixelSampler {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let data: Data

    init?(_ pb: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        width = CVPixelBufferGetWidth(pb); height = CVPixelBufferGetHeight(pb)
        bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        data = Data(bytes: base, count: bytesPerRow * height)
    }

    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = y * bytesPerRow + x * 4
        guard i >= 0, i + 2 < data.count else { return (0, 0, 0) }
        return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
    }
}
