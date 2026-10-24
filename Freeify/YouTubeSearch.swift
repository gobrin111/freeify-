import Foundation
import SwiftUI
import YouTubeKit

@MainActor
struct YouTubeSearchView: View {
    // Video IDs already in the library, so the same song isn't downloaded twice.
    let libraryIDs: Set<String>
    let onDownloaded: (SavedAudio) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SongResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var downloadingID: String?
    @State private var progress: Double?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results) { song in
                Button {
                    download(song)
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text([song.artist, song.duration, libraryIDs.contains(song.id) ? "In library" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if downloadingID == song.id {
                                ProgressView(value: progress ?? 0)
                                Text(progress.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if libraryIDs.contains(song.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        } else if downloadingID != song.id {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .overlay {
                if isSearching {
                    ProgressView("Searching…")
                } else if results.isEmpty && hasSearched {
                    ContentUnavailableView {
                        Label("No songs found", systemImage: "magnifyingglass")
                    } description: {
                        Text("YouTube Music has no songs matching that search. Try another title or artist.")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("Search YouTube Music", systemImage: "magnifyingglass")
                    } description: {
                        Text("Find a song, then tap it to save an offline copy in Freeify.")
                    }
                }
            }
            .navigationTitle("YouTube Music")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Song or artist"
            )
            .onSubmit(of: .search) { search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(downloadingID != nil)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(downloadingID != nil)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, downloadingID == nil else { return }
        isSearching = true
        Task { @MainActor in
            defer { isSearching = false }
            do {
                results = try await YouTubeSource.searchSongs(text)
                hasSearched = true
            } catch {
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }

    private func download(_ song: SongResult) {
        guard downloadingID == nil, !isSearching, !libraryIDs.contains(song.id) else { return }
        downloadingID = song.id
        progress = nil
        Task { @MainActor in
            defer { downloadingID = nil }
            do {
                let saved = try await YouTubeSource.download(
                    videoID: song.id, title: song.title, artist: song.artist
                ) { value in
                    Task { @MainActor in progress = value }
                }
                try onDownloaded(saved)
                dismiss()
            } catch {
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }
}

struct SongResult: Identifiable, Sendable {
    let id: String // YouTube video ID
    let title: String
    let artist: String?
    let duration: String?
}

enum YouTubeSource {
    // Client settings follow yt-dlp's visionos client.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private static let model: YouTubeModel = {
        let model = YouTubeModel()
        // YouTubeKit's default iOS client needs a proof-of-origin token Freeify can't create,
        // so its audio links return HTTP 403. The visionOS client's links work without one
        // and without running YouTube's JavaScript player.
        model.customHeaders[.videoInfosWithDownloadFormats] = HeadersList(
            url: URL(string: "https://www.youtube.com/youtubei/v1/player")!,
            method: .POST,
            headers: [
                .init(name: "Content-Type", content: "application/json"),
                .init(name: "User-Agent", content: YouTubeSource.userAgent),
                .init(name: "Origin", content: "https://www.youtube.com"),
                .init(name: "X-Youtube-Client-Name", content: "101"),
                .init(name: "X-Youtube-Client-Version", content: "1.02")
            ],
            customHeaders: ["X-Goog-Visitor-Id": .visitorData],
            addQueryAfterParts: [.init(index: 0, encode: false, content: .query)],
            httpBody: [
                #"{"contentCheckOk":true,"racyCheckOk":true,"context":{"client":{"clientName":"VISIONOS","clientVersion":"1.02","deviceMake":"Apple","deviceModel":"RealityDevice17,1","osName":"visionOS","osVersion":"26.5.23O471","hl":"en","userAgent":"\#(YouTubeSource.userAgent)"}},"playbackContext":{"contentPlaybackContext":{"html5Preference":"HTML5_PREF_WANTS"}},"videoId":""#,
                #""}"#
            ],
            parameters: [.init(name: "prettyPrint", content: "false")]
        )
        return model
    }()

    // Search YouTube Music's Songs tab, the way ytmusicapi does, so results are songs
    // with their real artist instead of every kind of YouTube video.
    static func searchSongs(_ query: String) async throws -> [SongResult] {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        if !model.visitorData.isEmpty {
            request.setValue(model.visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        let body: [String: Any] = [
            "context": ["client": [
                "clientName": "WEB_REMIX",
                "clientVersion": musicClientVersion(),
                "hl": model.selectedLocaleLanguageCode
            ]],
            "query": query,
            "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF" // Songs filter
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status), let json = try? JSONSerialization.jsonObject(with: data) else {
            throw SourceError(errorDescription: "YouTube Music search didn’t work (HTTP \(status)). Try again in a moment.")
        }
        // Downloads without a visitor ID hit YouTube's bot check, reported as "Login is required".
        // Keep the first one so searches stay consistent.
        if model.visitorData.isEmpty, let visitorData = dig(json, "responseContext", "visitorData") as? String {
            model.visitorData = visitorData
        }
        let tabs = dig(json, "contents", "tabbedSearchResultsRenderer", "tabs") as? [Any]
        let sections = dig(tabs?.first, "tabRenderer", "content", "sectionListRenderer", "contents") as? [Any] ?? []
        return sections
            .flatMap { dig($0, "musicShelfRenderer", "contents") as? [Any] ?? [] }
            .compactMap(parseSong)
    }

    // ytmusicapi uses today's date as the web client version.
    private static func musicClientVersion() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return "1.\(formatter.string(from: Date())).01.00"
    }

    // A song row has the title in its first column and "Artist • Album • 3:16" in its second.
    private static func parseSong(_ item: Any) -> SongResult? {
        guard let renderer = dig(item, "musicResponsiveListItemRenderer"),
              let columns = dig(renderer, "flexColumns") as? [Any], columns.count >= 2
        else { return nil }
        let titleRuns = dig(columns[0], "musicResponsiveListItemFlexColumnRenderer", "text", "runs") as? [Any] ?? []
        let detailRuns = dig(columns[1], "musicResponsiveListItemFlexColumnRenderer", "text", "runs") as? [Any] ?? []
        guard let title = dig(titleRuns.first, "text") as? String,
              let videoID = (dig(renderer, "playlistItemData", "videoId")
                  ?? dig(titleRuns.first, "navigationEndpoint", "watchEndpoint", "videoId")) as? String
        else { return nil }

        var artists: [String] = []
        var duration: String?
        var pastArtists = false
        // Odd runs are separators such as " • " or " & ".
        for (index, run) in detailRuns.enumerated() where index % 2 == 0 {
            guard let text = dig(run, "text") as? String else { continue }
            let browseID = dig(run, "navigationEndpoint", "browseEndpoint", "browseId") as? String
            if text.range(of: #"^(\d+:)*\d+:\d+$"#, options: .regularExpression) != nil {
                duration = text
            } else if browseID?.hasPrefix("MPRE") == true {
                pastArtists = true // album
            } else if !pastArtists {
                artists.append(text)
            }
        }
        return SongResult(
            id: videoID,
            title: title,
            artist: artists.isEmpty ? nil : artists.joined(separator: ", "),
            duration: duration
        )
    }

    private static func dig(_ value: Any?, _ keys: String...) -> Any? {
        keys.reduce(value) { ($0 as? [String: Any])?[$1] }
    }

    // Download a song by video ID. Without a known title (a re-download), use YouTube's video title.
    static func download(
        videoID: String,
        title: String? = nil,
        artist: String? = nil,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SavedAudio {
        try await download(YTVideo(videoId: videoID), title: title, artist: artist, onProgress: onProgress)
    }

    // Use YouTube's AAC (audio/mp4) stream; AVAudioPlayer can't play its WebM/Opus formats.
    private static func download(
        _ video: YTVideo,
        title: String?,
        artist: String?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SavedAudio {
        let infos = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: model)
        let format = infos.downloadFormats
            .compactMap { $0 as? AudioOnlyFormat }
            .filter { $0.mimeType == "audio/mp4" && $0.url != nil && !$0.isDrc }
            .max { ($0.averageBitrate ?? 0) < ($1.averageBitrate ?? 0) }
        guard let format, let url = format.url else {
            let found = Set(infos.downloadFormats.compactMap { $0.mimeType }).sorted().joined(separator: ", ")
            throw SourceError(errorDescription: "YouTube has no audio Freeify can play for this song. Try another version of it.\n\nDetails: formats \(found.isEmpty ? "none" : found)")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // YouTube throttles audio-only downloads that don't request an explicit range.
        if let length = format.contentLength {
            request.setValue("bytes=0-\(length)", forHTTPHeaderField: "Range")
        }
        let (temporary, response) = try await URLSession.shared.download(
            for: request,
            delegate: ProgressDelegate(expectedBytes: format.contentLength, onProgress: onProgress)
        )
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            try? FileManager.default.removeItem(at: temporary)
            throw SourceError(errorDescription: status == 403
                ? "YouTube refused the download (HTTP 403). YouTube may have changed how downloads work, so Freeify may need an update."
                : "The download failed (HTTP \(status)). Try again.")
        }

        let name = title.map { (title: $0, artist: artist) } ?? SongName.parse(
            infos.videoInfos.title ?? "Untitled",
            channel: infos.videoInfos.channel?.name
        )
        do {
            return try await Task.detached(priority: .userInitiated) {
                try AudioFiles.saveDownload(temporary, title: name.title, artist: name.artist, youtubeID: video.videoId)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    // Reports download progress in whole-percent steps.
    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
        let expectedBytes: Int?
        let onProgress: @Sendable (Double) -> Void
        private var observation: NSKeyValueObservation?
        private var lastPercent = -1

        init(expectedBytes: Int?, onProgress: @escaping @Sendable (Double) -> Void) {
            self.expectedBytes = expectedBytes
            self.onProgress = onProgress
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            observation = task.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
                guard let self else { return }
                let total = self.expectedBytes.map { Int64($0) } ?? progress.totalUnitCount
                guard total > 0 else { return }
                let percent = Int(min(Double(progress.completedUnitCount) / Double(total), 1) * 100)
                guard percent != self.lastPercent else { return }
                self.lastPercent = percent
                self.onProgress(Double(percent) / 100)
            }
        }
    }

    // Plain messages for search and download failures. YouTubeKit errors aren't localized,
    // so their details follow in small print for diagnosing YouTube changes.
    static func describe(_ error: Error) -> String {
        if let error = error as? SourceError {
            return error.errorDescription ?? "Something went wrong."
        }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dataNotAllowed].contains(error.code) {
            return "Freeify couldn’t reach YouTube. Check your internet connection and try again."
        }
        let details = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let message: String
        if details.contains("Login is required") {
            message = "YouTube wants a sign-in for this song. It may be age-restricted, or YouTube’s bot check kicked in. Try another version of the song, or try again later."
        } else if details.localizedCaseInsensitiveContains("unavailable") {
            message = "This song isn’t available on YouTube right now. Try another version of it."
        } else {
            message = "YouTube wouldn’t let Freeify get this song. Try again, or try another version of it."
        }
        return "\(message)\n\nDetails: \(details)"
    }

    struct SourceError: LocalizedError {
        let errorDescription: String?
    }
}
