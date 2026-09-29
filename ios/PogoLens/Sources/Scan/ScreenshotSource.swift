import Foundation
import Photos
import UIKit

/// Screenshots from the photo library, newest last, taken after a given moment.
struct Screenshot {
    let identifier: String
    let created: Date
    let image: CGImage
}

enum ScreenshotSource {
    enum SourceError: LocalizedError {
        case denied
        var errorDescription: String? { "Photo access was not granted. Allow it in Settings > Pogo Lens > Photos." }
    }

    static func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw SourceError.denied }
    }

    static func assets(since: Date?, limit: Int = 400) -> [PHAsset] {
        let options = PHFetchOptions()
        var predicates = [NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)]
        if let since { predicates.append(NSPredicate(format: "creationDate > %@", since as NSDate)) }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var out: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in out.append(asset) }
        return out
    }

    static func load(_ asset: PHAsset) async -> Screenshot? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data, let ui = UIImage(data: data), let cg = ui.cgImage else { cont.resume(returning: nil); return }
                cont.resume(returning: Screenshot(identifier: asset.localIdentifier, created: asset.creationDate ?? Date(), image: cg))
            }
        }
    }
}
