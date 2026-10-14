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

        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)

        do {
            try manager.copyItem(at: source, to: destination)
            // Validate before adding a library entry. Unsupported or corrupt files throw.
            _ = try AVAudioPlayer(contentsOf: destination)
            // Keep imported files readable when the phone locks after its first unlock.
            try manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
            return (source.deletingPathExtension().lastPathComponent, destination.lastPathComponent)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }
}
