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
        let savedURL = track.fileURL
        context.insert(track)
        do {
            try context.save()
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: savedURL)
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
        let fileURLs = tracks.map { $0.fileURL }
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
