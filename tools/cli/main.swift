import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO

// pogolens-cli: run the app's OCR and parsers over screenshot files on the Mac.
//   POGOLENS_GAMEDATA=ios/PogoLens/Resources/Data/gamedata.json build/pogolens-cli [--boxes] shot.jpg ...

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

let args = Array(CommandLine.arguments.dropFirst())
let showBoxes = args.contains("--boxes")
let liveMode = args.contains("--live")
let paths = args.filter { !$0.hasPrefix("--") }

/// The broadcast extension's frame path: downscale to 720 px wide into a 32BGRA pixel buffer,
/// synchronous OCR on that buffer, bars read through BGRABuffer. Same code, same scale.
func liveFrame(_ img: CGImage) -> CVPixelBuffer? {
    let scale = min(1.0, 720.0 / Double(img.width))
    let sw = Int(Double(img.width) * scale), sh = Int(Double(img.height) * scale)
    var buf: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, sw, sh, kCVPixelFormatType_32BGRA, nil, &buf)
    guard let buf else { return nil }
    let ci = CIImage(cgImage: img).transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
    CIContext(options: [.cacheIntermediates: false]).render(ci, to: buf, bounds: CGRect(x: 0, y: 0, width: sw, height: sh), colorSpace: CGColorSpaceCreateDeviceRGB())
    return buf
}

func runLive(_ path: String, _ img: CGImage) {
    guard let frame = liveFrame(img) else { print("== \(path): could not build a frame"); return }
    do {
        let boxes = try TextRecognizer.recognizeSync(pixelBuffer: frame)
        let kind = ScreenParser.classify(boxes)
        print("== \(path) [live path, \(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame))]: \(kind.rawValue) (\(boxes.count) boxes)")
        let r = ScreenParser.parseSummary(boxes)
        print("   name=\(r.name ?? "?") cp=\(r.cp ?? 0) hp=\(r.hpMax ?? 0) dust=\(r.dust ?? 0) candy=\(r.candyOnHand ?? 0) xl=\(r.candyXL ?? 0) types=\(r.types) fast=\(r.fastMove ?? "?") caught=\(r.caughtDate ?? "?")")
        if kind == .appraisal, let px = BGRABuffer(frame) {
            if let iv = AppraisalReader.read(px, boxes: boxes) {
                print("   appraisal: \(iv.atk)/\(iv.def)/\(iv.sta) confidence \(String(format: "%.2f", iv.confidence))")
            } else { print("   appraisal: bars not read") }
        }
        if let mon = BoxBuilder.build(r, at: Date(), asset: "live") {
            print("   banner: \(mon.displayName) · CP \(mon.cp) · \(mon.ivText) · L\(mon.levelText) · \(mon.candidates.count) candidates")
        }
    } catch { print("== \(path): \(error)") }
}

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
        if liveMode { runLive(path, img); continue }
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
