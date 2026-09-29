import Foundation
import CoreGraphics
import ImageIO

// pogolens-cli: run the app's OCR and parsers over screenshot files on the Mac.
//   POGOLENS_GAMEDATA=ios/PogoLens/Resources/Data/gamedata.json build/pogolens-cli [--boxes] shot.jpg ...

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

let args = Array(CommandLine.arguments.dropFirst())
let showBoxes = args.contains("--boxes")
let paths = args.filter { !$0.hasPrefix("--") }

/// A pogolens-debug-*.json written by the app: the OCR boxes of one screenshot.
struct DebugDump: Codable { let asset: String; let kind: ScreenKind; let boxes: [TextBox] }

func replay(_ path: String) {
    guard let data = FileManager.default.contents(atPath: path), let dump = try? JSONDecoder().decode(DebugDump.self, from: data) else {
        print("== \(path): not a debug dump"); return
    }
    let kind = ScreenParser.classify(dump.boxes)
    print("== \(path): recorded \(dump.kind.rawValue), now \(kind.rawValue) (\(dump.boxes.count) boxes)")
    let reading = ScreenParser.parseSummary(dump.boxes)
    if let out = try? encoder.encode(reading), let text = String(data: out, encoding: .utf8) { print(text) }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let done = DispatchSemaphore(value: 0)

Task {
    for path in paths {
        if path.hasSuffix(".json") { replay(path); continue }
        guard let img = loadImage(path) else { print("== \(path): cannot load"); continue }
        do {
            let boxes = try await TextRecognizer.recognize(img)
            let kind = ScreenParser.classify(boxes)
            print("== \(path): \(kind.rawValue) (\(boxes.count) boxes, \(img.width)x\(img.height))")
            if showBoxes {
                for b in boxes { print(String(format: "   y=%.3f x=%.3f w=%.3f h=%.3f  %@", b.y, b.x, b.width, b.height, b.text)) }
            }
            let reading = ScreenParser.parseSummary(boxes)
            if let data = try? encoder.encode(reading), let text = String(data: data, encoding: .utf8) { print(text) }
            if kind == .appraisal {
                if let iv = AppraisalReader.read(image: img, boxes: boxes) {
                    print("appraisal: \(iv.atk)/\(iv.def)/\(iv.sta) confidence \(String(format: "%.2f", iv.confidence)) [\(iv.debug)]")
                } else {
                    print("appraisal: bars not read")
                }
            }
        } catch {
            print("== \(path): \(error)")
        }
    }
    done.signal()
}
done.wait()
