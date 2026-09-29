import SwiftUI

@main
struct PogoLensApp: App {
    @StateObject private var store = BoxStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
