import SwiftData
import SwiftUI

@main
@MainActor
struct FreeifyApp: App {
    private let container: ModelContainer
    private let libraryError: String?

    init() {
        // Freeify never signs in, so it keeps no YouTube cookies: a session YouTube
        // flagged earlier can't follow later requests. Visitor IDs are sent explicitly.
        let cookieStore = HTTPCookieStorage.shared
        cookieStore.cookieAcceptPolicy = .never
        cookieStore.cookies?.forEach(cookieStore.deleteCookie)

        // The library stays at a fixed path next to Audio/. SwiftData's default moves into
        // an app group container when the sideloading tool adds one, which showed an empty
        // library while the songs were still on the phone.
        let schema = Schema([Track.self, Playlist.self, ListenEvent.self, RecommendationEvent.self])
        let saved = ModelConfiguration(
            schema: schema,
            url: URL.applicationSupportDirectory.appendingPathComponent("default.store"),
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: saved)
            libraryError = nil
        } catch {
            // Never replace the saved library; run on an empty one and say why.
            let empty = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            container = try! ModelContainer(for: schema, configurations: empty)
            libraryError = "Freeify couldn't open your saved library, so it looks empty for now. "
                + "Your songs are still on the phone; don't delete the app. (\(error.localizedDescription))"
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(libraryError: libraryError)
        }
        .modelContainer(container)
    }
}

// Discover, Search, and Library tabs, sharing one player and store.
@MainActor
struct RootView: View {
    let libraryError: String?
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
            store.errorMessage = libraryError
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
