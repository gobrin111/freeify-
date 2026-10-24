import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.addedAt, order: .reverse) private var tracks: [Track]
    @StateObject private var player = LocalPlayer()
    @State private var showingImporter = false
    @State private var showingYouTube = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var libraryError: String?
    @State private var trackToRemove: Track?
    @State private var downloadingTrackID: UUID?
    @State private var downloadProgress: Double?
    @State private var searchText = ""

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
                        Text("Add songs from Files to save a copy in Freeify. Only songs you add appear in this library.")
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
                    List(filteredTracks) { track in
                        Button {
                            select(track)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: player.trackID == track.id ? "waveform" : "music.note")
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if downloadingTrackID == track.id {
                                        ProgressView(value: downloadProgress ?? 0)
                                        Text(downloadProgress.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    } else if !track.isDownloaded {
                                        Text([track.artist, "Not downloaded"].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(track.artist ?? "Saved in Freeify · Offline")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if downloadingTrackID != track.id {
                                    Image(systemName: track.isDownloaded ? "play.circle" : "arrow.down.circle")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                trackToRemove = track
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            if track.youtubeID != nil && track.isDownloaded {
                                Button {
                                    removeDownload(track)
                                } label: {
                                    Label("Remove Download", systemImage: "arrow.down.circle.dotted")
                                }
                                .tint(.orange)
                            }
                        }
                        .disabled(downloadingTrackID == track.id)
                    }
                }
            }
            .navigationTitle("Freeify")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Freeify library"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingYouTube = true
                    } label: {
                        Label("Search YouTube", systemImage: "globe")
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    importButton
                }
            }
            .sheet(isPresented: $showingYouTube) {
                YouTubeSearchView(libraryIDs: Set(tracks.compactMap { $0.youtubeID }), onDownloaded: addTrack)
            }
            .safeAreaInset(edge: .bottom) {
                if player.trackID != nil {
                    playbackControls
                }
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
                "Remove from library?",
                isPresented: Binding(
                    get: { trackToRemove != nil },
                    set: { if !$0 { trackToRemove = nil } }
                ),
                titleVisibility: .visible,
                presenting: trackToRemove
            ) { track in
                Button("Remove “\(track.title)”", role: .destructive) { remove(track) }
            } message: { track in
                Text(track.youtubeID == nil
                    ? "This deletes Freeify’s copy of the audio. To get it back, add it again."
                    : "This deletes the song and its audio. You can find it again in Search YouTube.")
            }
            .alert("Couldn’t update library", isPresented: Binding(
                get: { libraryError != nil },
                set: { if !$0 { libraryError = nil } }
            )) {
                Button("OK", role: .cancel) { libraryError = nil }
            } message: {
                Text(libraryError ?? "")
            }
            .alert("Couldn’t play audio", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { player.errorMessage = nil }
            } message: {
                Text(player.errorMessage ?? "")
            }
        }
        .tint(.mint)
    }

    private var importButton: some View {
        Button {
            showingImporter = true
        } label: {
            Label("Add from Files", systemImage: "plus")
        }
        .disabled(isImporting)
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.title).font(.headline).lineLimit(1)
                Text(player.artist ?? "Saved in Freeify").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Slider(
                value: Binding(get: { player.elapsed }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 0.01)
            )
            .accessibilityLabel("Playback position")
            HStack {
                Text(timeLabel(player.elapsed))
                Spacer()
                Text(timeLabel(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack {
                Button {
                    player.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.shuffle ? Color.mint : .secondary)
                }
                .accessibilityLabel(player.shuffle ? "Shuffle on" : "Shuffle off")
                Spacer()
                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                .accessibilityLabel("Previous")
                Spacer()
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .disabled(!player.hasNext)
                .accessibilityLabel("Next")
                Spacer()
                Button {
                    player.cycleRepeat()
                } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(player.repeatMode == .off ? .secondary : Color.mint)
                }
                .accessibilityLabel(repeatLabel)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func importAudio(_ source: URL) {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try AudioFiles.importFile(source)
                }.value
                try addTrack(imported)
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func addTrack(_ saved: SavedAudio) throws {
        let track = Track(title: saved.title, artist: saved.artist, filename: saved.filename, youtubeID: saved.youtubeID)
        let savedURL = track.fileURL
        modelContext.insert(track)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            try? FileManager.default.removeItem(at: savedURL)
            throw error
        }
    }

    private func select(_ track: Track) {
        if track.isDownloaded {
            player.play(track, in: filteredTracks.filter { $0.isDownloaded })
        } else {
            redownload(track)
        }
    }

    // Delete only the audio file; the song stays listed and can be downloaded again.
    private func removeDownload(_ track: Track) {
        if player.trackID == track.id { player.stop() }
        let fileURL = track.fileURL
        track.isDownloaded = false
        do {
            try modelContext.save()
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            modelContext.rollback()
            libraryError = error.localizedDescription
        }
    }

    private func remove(_ track: Track) {
        player.forget(track)
        let fileURL = track.fileURL
        modelContext.delete(track)
        do {
            try modelContext.save()
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            modelContext.rollback()
            libraryError = error.localizedDescription
        }
    }

    private func redownload(_ track: Track) {
        guard let videoID = track.youtubeID, downloadingTrackID == nil else { return }
        downloadingTrackID = track.id
        downloadProgress = nil
        Task { @MainActor in
            defer { downloadingTrackID = nil }
            do {
                let saved = try await YouTubeSource.download(videoID: videoID) { value in
                    Task { @MainActor in downloadProgress = value }
                }
                track.filename = saved.filename
                track.isDownloaded = true
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    try? FileManager.default.removeItem(at: AudioFiles.directory.appendingPathComponent(saved.filename))
                    throw error
                }
            } catch {
                libraryError = YouTubeSource.describe(error)
            }
        }
    }
}
