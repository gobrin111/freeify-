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
        NavigationStack {
            Group {
                if tracks.isEmpty {
                    ContentUnavailableView {
                        Label("Your offline library", systemImage: "music.note.list")
                    } description: {
                        Text("Download songs from the Search or Discover tabs, or add songs from Files.")
                    } actions: {
                        importButton
                            .buttonStyle(.borderedProminent)
                    }
                } else if filteredTracks.isEmpty {
                    ContentUnavailableView {
                        Label("No matching songs", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another title or artist, or add a song to your Freeify library.")
                    }
                } else {
                    songList
                }
            }
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
            .sheet(isPresented: Binding(
                get: { !tracksToAdd.isEmpty },
                set: { if !$0 { tracksToAdd = [] } }
            )) {
                AddToPlaylistView(tracks: tracksToAdd)
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing audio…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                    NavigationLink {
                        LikedSongsView()
                    } label: {
                        Label("Liked Songs", systemImage: "heart.fill")
                    }
                    NavigationLink {
                        PlaylistsView()
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }
            }
            Section {
                ForEach(filteredTracks) { track in
                    Group {
                        if editMode.isEditing {
                            TrackRow(track: track)
                        } else {
                            Button {
                                store.select(track, in: filteredTracks, from: "library", context: modelContext)
                            } label: {
                                TrackRow(track: track)
                            }
                        }
                    }
                    .tag(track.id)
                    .contextMenu {
                        QueueMenuItems(track: track)
                        Button {
                            store.toggleLike(track, in: modelContext)
                        } label: {
                            Label(track.likedAt == nil ? "Like" : "Unlike",
                                  systemImage: track.likedAt == nil ? "heart" : "heart.slash")
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
                        }
                    }
                    // Swipe buttons are text-only: iOS hides the text of icon-and-text buttons on
                    // shorter rows, so one-line songs would show only icons.
                    .swipeActions(edge: .leading) {
                        Button(track.likedAt == nil ? "Like" : "Unlike") {
                            store.toggleLike(track, in: modelContext)
                        }
                        .tint(.pink)
                        Button("Add to Playlist") {
                            tracksToAdd = [track]
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Remove", role: .destructive) {
                            tracksToRemove = [track]
                        }
                        if track.youtubeID != nil && track.isDownloaded {
                            Button("Remove Download") {
                                store.removeDownload(track, in: modelContext)
                            }
                            .tint(.orange)
                        }
                    }
                    .disabled(store.downloadingTrackID == track.id)
                }
            } footer: {
                Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs") · \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)) on this iPhone")
            }
        }
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
                importButton
                Menu {
                    Button {
                        editMode = .active
                    } label: {
                        Label("Select Songs", systemImage: "checkmark.circle")
                    }
                    .disabled(tracks.isEmpty)
                    Picker("Sort By", selection: $sort) {
                        Text("Recently Added").tag(LibrarySort.recentlyAdded)
                        Text("Title").tag(LibrarySort.title)
                        Text("Artist").tag(LibrarySort.artist)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private var importButton: some View {
        Button {
            showingImporter = true
        } label: {
            Label("Add from Files", systemImage: "plus")
        }
        .disabled(isImporting)
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
}
