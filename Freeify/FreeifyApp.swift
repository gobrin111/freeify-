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
            await store.lookUpLoudness(in: modelContext)
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
        modifier(PlayerBarPlacement())
    }
}

// Safe-area insets added outside a navigation stack don't reach the lists inside it, so
// lists would scroll under the mini player. Instead, every scrolling screen in the tab gets
// a bottom margin the bar's height while a song is loaded, and scrolls clear of it.
private struct PlayerBarPlacement: ViewModifier {
    @EnvironmentObject private var player: LocalPlayer
    // Measured, since the bar grows with larger text.
    @State private var barHeight: CGFloat = 64

    func body(content: Content) -> some View {
        let margin = player.current == nil ? 0 : barHeight + Spacing.s
        content
            .contentMargins(.bottom, margin, for: .scrollContent)
            .contentMargins(.bottom, margin, for: .scrollIndicators)
            .overlay(alignment: .bottom) {
                PlayerBar()
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear { barHeight = geometry.size.height }
                                .onChange(of: geometry.size.height) { _, height in barHeight = height }
                        }
                    }
            }
            .toolbarBackground(Palette.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}
