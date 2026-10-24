import AVFAudio
import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var filename: String
    var addedAt: Date

    init(title: String, filename: String) {
        id = UUID()
        self.title = title
        self.filename = filename
        addedAt = Date()
    }

    var fileURL: URL {
        AudioFiles.directory.appendingPathComponent(filename)
    }
}

enum AudioFiles {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Audio", isDirectory: true)
    }

    // Return values, rather than a SwiftData model, across the background task boundary.
    static func importFile(_ source: URL) throws -> (title: String, filename: String) {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { source.stopAccessingSecurityScopedResource() }
        }

        let filename = try store(pathExtension: source.pathExtension) { destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return (source.deletingPathExtension().lastPathComponent, filename)
    }

    // Move a finished download into Freeify's audio folder.
    static func saveDownload(_ temporary: URL, title: String) throws -> (title: String, filename: String) {
        let filename = try store(pathExtension: "m4a") { destination in
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return (title, filename)
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
