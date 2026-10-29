import Foundation

// One anonymous visitor per app session, including playback before the first search.
// Only YouTube-issued values are accepted from responses; nothing is synthesized.
actor YouTubeVisitorSession {
    private(set) var current = ""
    private var bootstrap: (id: UUID, task: Task<String, Error>)?

    // Ignore a late response from an older visitor after another response updated it.
    func record(_ value: String?, replacing previous: String) {
        guard current == previous, let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        current = value
    }

    func prepare(using load: @escaping @Sendable () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        if !current.isEmpty { return current }

        let pending: (id: UUID, task: Task<String, Error>)
        if let bootstrap {
            pending = bootstrap
        } else {
            // Shared by simultaneous preview, queue, download, and loudness requests.
            // Canceling one consumer must not cancel initialization for everyone else.
            pending = (UUID(), Task {
                let value = try await load()
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SessionError.missingVisitor
                }
                return value
            })
            bootstrap = pending
        }
        do {
            let value = try await pending.task.value
            if current.isEmpty { current = value }
            if bootstrap?.id == pending.id { bootstrap = nil }
            try Task.checkCancellation()
            return current
        } catch {
            if bootstrap?.id == pending.id { bootstrap = nil }
            throw error
        }
    }

    enum SessionError: LocalizedError {
        case missingVisitor

        var errorDescription: String? {
            "YouTube didn’t establish a playback session. Try again later. Saved songs still play offline."
        }
    }
}
