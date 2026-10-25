import SwiftData
import SwiftUI

// A Discover row's content, loaded separately so one failing page doesn't affect the others.
enum Loadable<Value> {
    case loading, loaded(Value), failed
}

@MainActor
struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: LibraryStore
    @Query(DiscoverView.recentListens) private var listens: [ListenEvent]
    @Query private var tracks: [Track]
    @State private var madeForYou: Loadable<[Mix]> = .loading
    @State private var charts: Loadable<[BrowseCard]> = .loading
    @State private var newReleases: Loadable<[BrowseCard]> = .loading
    @State private var moods: Loadable<[MoodTile]> = .loading

    private static var recentListens: FetchDescriptor<ListenEvent> {
        var descriptor = FetchDescriptor<ListenEvent>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        return descriptor
    }

    // Downloaded songs, most recently played first, each listed once.
    private var recentlyPlayed: [Track] {
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return listens
            .compactMap { byID[$0.trackID] }
            .filter { $0.isDownloaded && seen.insert($0.id).inserted }
            .prefix(15)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    recentlyPlayedRow
                    madeForYouRow
                    cardRow("Charts", charts)
                    cardRow("New releases", newReleases)
                    moodsGrid
                }
                .padding(.vertical)
            }
            .navigationTitle("Discover")
            .navigationDestination(for: BrowseCard.self) { card in
                CardSongsView(card: card)
            }
            .navigationDestination(for: MoodTile.self) { mood in
                MoodView(mood: mood)
            }
            .navigationDestination(for: Mix.self) { mix in
                MixView(mix: mix)
            }
            .task { await load(refreshMixes: false) }
            .refreshable { await load(refreshMixes: true) }
        }
    }

    @ViewBuilder
    private var recentlyPlayedRow: some View {
        let recent = recentlyPlayed
        if !recent.isEmpty {
            DiscoverSection(title: "Recently played") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(recent) { track in
                            Button {
                                store.select(track, in: recent, from: "recent", context: modelContext)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(track: track, size: 120)
                                    Text(track.title).font(.subheadline).lineLimit(1)
                                    Text(track.artist ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var madeForYouRow: some View {
        DiscoverSection(title: "Made for you") {
            switch madeForYou {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                RowUnavailable()
            case .loaded(let mixes) where mixes.isEmpty:
                Text("Play, like, or download a few songs from YouTube Music, then pull down to get mixes made for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            case .loaded(let mixes):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(mixes) { mix in
                            NavigationLink(value: mix) {
                                MixCard(mix: mix)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func cardRow(_ title: String, _ state: Loadable<[BrowseCard]>) -> some View {
        DiscoverSection(title: title) {
            switch state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                RowUnavailable()
            case .loaded(let cards):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(cards) { card in
                            NavigationLink(value: card) {
                                CardView(card: card, size: 140)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var moodsGrid: some View {
        DiscoverSection(title: "Moods & genres") {
            switch moods {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                RowUnavailable()
            case .loaded(let tiles):
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles) { mood in
                        NavigationLink(value: mood) {
                            Text(mood.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .leading) {
                                    // YouTube Music's stripe color for the tile.
                                    UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                                        .fill(mood.color.map(Color.init(argb:)) ?? Color.mint)
                                        .frame(width: 6)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func load(refreshMixes: Bool) async {
        async let mixes = try? MadeForYou.mixes(in: modelContext, refresh: refreshMixes)
        async let chartCards = try? YouTubeSource.charts()
        async let releaseCards = try? YouTubeSource.newReleases()
        async let moodTiles = try? YouTubeSource.moods()
        let (loadedMixes, loadedCharts, loadedReleases, loadedMoods) = await (mixes, chartCards, releaseCards, moodTiles)
        madeForYou = loadedMixes.map { .loaded($0) } ?? .failed
        charts = loadedCharts.map { .loaded($0) } ?? .failed
        newReleases = loadedReleases.map { .loaded($0) } ?? .failed
        moods = loadedMoods.map { .loaded($0) } ?? .failed
    }
}

struct DiscoverSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)
            content
        }
    }
}

private struct RowUnavailable: View {
    var body: some View {
        Text("Couldn’t load from YouTube Music. Pull down to try again.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }
}

// A playlist or album cover with its title. Streamed for display only; nothing is saved.
struct CardView: View {
    let card: BrowseCard
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: card.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(card.title).font(.subheadline).lineLimit(2)
            Text(card.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size, alignment: .leading)
    }
}

// A "Made for you" mix: the first song's cover with the mix name over it.
private struct MixCard: View {
    let mix: Mix

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: mix.songs.first?.artworkURL ?? mix.songs.first?.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.mint.opacity(0.3)
            }
            .frame(width: 140, height: 140)
            .overlay(alignment: .bottomLeading) {
                Text(mix.id == "discover" ? "Discover" : "Mix")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.mint, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(mix.title).font(.subheadline).lineLimit(2)
            Text(mix.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 140, alignment: .leading)
    }
}

// A mix's songs. What you do with them is recorded as feedback for recommendations.
struct MixView: View {
    let mix: Mix
    @Environment(\.modelContext) private var modelContext
    @State private var hidden = Set<String>()
    @State private var radioSeed: SongResult?

    var body: some View {
        List {
            RemoteSongRows(
                songs: mix.songs.filter { !hidden.contains($0.id) },
                startRadio: { radioSeed = $0 },
                onAction: { song, action in
                    MadeForYou.record(action, song: song, in: mix, context: modelContext)
                },
                notInterested: { song in
                    MadeForYou.record("dismissed", song: song, in: mix, context: modelContext)
                    hidden.insert(song.id)
                }
            )
        }
        .navigationTitle(mix.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $radioSeed) { seed in
            RadioView(seed: seed)
        }
    }
}

// The songs on a chart, playlist, or album.
struct CardSongsView: View {
    let card: BrowseCard

    var body: some View {
        RemoteSongsScreen(title: card.title) {
            try await YouTubeSource.songs(in: card)
        }
    }
}

// Songs like one song, from YouTube Music's song radio.
struct RadioView: View {
    let seed: SongResult

    var body: some View {
        RemoteSongsScreen(title: "\(seed.title) Radio") {
            try await YouTubeSource.radio(for: seed.id)
        }
    }
}

// A loaded list of YouTube Music songs, with preview, download, and Start Radio.
private struct RemoteSongsScreen: View {
    let title: String
    let load: () async throws -> [SongResult]
    @State private var songs: Loadable<[SongResult]> = .loading
    @State private var radioSeed: SongResult?

    var body: some View {
        Group {
            switch songs {
            case .loading:
                ProgressView()
            case .failed:
                ContentUnavailableView {
                    Label("Couldn’t load songs", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("YouTube Music didn’t respond. Check your connection and try again.")
                } actions: {
                    Button("Try Again") { Task { await reload() } }
                }
            case .loaded(let list):
                List {
                    RemoteSongRows(songs: list) { radioSeed = $0 }
                }
                .overlay {
                    if list.isEmpty {
                        ContentUnavailableView("No songs here", systemImage: "music.note")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $radioSeed) { seed in
            RadioView(seed: seed)
        }
        .task { await reload() }
    }

    private func reload() async {
        songs = .loading
        songs = (try? await load()).map { .loaded($0) } ?? .failed
    }
}

// The playlists for one mood or genre.
struct MoodView: View {
    let mood: MoodTile
    @State private var playlists: Loadable<[BrowseCard]> = .loading

    var body: some View {
        ScrollView {
            switch playlists {
            case .loading:
                ProgressView().padding(.top, 40)
            case .failed:
                RowUnavailable().padding(.top, 40)
            case .loaded(let cards):
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                    ForEach(cards) { card in
                        NavigationLink(value: card) {
                            CardView(card: card, size: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(mood.title)
        .task {
            if case .loaded = playlists { return }
            playlists = (try? await YouTubeSource.playlists(for: mood)).map { .loaded($0) } ?? .failed
        }
        .refreshable {
            playlists = (try? await YouTubeSource.playlists(for: mood)).map { .loaded($0) } ?? .failed
        }
    }
}

extension Color {
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: 1
        )
    }
}
