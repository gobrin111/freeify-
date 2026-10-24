import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.addedAt, order: .reverse) private var tracks: [Track]
    @StateObject private var store = LibraryStore()
    @State private var showingImporter = false
    @State private var showingYouTube = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var tracksToRemove: [Track] = []
    @State private var tracksToAdd: [Track] = []
    @State private var searchText = ""
    @State private var editMode = EditMode.inactive
    @State private var selection = Set<UUID>()
    @State private var storageBytes: Int64 = 0

    private var filteredTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedStandardContains(query) || ($0.artist?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if tracks.isEmpty {
                    ContentUnavailableView {
                        Label("Your offline library", systemImage: "music.note.list")
                    } description: {
                        Text("Search YouTube Music or add songs from Files to save a copy in Freeify.")
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
            .navigationTitle("Freeify")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Freeify library"
            )
            .toolbar { toolbar }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showingYouTube) {
                YouTubeSearchView(libraryIDs: Set(tracks.compactMap { $0.youtubeID })) { saved in
                    try store.add(saved, in: modelContext)
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
            .alert("Couldn’t update library", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .task(id: tracks.map { "\($0.filename)\($0.isDownloaded)" }) {
                storageBytes = AudioFiles.usedBytes()
            }
        }
        .safeAreaInset(edge: .bottom) { PlayerBar() }
        .modifier(PlayerErrorAlert())
        .environmentObject(store)
        .environmentObject(store.player)
        .tint(.mint)
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
                                store.select(track, in: filteredTracks, context: modelContext)
                            } label: {
                                TrackRow(track: track)
                            }
                        }
                    }
                    .tag(track.id)
                    .swipeActions(edge: .leading) {
                        Button {
                            store.toggleLike(track, in: modelContext)
                        } label: {
                            Label(track.likedAt == nil ? "Like" : "Unlike",
                                  systemImage: track.likedAt == nil ? "heart" : "heart.slash")
                        }
                        .tint(.pink)
                        Button {
                            tracksToAdd = [track]
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            tracksToRemove = [track]
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        if track.youtubeID != nil && track.isDownloaded {
                            Button {
                                store.removeDownload(track, in: modelContext)
                            } label: {
                                Label("Remove Download", systemImage: "arrow.down.circle.dotted")
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    selection = []
                    editMode = .inactive
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    tracksToAdd = tracks.filter { selection.contains($0.id) }
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(selection.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingYouTube = true
                } label: {
                    Label("Search YouTube Music", systemImage: "globe")
                }
                .disabled(isImporting)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                importButton
                Menu {
                    Button {
                        editMode = .active
                    } label: {
                        Label("Select Songs", systemImage: "checkmark.circle")
                    }
                    .disabled(tracks.isEmpty)
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

// Playback errors, shown wherever the player is used.
private struct PlayerErrorAlert: ViewModifier {
    @EnvironmentObject private var player: LocalPlayer

    func body(content: Content) -> some View {
        content.alert("Couldn’t play audio", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
    }
}
