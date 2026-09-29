import Foundation

/// Writes files into a folder the user picks in Files (iCloud Drive/Pokemon GO on Alex's phone).
/// The document picker grants access without an iCloud entitlement, and the grant survives
/// relaunches as a security-scoped bookmark. Same pattern as the Ironman app's sync.
enum CloudFolderSync {
    private static let bookmarkKey = "pl-folder-bookmark"
    private static let nameKey = "pl-folder-name"

    enum CloudError: LocalizedError {
        case notConfigured, bookmarkStale, accessDenied
        case coordination(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "No sync folder chosen yet. Settings > Choose sync folder."
            case .bookmarkStale: return "The sync folder moved or was deleted. Choose it again."
            case .accessDenied: return "iOS would not grant access to the sync folder. Choose it again."
            case .coordination(let d): return d
            }
        }
    }

    static var isConfigured: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }
    static var displayName: String? { UserDefaults.standard.string(forKey: nameKey) }

    static func remember(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    private static func resolve() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { throw CloudError.notConfigured }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            guard url.startAccessingSecurityScopedResource() else { throw CloudError.bookmarkStale }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { throw CloudError.bookmarkStale }
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url
    }

    /// Write one file into the folder; returns its URL.
    @discardableResult
    static func write(_ payload: Data, fileName: String) throws -> URL {
        let folder = try resolve()
        guard folder.startAccessingSecurityScopedResource() else { throw CloudError.accessDenied }
        defer { folder.stopAccessingSecurityScopedResource() }
        let url = folder.appendingPathComponent(fileName)
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do { try payload.write(to: writeURL, options: .atomic) } catch { thrown = error }
        }
        if let coordinationError { throw CloudError.coordination(coordinationError.localizedDescription) }
        if let thrown { throw thrown }
        return url
    }
}
