import SwiftData
import SwiftUI

@main
@MainActor
struct FreeifyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Track.self, Playlist.self, ListenEvent.self, RecommendationEvent.self])
    }
}

// Discover, Search, and Library tabs, sharing one player and store.
@MainActor
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = LibraryStore()

    var body: some View {
        TabView(selection: $store.selectedTab) {
            DiscoverView()
                .withPlayerBar()
                .tabItem { Label("Discover", systemImage: "sparkles") }
                .tag(AppTab.discover)
            YouTubeSearchView()
                .withPlayerBar()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            LibraryView()
                .withPlayerBar()
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .modifier(PlaybackErrorAlerts())
        .environmentObject(store)
        .environmentObject(store.player)
        .environmentObject(store.preview)
        .tint(.mint)
        .task {
            store.attach(modelContext)
            restoreLastSong()
        }
    }

    // Reopen where playback left off, paused, with the library queued.
    private func restoreLastSong() {
        guard store.player.current == nil, let id = store.player.savedTrackID else { return }
        let descriptor = FetchDescriptor<Track>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        let library = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.isDownloaded }
        guard let track = library.first(where: { $0.id == id }) else { return }
        store.player.restore(track, in: library)
    }
}

extension View {
    // The player bar sits above the tab bar on every tab.
    func withPlayerBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { PlayerBar() }
    }
}
