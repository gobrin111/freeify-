import Foundation
import SwiftData
import UIKit

enum AppTab {
    case discover, search, library
}

// A page inside the Library tab.
enum LibraryRoute: Hashable {
    case liked
    case playlists
    case playlist(UUID)
}

// A screen the player can reopen from "Playing from": a tab and the pages opened inside it.
// An empty path is the tab's main page.
enum AppRoute {
    case discover([DiscoverRoute])
    case library([LibraryRoute])
}

// Progress of "Download All" for one Discover list.
struct BulkDownload {
    let name: String
    let total: Int
    var done = 0
}

// Song actions shared by every tab.
@MainActor
final class LibraryStore: ObservableObject {
    let player = LocalPlayer()
    let preview = PreviewPlayer()
    // One download at a time: a library song being downloaded again, or a YouTube Music song.
    @Published private(set) var downloadingTrackID: UUID?
    @Published private(set) var downloadingSongID: String?
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var bulkDownload: BulkDownload?
    @Published var errorMessage: String?
    // Navigation, so the player can open the list a song is playing from.
    @Published var selectedTab = AppTab.discover
    @Published var discoverPath: [DiscoverRoute] = []
    @Published var libraryPath: [LibraryRoute] = []
    private var cancelBulk = false

    var isDownloading: Bool { downloadingTrackID != nil || downloadingSongID != nil || bulkDownload != nil }

    func show(_ route: AppRoute) {
        switch route {
        case .discover(let path):
            selectedTab = .discover
            discoverPath = path
        case .library(let path):
            selectedTab = .library
            libraryPath = path
        }
    }

    // Record finished plays as listening history.
    func attach(_ context: ModelContext) {
        player.onListen = { listen in
            context.insert(ListenEvent(listen))
            try? context.save()
        }
    }

