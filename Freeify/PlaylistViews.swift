import SwiftData
import SwiftUI

struct LikedSongsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tracks: [Track]
    @EnvironmentObject private var store: LibraryStore

    private var liked: [Track] {
        tracks
            .filter { $0.likedAt != nil }
            .sorted { ($0.likedAt ?? .distantPast) > ($1.likedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            ForEach(liked) { track in
                Button {
                    store.select(track, in: liked, from: PlayContext(name: "Liked Songs", source: "liked"), context: modelContext)
                } label: {
                    TrackRow(track: track)
                }
                .contextMenu { QueueMenuItems(track: track) }
                .swipeActions(edge: .trailing) {
                    Button("Unlike") {
                        store.toggleLike(track, in: modelContext)
                    }
                    .tint(.pink)
                }
                .disabled(store.downloadingTrackID == track.id)
            }
        }
        .overlay {
            if liked.isEmpty {
                ContentUnavailableView {
                    Label("No liked songs", systemImage: "heart")
                } description: {
                    Text("Swipe right on a song in your library and tap the heart to like it.")
                }
            }
        }
        .navigationTitle("Liked Songs")
    }
}

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @EnvironmentObject private var store: LibraryStore
    @State private var naming = false
    @State private var newName = ""
    @State private var playlistToDelete: Playlist?

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    PlaylistLabel(playlist: playlist)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        playlistToDelete = playlist
                    }
                }
            }
        }
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView {
                    Label("No playlists", systemImage: "music.note.list")
                } description: {
                    Text("Create a playlist, then add songs from your library.")
                } actions: {
                    Button("New Playlist") { naming = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    naming = true
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
            }
        }
        .alert("New Playlist", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") {
                store.createPlaylist(named: playlistName(newName, existing: playlists), in: modelContext)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .confirmationDialog(
            "Delete playlist?",
            isPresented: Binding(
                get: { playlistToDelete != nil },
                set: { if !$0 { playlistToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: playlistToDelete
        ) { playlist in
            Button("Delete “\(playlist.name)”", role: .destructive) {
                store.delete(playlist, in: modelContext)
            }
        } message: { _ in
            Text("The songs stay in your library.")
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.modelContext) private var modelContext
    @Query private var tracks: [Track]
    @EnvironmentObject private var store: LibraryStore
    @State private var addingSongs = false
    @State private var renaming = false
    @State private var newName = ""

    private var songs: [Track] {
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.trackIDs.compactMap { byID[$0] }
    }

    var body: some View {
        List {
            ForEach(songs) { track in
                Button {
                    store.select(track, in: songs, from: PlayContext(name: playlist.name, source: "playlist"), context: modelContext)
                } label: {
                    TrackRow(track: track)
                }
                .contextMenu { QueueMenuItems(track: track) }
                .disabled(store.downloadingTrackID == track.id)
            }
            .onMove { from, to in
                var ids = songs.map { $0.id }
                ids.move(fromOffsets: from, toOffset: to)
                playlist.trackIDs = ids
                store.save(modelContext)
            }
            .onDelete { offsets in
                let removed = Set(offsets.map { songs[$0].id })
                playlist.trackIDs.removeAll { removed.contains($0) }
                store.save(modelContext)
            }
        }
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView {
                    Label("No songs yet", systemImage: "music.note")
                } description: {
                    Text("Add songs from your library to this playlist.")
                } actions: {
                    Button("Add Songs") { addingSongs = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !songs.isEmpty { EditButton() }
                Menu {
                    Button {
                        addingSongs = true
                    } label: {
                        Label("Add Songs", systemImage: "plus")
                    }
                    Button {
                        newName = playlist.name
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $addingSongs) {
            SongPickerView(excluded: Set(playlist.trackIDs)) { picked in
                store.add(picked, to: playlist, in: modelContext)
            }
        }
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    playlist.name = name
                    store.save(modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// Pick library songs to add to a playlist.
struct SongPickerView: View {
    let excluded: Set<UUID>
    let onAdd: ([Track]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Track.addedAt, order: .reverse) private var tracks: [Track]
    @State private var selection = Set<UUID>()

    private var available: [Track] { tracks.filter { !excluded.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List(available, selection: $selection) { track in
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).lineLimit(2)
                    if let artist = track.artist {
                        Text(artist).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .overlay {
                if available.isEmpty {
                    ContentUnavailableView("Every song is already here", systemImage: "checkmark.circle")
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selection.count))") {
                        onAdd(available.filter { selection.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}

// Choose a playlist for one or more library songs, or create a new one with them.
struct AddToPlaylistView: View {
    let tracks: [Track]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @EnvironmentObject private var store: LibraryStore
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    naming = true
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                ForEach(playlists) { playlist in
                    Button {
                        store.add(tracks, to: playlist, in: modelContext)
                        dismiss()
                    } label: {
                        PlaylistLabel(playlist: playlist)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(tracks.count == 1 ? "Add to Playlist" : "Add \(tracks.count) Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create") {
                    store.createPlaylist(named: playlistName(newName, existing: playlists), with: tracks, in: modelContext)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }
}

struct PlaylistLabel: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).lineLimit(1)
                Text("\(playlist.trackIDs.count) \(playlist.trackIDs.count == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// An empty name becomes "My Playlist #n", like Spotify.
private func playlistName(_ name: String, existing: [Playlist]) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "My Playlist #\(existing.count + 1)" : trimmed
}
