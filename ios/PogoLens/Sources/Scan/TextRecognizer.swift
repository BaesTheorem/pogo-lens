import Foundation
import Vision
import CoreGraphics

/// A line of recognised text with its box in top-left-origin unit coordinates.
struct TextBox: Codable, Hashable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Float

    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var norm: String { GameDB.norm(text) }
}

enum TextRecognizer {
    static func recognize(_ image: CGImage) async throws -> [TextBox] {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, error in
                if let error { cont.resume(throwing: error); return }
                let boxes: [TextBox] = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { obs in
                    guard let best = obs.topCandidates(1).first else { return nil }
                    let b = obs.boundingBox  // Vision: origin bottom-left, unit square
                    return TextBox(text: best.string, x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height,
                                   confidence: best.confidence)
                }
                cont.resume(returning: boxes.sorted { $0.y < $1.y })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // game text: move names, numbers, nicknames
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
        }
    }
}
