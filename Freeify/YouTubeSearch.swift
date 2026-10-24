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
    private static let model = YouTubeModel()

    static func search(_ query: String) async throws -> [YTVideo] {
        let response = try await SearchResponse.sendThrowingRequest(youtubeModel: model, data: [.query: query])
        return response.results.compactMap { $0 as? YTVideo }
    }

    // Use YouTube's AAC (audio/mp4) stream; AVAudioPlayer can't play its WebM/Opus formats.
    static func download(_ video: YTVideo) async throws -> (title: String, filename: String) {
        let infos = try await video.fetchStreamingInfosWithDownloadFormatsThrowing(youtubeModel: model)
        let format = infos.downloadFormats
            .compactMap { $0 as? AudioOnlyFormat }
            .filter { $0.mimeType == "audio/mp4" && $0.url != nil && !$0.isDrc }
            .max { ($0.averageBitrate ?? 0) < ($1.averageBitrate ?? 0) }
        guard let format, let url = format.url else {
            throw SourceError(errorDescription: "No playable audio was found for this video.")
        }

        var request = URLRequest(url: url)
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
