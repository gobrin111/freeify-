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
    // Drawn once; the root view refreshes often while downloads report progress.
    private static let libraryIcon = GlyphView.image(ThemeGlyph.library)

    var body: some View {
        TabView(selection: $store.selectedTab) {
            LibraryView()
                .withPlayerBar()
                .tabItem { Label { Text("Library") } icon: { Self.libraryIcon } }
                .tag(AppTab.library)
            DiscoverView()
                .withPlayerBar()
                .tabItem { Label("Discover", systemImage: "sparkles") }
                .tag(AppTab.discover)
            YouTubeSearchView()
                .withPlayerBar()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            SettingsView()
                .withPlayerBar()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
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
        .tint(Palette.hair)
        .preferredColorScheme(.dark)
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
    // The mini player sits above the tab bar on every tab, which uses the dark surface.
    func withPlayerBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { PlayerBar() }
            .toolbarBackground(Palette.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}
