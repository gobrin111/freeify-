import Foundation
import SwiftUI
import YouTubeKit

@MainActor
struct YouTubeSearchView: View {
    let onDownloaded: ((title: String, filename: String)) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [YTVideo] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var downloadingID: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results, id: \.videoId) { video in
                Button {
                    download(video)
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.title ?? "Untitled")
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text([video.channel?.name, video.timeLength].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if downloadingID == video.videoId {
                            ProgressView()
                        } else {
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
                        Text("Shorts, live streams, and videos over 15 minutes are hidden. Try another search.")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("Search YouTube", systemImage: "magnifyingglass")
                    } description: {
                        Text("Find a song, then tap it to save an offline copy in Freeify.")
                    }
                }
            }
            .navigationTitle("Search YouTube")
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
                }
            }
            .disabled(downloadingID != nil)
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
        guard !text.isEmpty else { return }
        isSearching = true
        Task { @MainActor in
            defer { isSearching = false }
            do {
                results = try await YouTubeSource.search(text)
                hasSearched = true
            } catch {
                errorMessage = describe(error)
            }
        }
    }

    private func download(_ video: YTVideo) {
        downloadingID = video.videoId
        Task { @MainActor in
            defer { downloadingID = nil }
            do {
                try onDownloaded(try await YouTubeSource.download(video))
                dismiss()
            } catch {
                errorMessage = describe(error)
            }
        }
    }

    // YouTubeKit errors aren't localized; show their details while this path is being tested.
    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
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

    static func search(_ query: String) async throws -> [YTVideo] {
        let response = try await SearchResponse.sendThrowingRequest(youtubeModel: model, data: [.query: query])
        // Downloads without a visitor ID hit YouTube's bot check, reported as "Login is required".
        if let visitorData = response.visitorData, !visitorData.isEmpty {
            model.visitorData = visitorData
        }
        let videos = response.results.compactMap { $0 as? YTVideo }.filter(hasSongLength)
        // Keep YouTube's order within each group, with likely songs first.
        return videos.filter { looksLikeSong($0, query: query) } + videos.filter { !looksLikeSong($0, query: query) }
    }

    // Hide Shorts, live streams and premieres (no fixed length), and long videos like podcasts.
    private static func hasSongLength(_ video: YTVideo) -> Bool {
        guard let seconds = video.timeLengthSeconds, (60...900).contains(seconds) else { return false }
        return !(video.title ?? "").localizedCaseInsensitiveContains("#shorts")
    }

    private static func looksLikeSong(_ video: YTVideo, query: String) -> Bool {
        let title = video.title ?? ""
        let channel = video.channel?.name ?? ""
        return title.localizedCaseInsensitiveContains("audio")
            || title.localizedCaseInsensitiveContains("lyric")
            || channel.hasSuffix(" - Topic")
            || (!channel.isEmpty && query.localizedCaseInsensitiveContains(channel))
    }

    // Use YouTube's AAC (audio/mp4) stream; AVAudioPlayer can't play its WebM/Opus formats.
    static func download(_ video: YTVideo) async throws -> (title: String, filename: String) {
        let infos = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: model)
        let format = infos.downloadFormats
            .compactMap { $0 as? AudioOnlyFormat }
            .filter { $0.mimeType == "audio/mp4" && $0.url != nil && !$0.isDrc }
            .max { ($0.averageBitrate ?? 0) < ($1.averageBitrate ?? 0) }
        guard let format, let url = format.url else {
            let found = Set(infos.downloadFormats.compactMap { $0.mimeType }).sorted().joined(separator: ", ")
            throw SourceError(errorDescription: "No playable audio was found for this video (formats: \(found.isEmpty ? "none" : found)).")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // YouTube throttles audio-only downloads that don't request an explicit range.
        if let length = format.contentLength {
            request.setValue("bytes=0-\(length)", forHTTPHeaderField: "Range")
        }
        let (temporary, response) = try await URLSession.shared.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            try? FileManager.default.removeItem(at: temporary)
            throw SourceError(errorDescription: "YouTube refused the download (HTTP \(status)).")
        }

        let title = video.title ?? infos.videoInfos.title ?? "Untitled"
        do {
            return try await Task.detached(priority: .userInitiated) {
                try AudioFiles.saveDownload(temporary, title: title)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    struct SourceError: LocalizedError {
        let errorDescription: String?
    }
}
