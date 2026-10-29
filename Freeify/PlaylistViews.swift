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
                TrackListRow(track: track) {
                    store.select(track, in: liked, from: PlayContext(name: "Liked Songs", source: "liked", route: .library([.liked])),
                                 context: modelContext)
                } menu: {
                    QueueMenuItems(track: track)
                    Button {
                        store.toggleLike(track, in: modelContext)
                    } label: {
                        Label("Unlike", systemImage: "heart.slash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Unlike") {
                        store.toggleLike(track, in: modelContext)
                    }
                    .tint(Palette.pressed)
                }
                .disabled(store.downloadingTrackID == track.id)
            }
        }
        .themedList()
        .overlay {
            if liked.isEmpty {
                ContentUnavailableView {
                    Label("No liked songs", systemImage: "heart")
                } description: {
                    Text("Tap More on a song in your library, then Like.")
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
                NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                    PlaylistLabel(playlist: playlist)
                }
                .themedRow()
                .contextMenu {
                    Button(role: .destructive) {
                        playlistToDelete = playlist
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
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
                        .buttonStyle(PrimaryActionStyle())
                }
            }
        }
        .themedList()
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
                TrackListRow(track: track) {
                    store.select(track, in: songs, from: PlayContext(
                        name: playlist.name, source: "playlist", route: .library([.playlists, .playlist(playlist.id)])
                    ), context: modelContext)
                } menu: {
                    QueueMenuItems(track: track)
                    Button {
                        store.toggleLike(track, in: modelContext)
                    } label: {
                        Label(track.likedAt == nil ? "Like" : "Unlike", systemImage: track.likedAt == nil ? "heart" : "heart.slash")
                    }
                    // Removing from a playlist keeps the song in the library.
                    Button {
                        playlist.trackIDs.removeAll { $0 == track.id }
                        store.save(modelContext)
                    } label: {
                        Label("Remove from Playlist", systemImage: "minus.circle")
                    }
                }
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
                        .buttonStyle(PrimaryActionStyle())
                }
            }
        }
        .themedList()
        .navigationTitle(playlist.name)
        .safeAreaInset(edge: .top) { DownloadAllBanner(name: playlist.name) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !songs.isEmpty { EditButton() }
                Menu {
                    Button {
                        addingSongs = true
                    } label: {
                        Label("Add Songs", systemImage: "plus")
                    }
                    let missing = songs.filter { !$0.isDownloaded && $0.youtubeID != nil }
                    if !missing.isEmpty {
                        Button {
                            store.downloadMissing(songs, named: playlist.name, in: modelContext)
                        } label: {
                            Label("Download Missing (\(missing.count))", systemImage: "arrow.down.circle")
                        }
                        .disabled(store.isDownloading)
                    }
                    Button {
                        newName = playlist.name
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
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

// Opens a playlist by ID, e.g. from "Playing from", which may outlive the playlist.
struct PlaylistRouteView: View {
    let id: UUID
    @Query private var playlists: [Playlist]

    var body: some View {
        if let playlist = playlists.first(where: { $0.id == id }) {
            PlaylistDetailView(playlist: playlist)
        } else {
            ContentUnavailableView("This playlist was deleted", systemImage: "music.note.list")
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
                HStack(spacing: Spacing.m) {
                    ArtworkView(track: track, size: 40)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(track.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if let artist = track.artist {
                            Text(artist).font(.subheadline).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                    }
                }
                .themedRow()
            }
            .themedList()
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
        .presentationBackground(Palette.raised)
    }
}

// Add one or more library songs to playlists, or take them out. Playlists that already have
// them show a check; tapping toggles, and the sheet stays open until Done.
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
                        .foregroundStyle(Palette.hair)
                        .frame(minHeight: Spacing.target)
                }
                .themedRow()
                ForEach(playlists) { playlist in
                    let state = membership(in: playlist)
                    Button {
                        if state == .all {
                            store.remove(tracks, from: playlist, in: modelContext)
                        } else {
                            store.add(tracks, to: playlist, in: modelContext)
                        }
                    } label: {
                        HStack {
                            PlaylistLabel(playlist: playlist)
                            Spacer(minLength: Spacing.s)
                            Image(systemName: state.symbol)
                                .font(.title3)
                                .foregroundStyle(state == .missing ? Palette.textMuted : Palette.hair)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .themedRow()
                    .accessibilityAddTraits(state == .all ? .isSelected : [])
                    .accessibilityHint(state == .all ? "Removes from this playlist" : "Adds to this playlist")
                }
            }
            .themedList()
            .navigationTitle(tracks.count == 1 ? "Add to Playlist" : "Add \(tracks.count) Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create") {
                    store.createPlaylist(named: playlistName(newName, existing: playlists), with: tracks, in: modelContext)
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
        .presentationBackground(Palette.raised)
    }

    private enum Membership {
        case missing, partial, all

        var symbol: String {
            switch self {
            case .missing: return "circle"
            case .partial: return "minus.circle.fill"
            case .all: return "checkmark.circle.fill"
            }
        }
    }

    // With several songs selected, a playlist can have only some of them; tapping adds the rest.
    private func membership(in playlist: Playlist) -> Membership {
        let ids = Set(playlist.trackIDs)
        let count = tracks.filter { ids.contains($0.id) }.count
        return count == 0 ? .missing : (count == tracks.count ? .all : .partial)
    }
}

struct PlaylistLabel: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "music.note.list")
                .foregroundStyle(Palette.hair)
                .frame(width: Spacing.thumbnail, height: Spacing.thumbnail)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(playlist.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(playlist.trackIDs.count) \(playlist.trackIDs.count == 1 ? "song" : "songs")")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, Spacing.m)
    }
}

// An empty name becomes "My Playlist #n", like Spotify.
private func playlistName(_ name: String, existing: [Playlist]) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "My Playlist #\(existing.count + 1)" : trimmed
}
