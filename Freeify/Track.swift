import AVFAudio
import Foundation
import SwiftData
import UIKit

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String?
    var filename: String
    var addedAt: Date
    // Set for YouTube downloads so the audio can be downloaded again after "Remove download".
    var youtubeID: String?
    var isDownloaded = true
    var likedAt: Date?
    var artworkFilename: String?

    init(title: String, artist: String?, filename: String, youtubeID: String?) {
        id = UUID()
        self.title = title
        self.artist = artist
        self.filename = filename
        addedAt = Date()
        self.youtubeID = youtubeID
    }

    var fileURL: URL {
        AudioFiles.directory.appendingPathComponent(filename)
    }

    var artworkURL: URL? {
        artworkFilename.map { AudioFiles.directory.appendingPathComponent($0) }
    }
}

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    // Songs in order. A song can be in many playlists without being stored twice.
    var trackIDs: [UUID]
    var createdAt: Date

    init(name: String, trackIDs: [UUID] = []) {
        id = UUID()
        self.name = name
        self.trackIDs = trackIDs
        createdAt = Date()
    }
}

// A saved audio file and what is known about it, before it becomes a Track.
struct SavedAudio: Sendable {
    var title: String
    var artist: String?
    var filename: String
    var youtubeID: String?
    var artworkFilename: String?
}

// Saved cover art, cached in memory so scrolling lists don't reread files.
enum Artwork {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for track: Track) -> UIImage? {
        guard let name = track.artworkFilename, let url = track.artworkURL else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

enum SongName {
    // Split names like "Artist - Song (Official Audio)" into a song title and artist.
    // Falls back to the uploader's channel for the artist.
    static func parse(_ raw: String, channel: String? = nil) -> (title: String, artist: String?) {
        let title = raw
            .replacingOccurrences(of: #"\s*#\S+"#, with: "", options: .regularExpression)
            // Drop labels like "(Official Audio)" or "[Lyric Video]"; keep "(feat. …)" and "(Remix)".
            .replacingOccurrences(
                of: #"\s*[\(\[]\s*(official|lyrics?|audio|video|music video|visuali[sz]er|mv)\b[^\)\]]*[\)\]]"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespaces)
        let channelArtist = channel?
            .replacingOccurrences(of: " - Topic", with: "")
            .replacingOccurrences(of: #"VEVO$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // "Artist - Topic" channels already use the plain song title.
        if channel?.hasSuffix(" - Topic") != true {
            for separator in [" - ", " – ", " — "] {
                guard let range = title.range(of: separator) else { continue }
                let artist = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let song = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty && !song.isEmpty { return (song, artist) }
            }
        }
        return (title.isEmpty ? raw : title, channelArtist?.isEmpty == false ? channelArtist : nil)
    }
}

enum AudioFiles {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Audio", isDirectory: true)
    }

    // Space used by Freeify's saved audio.
    static func usedBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // Return values, rather than a SwiftData model, across the background task boundary.
    static func importFile(_ source: URL) throws -> SavedAudio {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { source.stopAccessingSecurityScopedResource() }
        }

        let filename = try store(pathExtension: source.pathExtension) { destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
        let name = SongName.parse(source.deletingPathExtension().lastPathComponent)
        return SavedAudio(title: name.title, artist: name.artist, filename: filename, youtubeID: nil)
    }

    // Move a finished download into Freeify's audio folder.
    static func saveDownload(_ temporary: URL, title: String, artist: String?, youtubeID: String) throws -> SavedAudio {
        let filename = try store(pathExtension: "m4a") { destination in
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return SavedAudio(title: title, artist: artist, filename: filename, youtubeID: youtubeID)
    }

    static func saveArtwork(_ data: Data) throws -> String {
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try data.write(to: destination, options: .completeFileProtectionUntilFirstUserAuthentication)
        return destination.lastPathComponent
    }

    private static func store(pathExtension: String, place: (URL) throws -> Void) throws -> String {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)

        do {
            try place(destination)
            // Validate before adding a library entry. Unsupported or corrupt files throw.
            _ = try AVAudioPlayer(contentsOf: destination)
            // Keep saved files readable when the phone locks after its first unlock.
            try manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
            return destination.lastPathComponent
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }
}
