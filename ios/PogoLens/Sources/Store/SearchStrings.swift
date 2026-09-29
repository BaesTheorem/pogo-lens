import Foundation

/// In-game storage search strings, one tap to copy. Built-ins ship with the app; MIST can add
/// or replace entries by writing `pogolens-searches.json` into the sync folder
/// (`[{"title": "...", "string": "...", "note": "..."}]`), matched by title.
struct SearchString: Codable, Identifiable, Hashable {
    var title: String
    var string: String
    var note: String = ""
    var id: String { title }
}

enum SearchStrings {
    static let fileName = "pogolens-searches.json"

    static let builtIn: [SearchString] = [
        SearchString(
            title: "Weekly cleanup: this week's catcher fodder",
            string: "age0-7&0*,1*,2*&!shiny&!lucky&!legendary&!mythical&!costume&!favorite&!shadow&!purified&!buddy&!defender&!traded",
            note: "Caught in the last 7 days, below three stars, nothing shiny, lucky, legendary, mythical, costumed, favorited, shadow, purified, buddy, defending or traded. Select all, Transfer."),
        SearchString(
            title: "All catcher fodder, any age",
            string: "0*,1*,2*&!shiny&!lucky&!legendary&!mythical&!costume&!favorite&!shadow&!purified&!buddy&!defender&!traded",
            note: "Same filter without the age limit. Check the list before transferring."),
        SearchString(
            title: "Keepers to review: three and four stars",
            string: "3*,4*&!favorite",
            note: "Strong IVs not yet favorited. Favorite the ones to keep so the cleanup strings skip them."),
        SearchString(
            title: "Hundos",
            string: "4*",
            note: ""),
        SearchString(
            title: "Caught today",
            string: "age0",
            note: "What the catcher brought in today."),
    ]

    /// Built-ins with the sync-folder file merged over them, by title.
    static func all() -> [SearchString] {
        var merged = builtIn
        if let data = CloudFolderSync.read(fileName: fileName),
           let extra = try? JSONDecoder().decode([SearchString].self, from: data) {
            for e in extra {
                if let i = merged.firstIndex(where: { $0.title == e.title }) { merged[i] = e } else { merged.append(e) }
            }
        }
        return merged
    }
}
