import SwiftData
import SwiftUI

@main
@MainActor
struct FreeifyApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: [Track.self, Playlist.self])
    }
}
