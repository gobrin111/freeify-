import Foundation
import SwiftData

// Song actions shared by the library, playlist, and player screens.
@MainActor
final class LibraryStore: ObservableObject {
    let player = LocalPlayer()
    @Published private(set) var downloadingTrackID: UUID?
    @Published private(set) var downloadProgress: Double?
    @Published var errorMessage: String?

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
    func select(_ track: Track, in list: [Track], context: ModelContext) {
        if track.isDownloaded {
            player.play(track, in: list.filter { $0.isDownloaded })
        } else {
            redownload(track, in: context)
        }
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
        let fileURLs = tracks.flatMap { [$0.fileURL, $0.artworkURL].compactMap { $0 } }
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

    func redownload(_ track: Track, in context: ModelContext) {
        guard let videoID = track.youtubeID, downloadingTrackID == nil else { return }
        downloadingTrackID = track.id
        downloadProgress = nil
        Task { @MainActor in
            defer { downloadingTrackID = nil }
            do {
                let saved = try await YouTubeSource.download(videoID: videoID) { value in
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
            } catch {
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }
}
