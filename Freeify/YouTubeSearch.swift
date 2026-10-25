import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import YouTubeKit

// The Search tab: YouTube Music's Songs tab, with more results as you scroll.
@MainActor
struct YouTubeSearchView: View {
    @State private var query = ""
    @State private var results: [SongResult] = []
    @State private var continuation: String?
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    // Bumped on each new search so a late page from an older search is ignored.
    @State private var searchGeneration = 0
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var radioSeed: SongResult?

    var body: some View {
        NavigationStack {
            List {
                RemoteSongRows(songs: results) { radioSeed = $0 }
                if continuation != nil {
                    Group {
                        if loadMoreFailed {
                            Button("Load More") { loadMore() }
                        } else {
                            ProgressView()
                                .onAppear { loadMore() }
                        }
                    }
                    .frame(maxWidth: .infinity)
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
                        Text("Find a song, then tap play to preview it or the download button to save it in Freeify.")
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Songs on YouTube Music"
            )
            .onSubmit(of: .search) { search() }
            .navigationDestination(item: $radioSeed) { seed in
                RadioView(seed: seed)
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
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        searchGeneration += 1
        let generation = searchGeneration
        results = []
        continuation = nil
        loadMoreFailed = false
        Task { @MainActor in
            defer { isSearching = false }
            do {
                let page = try await YouTubeSource.searchSongs(text)
                guard generation == searchGeneration else { return }
                var seen = Set<String>()
                results = page.songs.filter { seen.insert($0.id).inserted }
                continuation = page.continuation
                hasSearched = true
            } catch {
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }

    // Fetch the next page when the list reaches its end.
    private func loadMore() {
        guard let token = continuation, !isLoadingMore, !isSearching else { return }
        isLoadingMore = true
        loadMoreFailed = false
        let generation = searchGeneration
        Task { @MainActor in
            do {
                let page = try await YouTubeSource.moreSongs(token)
                isLoadingMore = false
                guard generation == searchGeneration else { return }
                // Pages can repeat a song; keep the first copy so list rows stay unique.
                var seen = Set(results.map { $0.id })
                let added = page.songs.filter { seen.insert($0.id).inserted }
                results += added
                continuation = page.continuation
                // The loading row only appears once, so fetch on if this page added nothing.
                if added.isEmpty { loadMore() }
            } catch {
                isLoadingMore = false
                guard generation == searchGeneration else { return }
                loadMoreFailed = true
            }
        }
    }
}

// YouTube Music songs with cover art, preview, and download, for use inside a List.
// Shared by search, radio, and Discover.
struct RemoteSongRows: View {
    let songs: [SongResult]
    // Discover lists play songs in the player, queued from this list; search previews them.
    var playContext: PlayContext?
    var startRadio: ((SongResult) -> Void)?
    // For recommendations: called with "previewed" or "downloaded", and for "Not interested".
    var onAction: ((SongResult, String) -> Void)?
    var notInterested: ((SongResult) -> Void)?
    @Query private var tracks: [Track]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        // Video IDs already in the library, so the same song isn't downloaded twice.
        let libraryIDs = Set(tracks.compactMap { $0.youtubeID })
        ForEach(songs) { song in
            RemoteSongRow(
                song: song,
                inLibrary: libraryIDs.contains(song.id),
                play: playContext.map { context -> () -> Void in
                    { store.playRemote(song, in: songs, from: context, context: modelContext) }
                },
                onAction: onAction
            )
                .contextMenu {
                    if let startRadio {
                        Button {
                            startRadio(song)
                        } label: {
                            Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                    if let notInterested {
                        Button {
                            notInterested(song)
                        } label: {
                            Label("Not Interested", systemImage: "hand.thumbsdown")
                        }
                    }
                }
        }
    }
}

private struct RemoteSongRow: View {
    let song: SongResult
    let inLibrary: Bool
    // Set in Discover lists: play in the player instead of previewing.
    let play: (() -> Void)?
    let onAction: ((SongResult, String) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var preview: PreviewPlayer
    @EnvironmentObject private var player: LocalPlayer

    private var isCurrent: Bool { play != nil && player.current?.youtubeID == song.id }

    var body: some View {
        HStack(spacing: 14) {
            // Streamed for display only; nothing here is saved.
            AsyncImage(url: song.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "music.note")
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.15))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .foregroundStyle(isCurrent ? Color.mint : .primary)
                    .lineLimit(2)
                Text([song.artist, song.duration, inLibrary ? "In library" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.downloadingSongID == song.id {
                    ProgressView(value: store.downloadProgress ?? 0)
                    Text(store.downloadProgress.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let play {
                Button {
                    if isCurrent {
                        player.togglePlayback()
                    } else {
                        onAction?(song, "previewed")
                        play()
                    }
                } label: {
                    if isCurrent && player.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: isCurrent && player.isPlaying ? "pause.circle" : "play.circle")
                            .font(.title2)
                    }
                }
                .frame(width: 32)
                .accessibilityLabel(isCurrent && player.isPlaying ? "Pause" : "Play")
            } else {
                Button {
                    if preview.songID != song.id { onAction?(song, "previewed") }
                    store.togglePreview(song)
                } label: {
                    if preview.songID == song.id && preview.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: preview.songID == song.id ? "stop.circle" : "play.circle")
                            .font(.title2)
                    }
                }
                .frame(width: 32)
                .accessibilityLabel(preview.songID == song.id ? "Stop preview" : "Preview")
            }
            if inLibrary {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                    .accessibilityLabel("In library")
            } else if store.downloadingSongID != song.id {
                Button {
                    onAction?(song, "downloaded")
                    store.download(song, in: modelContext)
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title2)
                }
                .frame(width: 32)
                .disabled(store.isDownloading)
                .accessibilityLabel("Download")
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
    }
}

// Streams a search result without saving it.
@MainActor
final class PreviewPlayer: ObservableObject {
    @Published private(set) var songID: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    func toggle(_ song: SongResult) {
        if songID == song.id {
            stop()
        } else {
            start(song)
        }
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        songID = nil
        isLoading = false
    }

    private func start(_ song: SongResult) {
        stop()
        songID = song.id
        isLoading = true
        Task { @MainActor in
            do {
                let asset = try await YouTubeSource.previewAsset(videoID: song.id)
                // Stopped, or another song picked, while the link loaded.
                guard songID == song.id else { return }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                let item = AVPlayerItem(asset: asset)
                statusObservation = item.observe(\.status) { [weak self] item, _ in
                    let status = item.status
                    let details = item.error?.localizedDescription ?? "unknown"
                    Task { @MainActor [weak self] in
                        guard let self, self.songID == song.id else { return }
                        if status == .readyToPlay {
                            self.isLoading = false
                        } else if status == .failed {
                            self.stop()
                            self.errorMessage = "This preview couldn’t play. You can still download the song.\n\nDetails: \(details)"
                        }
                    }
                }
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.stop() }
                }
                let player = AVPlayer(playerItem: item)
                self.player = player
                player.play()
            } catch {
                guard songID == song.id else { return }
                stop()
                errorMessage = YouTubeSource.describe(error)
            }
        }
    }
}

struct SongResult: Identifiable, Hashable, Codable, Sendable {
    let id: String // YouTube video ID
    let title: String
    let artist: String?
    let duration: String?
    let thumbnailURL: URL? // small, for search rows
    let artworkURL: URL? // large, saved with downloads
}

struct SongPage: Sendable {
    let songs: [SongResult]
    let continuation: String?
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
    static func searchSongs(_ query: String) async throws -> SongPage {
        let json = try await musicRequest("search", body: [
            "query": query,
            "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF" // Songs filter
        ])
        let tabs = dig(json, "contents", "tabbedSearchResultsRenderer", "tabs") as? [Any]
        let sections = dig(tabs?.first, "tabRenderer", "content", "sectionListRenderer", "contents") as? [Any] ?? []
        let shelves = sections.compactMap { dig($0, "musicShelfRenderer") }
        return SongPage(
            songs: shelves.flatMap { dig($0, "contents") as? [Any] ?? [] }.compactMap(parseSong),
            continuation: shelves.lazy.compactMap(continuationToken).first
        )
    }

    // The next page of a search, for infinite scrolling.
    static func moreSongs(_ continuation: String) async throws -> SongPage {
        let token = continuation.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? continuation
        let json = try await musicRequest("search", urlSuffix: "&ctoken=\(token)&continuation=\(token)", body: [:])
        let shelf = dig(json, "continuationContents", "musicShelfContinuation")
        return SongPage(
            songs: (dig(shelf, "contents") as? [Any] ?? []).compactMap(parseSong),
            continuation: shelf.flatMap(continuationToken)
        )
    }

    private static func continuationToken(_ shelf: Any) -> String? {
        let continuations = dig(shelf, "continuations") as? [Any]
        return dig(continuations?.first, "nextContinuationData", "continuation") as? String
    }

    // A request to one of YouTube Music's web endpoints (search, browse, next).
    static func musicRequest(_ endpoint: String, urlSuffix: String = "", body extraBody: [String: Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false\(urlSuffix)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        if !model.visitorData.isEmpty {
            request.setValue(model.visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        var body = extraBody
        body["context"] = ["client": [
            "clientName": "WEB_REMIX",
            "clientVersion": musicClientVersion(),
            "hl": model.selectedLocaleLanguageCode,
            "gl": Locale.current.region?.identifier ?? "US" // charts and new releases for your country
        ]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status), let json = try? JSONSerialization.jsonObject(with: data) else {
            throw SourceError(errorDescription: "YouTube Music didn’t respond (HTTP \(status)). Try again in a moment.")
        }
        // Downloads without a visitor ID hit YouTube's bot check, reported as "Login is required".
        // Keep the first one so searches stay consistent.
        if model.visitorData.isEmpty, let visitorData = dig(json, "responseContext", "visitorData") as? String {
            model.visitorData = visitorData
        }
        return json
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
    // Album rows have no artist column, so only the title column is required.
    static func parseSong(_ item: Any) -> SongResult? {
        guard let renderer = dig(item, "musicResponsiveListItemRenderer"),
              let columns = dig(renderer, "flexColumns") as? [Any], !columns.isEmpty
        else { return nil }
        let titleRuns = dig(columns[0], "musicResponsiveListItemFlexColumnRenderer", "text", "runs") as? [Any] ?? []
        let detailRuns = columns.count > 1
            ? dig(columns[1], "musicResponsiveListItemFlexColumnRenderer", "text", "runs") as? [Any] ?? []
            : []
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
        // Playlist rows keep the length in a separate column.
        let fixedColumns = dig(renderer, "fixedColumns") as? [Any]
        duration = duration ?? text(dig(fixedColumns?.first, "musicResponsiveListItemFixedColumnRenderer", "text"))
        let thumbnails = dig(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails") as? [Any]
        let thumbnail = dig(thumbnails?.last, "url") as? String
        return SongResult(
            id: videoID,
            title: title,
            artist: artists.isEmpty ? nil : artists.joined(separator: ", "),
            duration: duration,
            thumbnailURL: thumbnail.flatMap { URL(string: $0) },
            artworkURL: thumbnail.flatMap(largeArtwork)
        )
    }

    // Thumbnails are about 120px; the same image is served larger by changing its size suffix.
    static func largeArtwork(_ thumbnail: String) -> URL? {
        URL(string: thumbnail.replacingOccurrences(of: #"=w\d+-h\d+"#, with: "=w544-h544", options: .regularExpression))
    }

    // The visible text of a YouTube Music text object, which is split into runs.
    static func text(_ value: Any?) -> String? {
        let runs = dig(value, "runs") as? [Any] ?? []
        let joined = runs.compactMap { dig($0, "text") as? String }.joined()
        return joined.isEmpty ? nil : joined
    }

    static func dig(_ value: Any?, _ keys: String...) -> Any? {
        keys.reduce(value) { ($0 as? [String: Any])?[$1] }
    }

    // Download a song by video ID. Without a known title (a re-download), use YouTube's video title.
    static func download(
        videoID: String,
        title: String? = nil,
        artist: String? = nil,
        artworkURL: URL? = nil,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SavedAudio {
        try await withTimeout(downloadTimeout, discardLate: AudioFiles.discard) {
            var saved = try await download(YTVideo(videoId: videoID), title: title, artist: artist, onProgress: onProgress)
            // Cover art is optional; fall back to the video thumbnail.
            let fallback = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
            if let url = artworkURL ?? fallback {
                saved.artworkFilename = await fetchArtwork(from: url)
            }
            return saved
        }
    }

    // A download that stalls, e.g. after iOS paused Freeify while the phone was locked, is
    // given up so Download All can move on. Generous enough for a slow cellular connection.
    private static let downloadTimeout: Duration = .seconds(180)

    // Runs `operation`, throwing if it takes longer than `limit`. A result that arrives too
    // late goes to `discardLate`, so its files don't linger.
    private static func withTimeout<T: Sendable>(
        _ limit: Duration,
        discardLate: @escaping @Sendable (T) -> Void,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation)
            let work = Task {
                do {
                    let value = try await operation()
                    if !gate.resume(with: .success(value)) { discardLate(value) }
                } catch {
                    _ = gate.resume(with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: limit)
                let stalled = SourceError(errorDescription: "The download stalled and was skipped. Try it again.")
                if gate.resume(with: .failure(stalled)) { work.cancel() }
            }
        }
    }

    private static func fetchArtwork(from url: URL) async -> String? {
        guard let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              UIImage(data: result.0) != nil
        else { return nil }
        return try? AudioFiles.saveArtwork(result.0)
    }

    // YouTube's best AAC (audio/mp4) stream; AVAudioPlayer can't play its WebM/Opus formats.
    private static func audioStream(
        for video: YTVideo
    ) async throws -> (infos: VideoInfosWithDownloadFormatsResponse, format: AudioOnlyFormat, url: URL) {
        let infos = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: model)
        let format = infos.downloadFormats
            .compactMap { $0 as? AudioOnlyFormat }
            .filter { $0.mimeType == "audio/mp4" && $0.url != nil && !$0.isDrc }
            .max { ($0.averageBitrate ?? 0) < ($1.averageBitrate ?? 0) }
        guard let format, let url = format.url else {
            let found = Set(infos.downloadFormats.compactMap { $0.mimeType }).sorted().joined(separator: ", ")
            throw SourceError(errorDescription: "YouTube has no audio Freeify can play for this song. Try another version of it.\n\nDetails: formats \(found.isEmpty ? "none" : found)")
        }
        return (infos, format, url)
    }

    // A streamable asset for previews, sent with the same User-Agent as downloads.
    static func previewAsset(videoID: String) async throws -> AVURLAsset {
        let url = try await audioStream(for: YTVideo(videoId: videoID)).url
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent]])
    }

    private static func download(
        _ video: YTVideo,
        title: String?,
        artist: String?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SavedAudio {
        let (infos, format, url) = try await audioStream(for: video)
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

    // Resumes a continuation once, from whichever task finishes first.
    private final class ResumeGate<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<T, Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard let continuation else { return false }
            self.continuation = nil
            continuation.resume(with: result)
            return true
        }
    }

    struct SourceError: LocalizedError {
        let errorDescription: String?
    }
}
