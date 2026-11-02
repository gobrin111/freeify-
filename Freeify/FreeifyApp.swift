import SQLite3
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
        let storeURL = LibraryRecovery.storeURL
        LibraryRecovery.recoverFromAppGroups()
        let saved = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
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

// Signing tools decide where SwiftData's default library goes: iloader adds an app group and
// SideStore doesn't, so after switching tools the library looked empty while the songs were
// still on the phone. Freeify now keeps the library at a fixed path, copies it back from any
// app group it can see, and Settings shows where every library file is.
enum LibraryRecovery {
    static let storeURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")

    // When this library has no songs and an app group's library does, copy that one here.
    // The group's copy stays, and the store it replaces is kept beside it.
    static func recoverFromAppGroups() {
        guard (songCount(at: storeURL) ?? 0) == 0 else { return }
        let manager = FileManager.default
        for (_, container) in groupContainers() {
            let source = container.appendingPathComponent("Library/Application Support/default.store")
            guard (songCount(at: source) ?? 0) > 0 else { continue }
            do {
                try manager.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
                for suffix in ["", "-wal", "-shm"] {
                    let from = URL(fileURLWithPath: source.path + suffix)
                    let to = URL(fileURLWithPath: storeURL.path + suffix)
                    let aside = URL(fileURLWithPath: storeURL.path + ".before-recovery" + suffix)
                    if manager.fileExists(atPath: to.path) {
                        try? manager.removeItem(at: aside)
                        try manager.moveItem(at: to, to: aside)
                    }
                    if manager.fileExists(atPath: from.path) {
                        try manager.copyItem(at: from, to: to)
                    }
                }
            } catch {}
            return
        }
    }

    // For Settings: the bundle ID, the app groups this install was signed with, and every
    // library file Freeify can reach, with its size and song count.
    static func report() -> String {
        let manager = FileManager.default
        var lines = [
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "none")",
            "Signed app groups: \(signedGroups().joined(separator: ", ").nonEmpty ?? "none")",
            "App:",
        ]
        lines += storeFiles(under: URL(fileURLWithPath: NSHomeDirectory()))
        let audio = (try? manager.contentsOfDirectory(atPath: AudioFiles.directory.path)) ?? []
        lines.append("  Audio: \(audio.filter { !$0.hasSuffix(".jpg") }.count) songs")
        for id in candidateGroups() {
            if let container = manager.containerURL(forSecurityApplicationGroupIdentifier: id) {
                lines.append("\(id):")
                lines += storeFiles(under: container)
            } else {
                lines.append("\(id): no access")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func candidateGroups() -> [String] {
        var ids = signedGroups()
        if let bundleID = Bundle.main.bundleIdentifier, !ids.contains("group.\(bundleID)") {
            ids.append("group.\(bundleID)")
        }
        return ids
    }

    private static func groupContainers() -> [(String, URL)] {
        candidateGroups().compactMap { id in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id).map { (id, $0) }
        }
    }

    // The app groups in the provisioning profile the signing tool embedded.
    private static func signedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let profile = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    // Library files (names containing ".store") under a folder, skipping the audio.
    private static func storeFiles(under base: URL) -> [String] {
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey])
        else { return ["  can't read"] }
        var lines: [String] = []
        for case let file as URL in files {
            if file.lastPathComponent == "Audio" { files.skipDescendants(); continue }
            let name = file.lastPathComponent
            guard name.contains(".store") else { continue }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "?"
            let path = file.path.replacingOccurrences(of: base.path + "/", with: "")
            var line = "  \(path) \(size)"
            if !name.hasSuffix("-wal"), !name.hasSuffix("-shm") {
                line += songCount(at: file).map { ", \($0) songs" } ?? ", unreadable"
            }
            lines.append(line)
        }
        return lines.isEmpty ? ["  no library files"] : lines
    }

    // Songs in a library file, read directly so it works for stores SwiftData isn't using.
    static func songCount(at url: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZTRACK", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
