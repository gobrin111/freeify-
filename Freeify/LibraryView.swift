import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.addedAt, order: .reverse) private var tracks: [Track]
    @EnvironmentObject private var store: LibraryStore
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var tracksToRemove: [Track] = []
    @State private var tracksToAdd: [Track] = []
    @State private var radioSeed: SongResult?
    @State private var searchText = ""
    @State private var editMode = EditMode.inactive
    @State private var selection = Set<UUID>()
    @State private var storageBytes: Int64 = 0
    @AppStorage("librarySort") private var sort = LibrarySort.recentlyAdded

    private var filteredTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? tracks : tracks.filter {
            $0.title.localizedStandardContains(query) || ($0.artist?.localizedStandardContains(query) ?? false)
        }
        switch sort {
        case .recentlyAdded:
            return matches
        case .title:
            return matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return matches.sorted {
                let order = ($0.artist ?? "").localizedStandardCompare($1.artist ?? "")
                return order == .orderedSame
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : order == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack(path: $store.libraryPath) {
            Group {
                if tracks.isEmpty {
                    emptyLibrary
                } else if filteredTracks.isEmpty {
                    ContentUnavailableView {
                        Label("No matching tracks", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another title or artist.")
                    } actions: {
                        Button("Clear Search") { searchText = "" }
                            .buttonStyle(PrimaryActionStyle())
                    }
                } else {
                    songList
                }
            }
            .background(Palette.canvas)
            .navigationTitle("Library")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Freeify library"
            )
            .toolbar { toolbar }
            .environment(\.editMode, $editMode)
            .navigationDestination(item: $radioSeed) { seed in
                RadioView(seed: seed)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .liked: LikedSongsView()
                case .playlists: PlaylistsView()
                case .playlist(let id): PlaylistRouteView(id: id)
                }
            }
            .sheet(isPresented: Binding(
                get: { !tracksToAdd.isEmpty },
                set: { if !$0 { tracksToAdd = [] } }
            )) {
                AddToPlaylistView(tracks: tracksToAdd)
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing audio…")
                        .tint(Palette.activity)
                        .foregroundStyle(Palette.textPrimary)
                        .padding(Spacing.xl)
                        .background(Palette.raised, in: ArmorPanelShape(cut: 12))
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let source):
                    importAudio(source)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Couldn’t import audio", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .confirmationDialog(
                tracksToRemove.count == 1 ? "Remove from library?" : "Remove \(tracksToRemove.count) songs from library?",
                isPresented: Binding(
                    get: { !tracksToRemove.isEmpty },
                    set: { if !$0 { tracksToRemove = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button(
                    tracksToRemove.count == 1
                        ? "Remove “\(tracksToRemove.first?.title ?? "")”"
                        : "Remove \(tracksToRemove.count) Songs",
                    role: .destructive
                ) {
                    store.remove(tracksToRemove, in: modelContext)
                    tracksToRemove = []
                    selection = []
                    editMode = .inactive
                }
            } message: {
                Text("This deletes the audio too. YouTube Music songs can be found again in search; songs added from Files must be added again.")
            }
            .task(id: tracks.map { "\($0.filename)\($0.isDownloaded)" }) {
                storageBytes = AudioFiles.usedBytes()
            }
        }
    }

    private var songList: some View {
        List(selection: $selection) {
            if searchText.isEmpty && !editMode.isEditing {
                Section {
                    NavigationLink(value: LibraryRoute.liked) {
                        Label("Liked Songs", systemImage: "heart.fill")
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .themedRow()
                    NavigationLink(value: LibraryRoute.playlists) {
                        Label("Playlists", systemImage: "music.note.list")
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .themedRow()
                }
            }
            Section {
                ForEach(filteredTracks) { track in
                    TrackListRow(track: track, isSelecting: editMode.isEditing) {
                        store.select(track, in: filteredTracks,
                                     from: PlayContext(name: "Library", source: "library", route: .library([])),
                                     context: modelContext)
                    } menu: {
                        trackMenu(track)
                    }
                    .tag(track.id)
                    // Swipes are shortcuts for the More menu. Buttons are text-only: iOS hides
                    // the text of icon-and-text buttons on shorter rows.
                    .swipeActions(edge: .leading) {
                        Button(track.likedAt == nil ? "Like" : "Unlike") {
                            store.toggleLike(track, in: modelContext)
                        }
                        .tint(Palette.pressed)
                        Button("Add to Playlist") {
                            tracksToAdd = [track]
                        }
                        .tint(Palette.pressed)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove", role: .destructive) {
                            tracksToRemove = [track]
                        }
                        if track.youtubeID != nil && track.isDownloaded {
                            Button("Remove Download") {
                                store.removeDownload(track, in: modelContext)
                            }
                            .tint(Palette.pressed)
                        }
                    }
                    .disabled(store.downloadingTrackID == track.id)
                }
            } header: {
                if !editMode.isEditing { sortControl }
            } footer: {
                Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs") · \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)) on this iPhone")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .themedList()
    }

    // Everything you can do with a library song, for its More button and long-press menu.
    @ViewBuilder
    private func trackMenu(_ track: Track) -> some View {
        QueueMenuItems(track: track)
        Button {
            store.toggleLike(track, in: modelContext)
        } label: {
            Label(track.likedAt == nil ? "Like" : "Unlike", systemImage: track.likedAt == nil ? "heart" : "heart.slash")
        }
        Button {
            tracksToAdd = [track]
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
        if let videoID = track.youtubeID {
            Button {
                radioSeed = SongResult(id: videoID, title: track.title, artist: track.artist,
                                       duration: nil, thumbnailURL: nil, artworkURL: nil)
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
            }
            if track.isDownloaded {
                Button {
                    store.removeDownload(track, in: modelContext)
                } label: {
                    Label("Remove Download", systemImage: "arrow.down.circle.dotted")
                }
            } else {
                Button {
                    store.redownload(track, in: modelContext)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(store.isDownloading)
            }
        }
        Button(role: .destructive) {
            tracksToRemove = [track]
        } label: {
            Label("Delete from Library", systemImage: "trash")
        }
    }

    // A labeled sort control under the search field.
    private var sortControl: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                Text("Recently added").tag(LibrarySort.recentlyAdded)
                Text("Title").tag(LibrarySort.title)
                Text("Artist").tag(LibrarySort.artist)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Sort by")
                    .foregroundStyle(Palette.textSecondary)
                Text(sort.label)
                    .foregroundStyle(Palette.hair)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Palette.hair)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: Spacing.target)
        }
        .textCase(nil)
        .accessibilityLabel("Sort by \(sort.label)")
    }

    // First run: a small original mark, a plain promise, and the way in.
    private var emptyLibrary: some View {
        VStack(spacing: Spacing.l) {
            EmptyStateMark()
            Text("Your music, ready offline")
                .font(.title2.bold())
                .foregroundStyle(Palette.textPrimary)
            Text("Find songs on YouTube Music to save them here, or add audio files you already have.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add music") { store.selectedTab = .search }
                .buttonStyle(PrimaryActionStyle())
            Button("Add from Files") { showingImporter = true }
                .foregroundStyle(Palette.hair)
                .frame(minHeight: Spacing.target)
                .disabled(isImporting)
        }
        .padding(.horizontal, Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if editMode.isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button("Remove (\(selection.count))", role: .destructive) {
                    tracksToRemove = tracks.filter { selection.contains($0.id) }
                }
                .disabled(selection.isEmpty)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    tracksToAdd = tracks.filter { selection.contains($0.id) }
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
                .disabled(selection.isEmpty)
                Button("Done") {
                    selection = []
                    editMode = .inactive
                }
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                addMusicMenu
                Menu {
                    Button {
                        editMode = .active
                    } label: {
                        Label("Select Songs", systemImage: "checkmark.circle")
                    }
                    .disabled(tracks.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    // Add music: search YouTube Music, or copy in an audio file.
    private var addMusicMenu: some View {
        Menu {
            Button {
                store.selectedTab = .search
            } label: {
                Label("Search YouTube Music", systemImage: "magnifyingglass")
            }
            Button {
                showingImporter = true
            } label: {
                Label("Add from Files", systemImage: "folder")
            }
            .disabled(isImporting)
        } label: {
            GlyphView(path: ThemeGlyph.add, size: 22)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: Spacing.target, height: Spacing.target)
        }
        .accessibilityLabel("Add music")
    }

    private func importAudio(_ source: URL) {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try AudioFiles.importFile(source)
                }.value
                try store.add(imported, in: modelContext)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

enum LibrarySort: String {
    case recentlyAdded, title, artist

    var label: String {
        switch self {
        case .recentlyAdded: "Recently added"
        case .title: "Title"
        case .artist: "Artist"
        }
    }
}
