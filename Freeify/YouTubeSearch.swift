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
                            Button("Couldn’t load more · Retry") { loadMore() }
                                .foregroundStyle(Palette.hair)
                                .frame(minHeight: Spacing.target)
                        } else {
                            ProgressView()
                                .tint(Palette.activity)
                                .onAppear { loadMore() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .themedRow()
                }
            }
            .themedList()
            .overlay {
                if isSearching {
                    ProgressView("Searching…").tint(Palette.activity)
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
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        // Video IDs already in the library, so the same song isn't downloaded twice.
        let libraryIDs = Set(tracks.compactMap { $0.youtubeID })
        ForEach(songs) { song in
            HStack(spacing: 0) {
                RemoteSongRow(
                    song: song,
                    inLibrary: libraryIDs.contains(song.id),
                    play: playContext.map { context -> () -> Void in
                        { store.playRemote(song, in: songs, from: context, context: modelContext) }
                    },
                    onAction: onAction
                )
                if startRadio != nil || notInterested != nil {
                    Menu {
                        menuItems(for: song)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: Spacing.target, height: Spacing.target)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More for \(song.title)")
                }
            }
            .themedRow(current: playContext != nil && player.current?.youtubeID == song.id)
            .contextMenu { menuItems(for: song) }
        }
    }

    @ViewBuilder
    private func menuItems(for song: SongResult) -> some View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCurrent: Bool { play != nil && player.current?.youtubeID == song.id }

    var body: some View {
        HStack(spacing: Spacing.m) {
            // Streamed for display only; nothing here is saved.
            AsyncImage(url: song.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkPlaceholder(size: Spacing.thumbnail)
            }
            .frame(width: Spacing.thumbnail, height: Spacing.thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(song.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text([song.artist, song.duration].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                if store.downloadingSongID == song.id {
                    StatusChip(
                        label: store.downloadProgress.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…",
                        systemImage: "arrow.down.circle",
                        kind: .downloading
                    )
                } else if inLibrary {
                    StatusChip(label: "Saved", systemImage: "checkmark", kind: .saved)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            // One quick check transition when a download completes; none with Reduce Motion.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: inLibrary)
            Spacer(minLength: Spacing.s)
            if isCurrent {
                PlayingIndicator(isPlaying: player.isPlaying)
            }
            playButton
            if !inLibrary && store.downloadingSongID != song.id {
                Button {
                    onAction?(song, "downloaded")
                    store.download(song, in: modelContext)
                } label: {
                    GlyphView(path: ThemeGlyph.download, size: 22)
                        .foregroundStyle(store.isDownloading ? Palette.textMuted : Palette.textPrimary)
                        .frame(width: Spacing.target, height: Spacing.target)
                        .contentShape(Rectangle())
                }
                .disabled(store.isDownloading)
                .accessibilityLabel("Download \(song.title)")
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, Spacing.m)
    }

    // Discover lists play in the player; search previews. Both use the small round housing.
    @ViewBuilder
    private var playButton: some View {
        let active = play != nil ? isCurrent : preview.songID == song.id
        let loading = play != nil ? isCurrent && player.isLoading : active && preview.isLoading
        let symbol = play != nil
            ? (isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
            : (active ? "stop.fill" : "play.fill")
        Button {
            if let play {
                if isCurrent {
                    player.togglePlayback()
                } else {
                    onAction?(song, "previewed")
                    play()
                }
            } else {
                if !active { onAction?(song, "previewed") }
                store.togglePreview(song)
            }
        } label: {
            ZStack {
                Circle().fill(Palette.action)
                if loading {
                    ProgressView().tint(Palette.inkOnAccent)
                } else {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.inkOnAccent)
                }
            }
            .frame(width: 34, height: 34)
            .frame(width: Spacing.target, height: Spacing.target)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(play != nil
            ? (isCurrent && player.isPlaying ? "Pause \(song.title)" : "Play \(song.title)")
            : (active ? "Stop preview" : "Preview \(song.title)"))
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
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func toggle(_ song: SongResult) {
        if songID == song.id {
            stop()
        } else {
            start(song)
        }
    }

    func stop() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
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
        errorMessage = nil
        let requestGeneration = generation
        songID = song.id
        isLoading = true
        loadTask = Task { @MainActor in
            do {
                let (asset, loudness) = try await YouTubeSource.previewAsset(videoID: song.id)
                // Stopped, or another song picked, while the link loaded.
                try Task.checkCancellation()
                guard requestGeneration == generation else { return }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                let item = AVPlayerItem(asset: asset)
                statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    let status = item.status
                    let details = item.error?.localizedDescription ?? "unknown"
                    Task { @MainActor [weak self] in
                        guard let self, requestGeneration == self.generation else { return }
                        if status == .readyToPlay {
                            self.isLoading = false
                        } else if status == .failed {
                            self.stop()
                            self.errorMessage = "This preview couldn’t play. Downloads may also be affected.\n\nDetails: \(details)"
                        }
                    }
                }
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, requestGeneration == self.generation else { return }
                        self.stop()
                    }
                }
                let player = AVPlayer(playerItem: item)
                player.volume = VolumeMatch.volume(forLoudness: loudness)
                self.player = player
                player.play()
            } catch {
                guard !Task.isCancelled, requestGeneration == generation else { return }
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
    var year: Int? = nil // release year and YouTube plays, where a radio lists them
    var plays: Double? = nil
}

struct SongPage: Sendable {
    let songs: [SongResult]
    let continuation: String?
}

enum YouTubeSource {
    // Client settings follow yt-dlp's visionos client.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    // Current configurations: https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py
    // Only direct AAC URLs are accepted. Ciphered, DRM, and SABR-only formats are not supported.
    private enum PlaybackClient: String, CaseIterable {
        case visionOS = "visionOS"
        case tv = "TV"

        var headerID: String { self == .visionOS ? "101" : "7" }
        var userAgent: String {
            self == .visionOS ? YouTubeSource.userAgent
                : "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version"
        }
        var context: [String: String] {
            if self == .tv {
                return ["clientName": "TVHTML5", "clientVersion": "5.20260707", "userAgent": userAgent]
            }
            return ["clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple",
                    "deviceModel": "RealityDevice17,1", "osName": "visionOS",
                    "osVersion": "26.5.23O471", "userAgent": userAgent]
        }

        static func shouldTryNext(_ error: Error, details: String) -> Bool {
            // Network failures, cancellation, and rate limits must not cause client cycling.
            if error is CancellationError || error is URLError { return false }
            let text = details.lowercased()
            if text.contains("429") || text.contains("too many requests") || text.contains("rate limit") { return false }
            if error is ClientAttemptError { return true }
            return text.contains("login is required") || text.contains("login_required")
                || text.contains("not a bot") || text.contains("sign in")
        }
    }

    private enum ClientAttemptError: LocalizedError {
        case retryable(String)
        var errorDescription: String? {
            switch self { case .retryable(let reason): return reason }
        }
    }

    private static let visitorSession = YouTubeVisitorSession()
    private static let languageCode = YouTubeModel().selectedLocaleLanguageCode

    // A model belongs to one lookup; concurrent requests cannot change its visitor ID.
    private static func makeModel(visitorData: String, client: PlaybackClient) throws -> YouTubeModel {
        let model = YouTubeModel()
        model.visitorData = visitorData
        var context = client.context
        context["visitorData"] = visitorData
        context["hl"] = languageCode
        let contextJSON = String(decoding: try JSONSerialization.data(withJSONObject: context), as: UTF8.self)
        // Header and body identify the same client and visitor for this attempt.
        model.customHeaders[.videoInfosWithDownloadFormats] = HeadersList(
            url: URL(string: "https://www.youtube.com/youtubei/v1/player")!,
            method: .POST,
            headers: [
                .init(name: "Content-Type", content: "application/json"),
                .init(name: "User-Agent", content: client.userAgent),
                .init(name: "Origin", content: "https://www.youtube.com"),
                .init(name: "X-Youtube-Client-Name", content: client.headerID),
                .init(name: "X-Youtube-Client-Version", content: client.context["clientVersion"]!)
            ],
            customHeaders: ["X-Goog-Visitor-Id": .visitorData],
            addQueryAfterParts: [.init(index: 0, encode: false, content: .query)],
            httpBody: [
                #"{"contentCheckOk":true,"racyCheckOk":true,"context":{"client":\#(contextJSON)},"playbackContext":{"contentPlaybackContext":{"html5Preference":"HTML5_PREF_WANTS"}},"videoId":""#,
                #""}"#
            ],
            parameters: [.init(name: "prettyPrint", content: "false")]
        )
        return model
    }

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
        try Task.checkCancellation()
        let visitorData = await visitorSession.current
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false\(urlSuffix)")!)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        if !visitorData.isEmpty {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        var body = extraBody
        var client: [String: Any] = [
            "clientName": "WEB_REMIX",
            "clientVersion": musicClientVersion(),
            "hl": languageCode,
            "gl": Locale.current.region?.identifier ?? "US" // charts and new releases for your country
        ]
        if !visitorData.isEmpty { client["visitorData"] = visitorData }
        body["context"] = ["client": client]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 {
            throw SourceError(errorDescription: "YouTube is limiting requests. Wait before trying again. Saved songs still play offline.")
        }
        guard (200...299).contains(status), let json = try? JSONSerialization.jsonObject(with: data) else {
            throw SourceError(errorDescription: "YouTube Music didn’t respond (HTTP \(status)). Try again in a moment.")
        }
        await visitorSession.record(dig(json, "responseContext", "visitorData") as? String, replacing: visitorData)
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
    ) async throws -> (infos: VideoInfosWithDownloadFormatsResponse, format: AudioOnlyFormat, url: URL, userAgent: String) {
        // Discover and saved recommendations can start playback before any search/browse.
        // Bootstrap through a normal public browse request, once for concurrent callers.
        let visitorData = try await visitorSession.prepare {
            let json = try await musicRequest("browse", body: ["browseId": "FEmusic_home"])
            return dig(json, "responseContext", "visitorData") as? String ?? ""
        }
        var failures: [String] = []
        for client in PlaybackClient.allCases {
            try Task.checkCancellation()
            do {
                let infos = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(
                    youtubeModel: makeModel(visitorData: visitorData, client: client)
                )
                try Task.checkCancellation()
                let format = infos.downloadFormats
                    .compactMap { $0 as? AudioOnlyFormat }
                    .filter { $0.mimeType == "audio/mp4" && $0.url != nil && !$0.isDrc }
                    .max { ($0.averageBitrate ?? 0) < ($1.averageBitrate ?? 0) }
                guard let format, let url = format.url else {
                    throw ClientAttemptError.retryable("No direct AAC audio URL")
                }
                // A format URL alone is not success: it can still require attestation.
                try await checkMediaAccess(url, userAgent: client.userAgent)
                return (infos, format, url, client.userAgent)
            } catch {
                try Task.checkCancellation()
                let details = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                guard PlaybackClient.shouldTryNext(error, details: details) else { throw error }
                failures.append("\(client.rawValue): \(details)")
            }
        }
        throw SourceError(errorDescription: "YouTube refused playback through the available clients. Sign-in or verification may still be required. Saved songs remain available offline.\n\nError code: CLIENTS_EXHAUSTED\n\nDetails: " + failures.joined(separator: "\n"))
    }

    private static func checkMediaAccess(_ url: URL, userAgent: String) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        defer { bytes.task.cancel() } // Never consume an entire song if Range is ignored.
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 {
            throw SourceError(errorDescription: "YouTube is limiting requests (HTTP 429). Wait before trying again.")
        }
        if status == 401 || status == 403 {
            throw ClientAttemptError.retryable("Audio access refused (HTTP \(status))")
        }
        guard (200...299).contains(status) else {
            throw SourceError(errorDescription: "YouTube audio did not respond (HTTP \(status)). Try again later.")
        }
        if response.mimeType?.contains("text/html") == true {
            throw ClientAttemptError.retryable("YouTube returned a web page instead of audio")
        }
    }

    // A streamable asset for previews, sent with the same User-Agent as downloads, and the
    // song's loudness for volume matching.
    static func previewAsset(videoID: String) async throws -> (asset: AVURLAsset, loudness: Double?) {
        let stream = try await audioStream(for: YTVideo(videoId: videoID))
        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": stream.userAgent]])
        return (asset, stream.format.loudness)
    }

    // A saved song's loudness, for songs downloaded before Freeify kept it. 0 when YouTube
    // doesn't list one, so the song isn't looked up again.
    static func loudness(videoID: String) async throws -> Double {
        try await audioStream(for: YTVideo(videoId: videoID)).format.loudness ?? 0
    }

    private static func download(
        _ video: YTVideo,
        title: String?,
        artist: String?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> SavedAudio {
        let (infos, format, url, selectedUserAgent) = try await audioStream(for: video)
        var request = URLRequest(url: url)
        request.setValue(selectedUserAgent, forHTTPHeaderField: "User-Agent")
        // YouTube throttles audio-only downloads that don't request an explicit range.
        if let length = format.contentLength {
            request.setValue("bytes=0-\(max(length - 1, 0))", forHTTPHeaderField: "Range")
        }
        // Read the audio as it arrives and count the bytes, so the progress bar moves during
        // the download rather than jumping from 0% to done.
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            bytes.task.cancel()
            throw SourceError(errorDescription: status == 403
                ? "YouTube refused the download (HTTP 403). YouTube may have changed how downloads work, so Freeify may need an update."
                : "The download failed (HTTP \(status)). Try again.")
        }
        let expected = format.contentLength.map { Int64($0) } ?? response.expectedContentLength
        let temporary = try await receive(bytes, expectedBytes: expected, onProgress: onProgress)

        let name = title.map { (title: $0, artist: artist) } ?? SongName.parse(
            infos.videoInfos.title ?? "Untitled",
            channel: infos.videoInfos.channel?.name
        )
        let loudness = format.loudness
        do {
            return try await Task.detached(priority: .userInitiated) {
                var saved = try AudioFiles.saveDownload(temporary, title: name.title, artist: name.artist, youtubeID: video.videoId)
                saved.loudness = loudness
                return saved
            }.value
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    // Writes a download to a temporary file in 64 KB pieces, reporting whole-percent steps.
    private static func receive(
        _ bytes: URLSession.AsyncBytes,
        expectedBytes: Int64,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            let pieceSize = 64 * 1024
            var piece = Data(capacity: pieceSize)
            var received: Int64 = 0
            var lastPercent = -1
            func flush() throws {
                try handle.write(contentsOf: piece)
                received += Int64(piece.count)
                piece.removeAll(keepingCapacity: true)
                guard expectedBytes > 0 else { return }
                let percent = Int(min(Double(received) / Double(expectedBytes), 1) * 100)
                if percent != lastPercent {
                    lastPercent = percent
                    onProgress(Double(percent) / 100)
                }
            }
            for try await byte in bytes {
                piece.append(byte)
                if piece.count >= pieceSize {
                    try Task.checkCancellation()
                    try flush()
                }
            }
            try flush()
            try handle.close()
            return temporary
        } catch {
            bytes.task.cancel()
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    // Plain messages for search and download failures. YouTubeKit errors aren't localized,
    // so their details follow in small print for diagnosing YouTube changes.
    static func describe(_ error: Error) -> String {
        if let error = error as? SourceError {
            return error.errorDescription ?? "Something went wrong."
        }
        if let error = error as? YouTubeVisitorSession.SessionError {
            return error.localizedDescription
        }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dataNotAllowed].contains(error.code) {
            return "Freeify couldn’t reach YouTube. Check your internet connection and try again.\n\nError code: URLError \(error.code.rawValue)"
        }
        let details = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        let message: String
        let code: String
        if details.localizedCaseInsensitiveContains("Login is required")
            || details.localizedCaseInsensitiveContains("LOGIN_REQUIRED")
            || details.localizedCaseInsensitiveContains("sign in")
            || details.localizedCaseInsensitiveContains("not a bot") {
            message = "YouTube requires sign-in or verification for this request. Freeify can’t complete that check. Open the song in YouTube to listen there, or try Freeify later. Saved songs still play offline."
            code = "LOGIN_REQUIRED"
        } else if details.localizedCaseInsensitiveContains("unavailable") {
            message = "This song isn’t available on YouTube right now. Try another version of it."
            code = "UNAVAILABLE"
        } else {
            message = "YouTube wouldn’t let Freeify get this song. Try again, or try another version of it."
            let error = error as NSError
            code = "\(error.domain) \(error.code)"
        }
        return "\(message)\n\nError code: \(code)\n\nDetails: \(details)"
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