    func add(_ saved: SavedAudio, in context: ModelContext) throws {
        let track = Track(title: saved.title, artist: saved.artist, filename: saved.filename, youtubeID: saved.youtubeID)
        track.artworkFilename = saved.artworkFilename
        let savedURLs = [track.fileURL, track.artworkURL].compactMap { $0 }
        context.insert(track)
        do {
            try context.save()
        } catch {
            context.rollback()
            savedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    // Play a downloaded track with the rest of its list queued, or download it again.
    func select(_ track: Track, in list: [Track], from playContext: PlayContext, context: ModelContext) {
        if track.isDownloaded {
            preview.stop()
            player.play(.track(track), in: list.filter { $0.isDownloaded }.map(PlayItem.track), context: playContext)
        } else {
            redownload(track, in: context)
        }
    }

    // Play a Discover list from one song, streaming songs that aren't saved.
    // Saved songs play from their file, so they also work offline.
    func playRemote(_ song: SongResult, in songs: [SongResult], from playContext: PlayContext, context: ModelContext) {
        preview.stop()
        let saved = savedTracks(in: context)
        let items = songs.map { song in saved[song.id].map(PlayItem.track) ?? .stream(song) }
        guard let item = items.first(where: { $0.youtubeID == song.id }) else { return }
        player.play(item, in: items, context: playContext)
    }

    // Put a Discover list in a playlist with its name (or add to that playlist), then download
    // its songs. The playlist is saved first: songs not saved yet join the library as
    // "Not downloaded", so the playlist is complete even if Freeify closes midway.
    func downloadAll(_ songs: [SongResult], named name: String, in context: ModelContext) {
        guard !isDownloading else { return }
        let existing = libraryTracks(in: context)
        let tracks = songs.map { song -> Track in
            if let track = existing[song.id] { return track }
            let track = Track(title: song.title, artist: song.artist, filename: "", youtubeID: song.id)
            track.isDownloaded = false
            track.remoteArtworkURL = song.artworkURL?.absoluteString
            context.insert(track)
            return track
        }
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        if let playlist = playlists.first(where: { $0.name == name }) {
            add(tracks, to: playlist, in: context)
        } else {
            createPlaylist(named: name, with: tracks, in: context)
        }
        downloadMissing(tracks, named: name, in: context)
    }

    // Download a list's "Not downloaded" songs one at a time. A song that fails or stalls is
    // skipped and stays "Not downloaded" to try again.
    func downloadMissing(_ tracks: [Track], named name: String, in context: ModelContext) {
        guard !isDownloading else { return }
        let missing = tracks.filter { !$0.isDownloaded && $0.youtubeID != nil }
        bulkDownload = BulkDownload(name: name, total: missing.count)
        cancelBulk = false
        // Keep the screen on, so auto-lock doesn't let iOS pause the downloads.
        UIApplication.shared.isIdleTimerDisabled = true
        Task { @MainActor in
            var failed = 0
            for track in missing {
                if cancelBulk { break }
                do {
                    try await downloadTrack(track, in: context)
                } catch {
                    failed += 1
                }
                bulkDownload?.done += 1
            }
            UIApplication.shared.isIdleTimerDisabled = false
            bulkDownload = nil
            if failed > 0 {
                errorMessage = "\(failed) \(failed == 1 ? "song" : "songs") couldn’t be downloaded. They’re in the “\(name)” playlist as Not downloaded; tap one, or use Download Missing in the playlist, to try again."
            }
        }
    }

    // Stops after the song downloading now finishes.
    func cancelDownloadAll() {
        cancelBulk = true
    }

    // Library songs from YouTube, saved or not, by video ID.
    private func libraryTracks(in context: ModelContext) -> [String: Track] {
        let tracks = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        return Dictionary(
            tracks.compactMap { track in track.youtubeID.map { ($0, track) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Saved songs from YouTube, by video ID.
    private func savedTracks(in context: ModelContext) -> [String: Track] {
        let tracks = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        return Dictionary(
            tracks.compactMap { track in track.isDownloaded ? track.youtubeID.map { ($0, track) } : nil },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Delete only the audio file; the song stays listed and can be downloaded again.
    func removeDownload(_ track: Track, in context: ModelContext) {
        if player.trackID == track.id { player.stop() }
        let fileURL = track.fileURL
        track.isDownloaded = false
        do {
            try context.save()
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ tracks: [Track], in context: ModelContext) {
        // "Not downloaded" songs have no audio file to delete.
        let fileURLs = tracks.flatMap { track in
            [track.isDownloaded && !track.filename.isEmpty ? track.fileURL : nil, track.artworkURL].compactMap { $0 }
        }
        let ids = Set(tracks.map { $0.id })
        for playlist in (try? context.fetch(FetchDescriptor<Playlist>())) ?? [] {
            playlist.trackIDs.removeAll { ids.contains($0) }
        }
        for track in tracks {
            player.forget(track)
            context.delete(track)
        }
        do {
            try context.save()
            fileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    func toggleLike(_ track: Track, in context: ModelContext) {
        track.likedAt = track.likedAt == nil ? Date() : nil
        // Liking a song that was recommended is feedback for "Made for you".
        if track.likedAt != nil, let videoID = track.youtubeID {
            var shown = FetchDescriptor<RecommendationEvent>(predicate: #Predicate { $0.youtubeID == videoID })
            shown.fetchLimit = 1
            if let event = try? context.fetch(shown).first {
                context.insert(RecommendationEvent(youtubeID: videoID, mix: event.mix, action: "liked", features: event.features))
            }
        }
        save(context)
    }

    func createPlaylist(named name: String, with tracks: [Track] = [], in context: ModelContext) {
        context.insert(Playlist(name: name, trackIDs: tracks.map { $0.id }))
        save(context)
    }

    // Songs already in the playlist aren't added again.
    func add(_ tracks: [Track], to playlist: Playlist, in context: ModelContext) {
        let existing = Set(playlist.trackIDs)
        playlist.trackIDs += tracks.map { $0.id }.filter { !existing.contains($0) }
        save(context)
    }

    func delete(_ playlist: Playlist, in context: ModelContext) {
        context.delete(playlist)
        save(context)
    }

    func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    // Pause library playback so a preview isn't mixed with it.
    func togglePreview(_ song: SongResult) {
        if preview.songID != song.id && player.isPlaying {
            player.pause()
        }
        preview.toggle(song)
    }

    // Download a YouTube Music song into the library.
    func download(_ song: SongResult, in context: ModelContext) {
        guard !isDownloading else { return }
        Task { @MainActor in
            do {
                try await downloadSong(song, in: context)
            } catch {
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }

    private func downloadSong(_ song: SongResult, in context: ModelContext) async throws {
        downloadingSongID = song.id
        downloadProgress = nil
        defer { downloadingSongID = nil }
        let saved = try await YouTubeSource.download(
            videoID: song.id, title: song.title, artist: song.artist, artworkURL: song.artworkURL
        ) { value in
            Task { @MainActor in self.downloadProgress = value }
        }
        try add(saved, in: context)
    }

    func redownload(_ track: Track, in context: ModelContext) {
        guard !isDownloading else { return }
        Task { @MainActor in
            do {
                try await downloadTrack(track, in: context)
            } catch {
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }

    // Download a library song's audio, keeping its details and any existing cover art.
    private func downloadTrack(_ track: Track, in context: ModelContext) async throws {
        guard let videoID = track.youtubeID else { return }
        downloadingTrackID = track.id
        downloadingSongID = videoID // so Discover rows show the progress too
        downloadProgress = nil
        // If the phone is locked mid-song, ask iOS for time to finish it.
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Download song") {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
        defer {
            downloadingTrackID = nil
            downloadingSongID = nil
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        let saved = try await YouTubeSource.download(
            videoID: videoID,
            artworkURL: track.remoteArtworkURL.flatMap { URL(string: $0) }
        ) { value in
            Task { @MainActor in self.downloadProgress = value }
        }
        track.filename = saved.filename
        track.isDownloaded = true
        // Keep the existing cover art; use the new copy only if there was none.
        if track.artworkFilename == nil {
            track.artworkFilename = saved.artworkFilename
        } else if let extra = saved.artworkFilename {
            try? FileManager.default.removeItem(at: AudioFiles.directory.appendingPathComponent(extra))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: AudioFiles.directory.appendingPathComponent(saved.filename))
            throw error
        }
    }
}
