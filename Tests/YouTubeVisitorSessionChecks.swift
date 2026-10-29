import Foundation

// Runs against the production actor with no YouTube traffic or third-party test tools.
// swiftc -parse-as-library Freeify/YouTubeVisitorSession.swift \
//   Tests/YouTubeVisitorSessionChecks.swift -o /tmp/freeify-session-checks
@main
enum YouTubeVisitorSessionChecks {
    enum Failure: Error {
        case expectedNetworkFailure
        case check(String)
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }

    static func main() async throws {
        let session = YouTubeVisitorSession()
        let counter = Counter()
        let values = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await session.prepare { await counter.load() }
                }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        try expect(values.count == 20 && values.allSatisfy { $0 == "issued-visitor" }, "Concurrent callers must share the issued visitor")
        let count = await counter.count
        try expect(count == 1, "Concurrent callers must only bootstrap once")

        let known = YouTubeVisitorSession()
        await known.record("search-visitor", replacing: "")
        let reused = try await known.prepare { throw Failure.check("Existing visitor must avoid bootstrap") }
        try expect(reused == "search-visitor", "Playback must reuse the search session")
        await known.record("newer-visitor", replacing: "search-visitor")
        await known.record("late-visitor", replacing: "search-visitor")
        await known.record("   ", replacing: "newer-visitor")
        let current = await known.current
        try expect(current == "newer-visitor", "Stale or blank responses must not replace the current session")

        let retry = YouTubeVisitorSession()
        do {
            _ = try await retry.prepare { throw Failure.expectedNetworkFailure }
            throw Failure.check("Bootstrap failure must propagate")
        } catch Failure.expectedNetworkFailure {}
        do {
            _ = try await retry.prepare { " \n" }
            throw Failure.check("Blank visitor must be rejected")
        } catch YouTubeVisitorSession.SessionError.missingVisitor {}
        let recovered = try await retry.prepare { "recovered-visitor" }
        try expect(recovered == "recovered-visitor", "A failed bootstrap must allow a later explicit retry")

        let cancellation = YouTubeVisitorSession()
        let gate = Gate()
        let canceled = Task {
            try await cancellation.prepare { await gate.load() }
        }
        await gate.waitUntilStarted()
        let survivor = Task {
            try await cancellation.prepare { throw Failure.check("Must share the pending bootstrap") }
        }
        canceled.cancel()
        await gate.release()
        let survivingValue = try await survivor.value
        try expect(survivingValue == "shared-visitor", "Canceling a preview must not break another consumer")
        do {
            _ = try await canceled.value
            throw Failure.check("Canceled caller must not proceed to playback")
        } catch is CancellationError {}

        print("PASS: concurrent bootstrap, session reuse, stale responses, failure recovery, cancellation")
    }

    actor Counter {
        private(set) var count = 0
        func load() -> String {
            count += 1
            return "issued-visitor"
        }
    }

    actor Gate {
        private var started = false
        private var startedWaiter: CheckedContinuation<Void, Never>?
        private var completion: CheckedContinuation<String, Never>?

        func load() async -> String {
            started = true
            startedWaiter?.resume()
            startedWaiter = nil
            return await withCheckedContinuation { completion = $0 }
        }

        func waitUntilStarted() async {
            if started { return }
            await withCheckedContinuation { startedWaiter = $0 }
        }

        func release() {
            completion?.resume(returning: "shared-visitor")
            completion = nil
        }
    }
}
