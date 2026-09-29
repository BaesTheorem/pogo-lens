import ReplayKit
import CoreImage
import CoreVideo
import UserNotifications

/// The live scanner. iOS streams every frame of the screen here while a system screen
/// broadcast targets Pogo Lens. About once a second, when the screen has changed, one frame
/// is downscaled, OCR'd and parsed; each Pokémon opened in the game becomes a record in the
/// App Group log the app merges, and a banner over the game shows what was read.
/// Memory ceiling for this extension is about 50 MB, hence the downscale and the pacing.
final class SampleHandler: RPBroadcastSampleHandler {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "pogolens.live", qos: .userInitiated)
    private var busy = false
    private var lastAt = Date.distantPast
    private var lastSig: [Int] = []
    private var small: CVPixelBuffer?
    private var current: (name: String, cp: Int, hp: Int)?
    private var lastAppraisalKey = ""
    private var lastMovesKey = ""
    private var seen = 0
    private var banners: Bool { AppGroup.defaults?.object(forKey: "pl-live-banners") as? Bool ?? true }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        seen = 0; current = nil; lastSig = []
        notify("Live scan on", body: "Open Pokémon GO and page through your Pokémon. Open Appraise for exact IVs.")
    }

    override func broadcastFinished() {
        notify("Live scan finished", body: "\(seen) Pokémon read. Open Pogo Lens to import them.")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, !busy, Date().timeIntervalSince(lastAt) > 0.7,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let sig = signature(pb)
        guard differs(sig, from: lastSig), let frame = downscale(pb) else { return }
        busy = true; lastAt = Date(); lastSig = sig
        queue.async { [self] in
            defer { busy = false }
            handle(frame)
        }
    }

    // MARK: frames

    /// A coarse luminance grid; the screen is "the same" when it barely moves.
    private func signature(_ pb: CVPixelBuffer) -> [Int] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let planar = CVPixelBufferIsPlanar(pb)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pb, 0) : CVPixelBufferGetBaseAddress(pb) else { return [] }
        let bpr = planar ? CVPixelBufferGetBytesPerRowOfPlane(pb, 0) : CVPixelBufferGetBytesPerRow(pb)
        let w = planar ? CVPixelBufferGetWidthOfPlane(pb, 0) : CVPixelBufferGetWidth(pb)
        let h = planar ? CVPixelBufferGetHeightOfPlane(pb, 0) : CVPixelBufferGetHeight(pb)
        let stride = planar ? 1 : 4, offset = planar ? 0 : 1
        let p = base.assumingMemoryBound(to: UInt8.self)
        var out: [Int] = []
        out.reserveCapacity(128)
        for gy in 0..<16 {
            for gx in 0..<8 {
                let x = (gx * 2 + 1) * w / 16, y = (gy * 2 + 1) * h / 32
                out.append(Int(p[y * bpr + x * stride + offset]))
            }
        }
        return out
    }

    private func differs(_ a: [Int], from b: [Int]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        let total = zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
        return total / a.count > 4
    }

    /// One reusable 32BGRA buffer about 720 px wide; enough for the game's text.
    private func downscale(_ pb: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let scale = min(1.0, 720.0 / Double(w))
        let sw = Int(Double(w) * scale), sh = Int(Double(h) * scale)
        if small == nil || CVPixelBufferGetWidth(small!) != sw || CVPixelBufferGetHeight(small!) != sh {
            var buf: CVPixelBuffer?
            let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
            CVPixelBufferCreate(kCFAllocatorDefault, sw, sh, kCVPixelFormatType_32BGRA, attrs, &buf)
            small = buf
        }
        guard let small else { return nil }
        let image = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        ciContext.render(image, to: small, bounds: CGRect(x: 0, y: 0, width: sw, height: sh), colorSpace: CGColorSpaceCreateDeviceRGB())
        return small
    }

    // MARK: reading

    private func handle(_ frame: CVPixelBuffer) {
        guard let boxes = try? TextRecognizer.recognizeSync(pixelBuffer: frame) else { return }
        switch ScreenParser.classify(boxes) {
        case .summary:
            let r = ScreenParser.parseSummary(boxes)
            guard let name = r.name, let cp = r.cp else { return }
            let hp = r.hpMax ?? 0
            if let c = current, c.name == name, c.cp == cp, c.hp == hp { return }  // same Pokémon still on screen
            current = (name, cp, hp)
            seen += 1
            LiveLog.append(LiveRecord(at: Date(), kind: .summary, reading: r, appraisal: nil))
            if banners, let mon = BoxBuilder.build(r, at: Date(), asset: "live") {
                let pct = mon.ivPercent.map { String(format: " (%.0f%%)", $0) } ?? ""
                notify(mon.displayName, body: "CP \(mon.cp) · \(mon.ivText)\(pct) · L\(mon.levelText) · \(seen) read")
            }
        case .appraisal:
            let r = ScreenParser.parseSummary(boxes)
            guard let px = BGRABuffer(frame), let iv = AppraisalReader.read(px, boxes: boxes) else { return }
            let key = "\(r.name ?? "")/\(r.cp ?? 0)/\(iv.atk)/\(iv.def)/\(iv.sta)"
            guard key != lastAppraisalKey else { return }
            lastAppraisalKey = key
            LiveLog.append(LiveRecord(at: Date(), kind: .appraisal, reading: r, appraisal: iv))
            if banners {
                let pct = Double(iv.atk + iv.def + iv.sta) / 45 * 100
                notify(r.name ?? "Appraisal", body: String(format: "IVs %d/%d/%d (%.0f%%)", iv.atk, iv.def, iv.sta, pct))
            }
        case .moves:
            let r = ScreenParser.parseSummary(boxes)
            let key = "\(r.fastMove ?? "")|\(r.chargedMoves.joined(separator: ","))"
            guard key != "|", key != lastMovesKey else { return }
            lastMovesKey = key
            LiveLog.append(LiveRecord(at: Date(), kind: .moves, reading: r, appraisal: nil))
        case .unknown:
            break
        }
    }

    /// One banner, replaced each time, so it reads like an overlay rather than a pile of alerts.
    private func notify(_ title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pogolens-live", content: content, trigger: nil))
    }
}
