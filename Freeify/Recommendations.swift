import Foundation
import SwiftData

// "Made for you": YouTube Music suggests candidate songs from radios of your top songs,
// and Freeify ranks them using what you play on the phone. Nothing here leaves the phone
// except the seed songs' video IDs, which YouTube Music sees as radio requests.

// What you seem to like, from listening history, likes, and the songs you've saved.
struct TasteProfile {
    private(set) var artistScores: [String: Double] = [:]
    private(set) var songScores: [String: Double] = [:] // by YouTube video ID
    private(set) var songNames: [String: (title: String, artist: String?)] = [:]

    init(listens: [ListenEvent], tracks: [Track], now: Date = .now) {
        for listen in listens {
            // A listen counts half as much every 30 days.
            let days = now.timeIntervalSince(listen.startedAt) / 86_400
            let recency = pow(0.5, days / 30)
            let value: Double = listen.finished ? 1 : (listen.secondsListened < 30 ? -0.5 : 0.5)
            add(value * recency, artist: listen.artist, videoID: listen.youtubeID, title: listen.title)
        }
        for track in tracks {
            add(track.likedAt == nil ? 1 : 4, artist: track.artist, videoID: track.youtubeID, title: track.title)
        }
    }

    // How much you like an artist, from -1 to 1 relative to your favorite.
    func affinity(for artist: String?) -> Double {
        guard let key = Self.artistKey(artist), let score = artistScores[key],
              let top = artistScores.values.max(), top > 0
        else { return 0 }
        return max(-1, min(1, score / top))
    }

    // Your top songs from YouTube, rotated daily so the mixes change.
    func seeds(count: Int, day: Int) -> [SongResult] {
        let top = songScores
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(count * 3)
            .map { $0.key }
        guard !top.isEmpty else { return [] }
        let start = (day * count) % top.count
        return (0..<min(count, top.count)).map { offset in
            let id = top[(start + offset) % top.count]
            let name = songNames[id]
            return SongResult(id: id, title: name?.title ?? "", artist: name?.artist,
                              duration: nil, thumbnailURL: nil, artworkURL: nil)
        }
    }

    // Songs list artists as "A, B"; the first one is the main artist.
    static func artistKey(_ artist: String?) -> String? {
        guard let main = artist?.components(separatedBy: ", ").first?.lowercased(), !main.isEmpty else { return nil }
        return main
    }

    private mutating func add(_ value: Double, artist: String?, videoID: String?, title: String) {
        if let key = Self.artistKey(artist) { artistScores[key, default: 0] += value }
        if let videoID {
            songScores[videoID, default: 0] += value
            songNames[videoID] = (title, artist)
        }
    }
}

// A song suggested by one or more seed radios.
struct Candidate {
    let song: SongResult
    var seedIDs: Set<String>
    var bestPosition: Int // its highest place in any radio, 0 = first
}

// Ranks candidates with the hand-set or learned weights (Ranker.swift). Every song's
// features are saved with its recommendation events, for training.
enum Recommender {
    static func features(for candidate: Candidate, profile: TasteProfile) -> [Double] {
        var features = [Double](repeating: 0, count: RankingFeature.count)
        features[RankingFeature.affinity] = profile.affinity(for: candidate.song.artist)
        features[RankingFeature.seeds] = Double(candidate.seedIDs.count)
        features[RankingFeature.radioPosition] = 1 - Double(min(candidate.bestPosition, 50)) / 50
        let song = candidate.song
        if let text = song.duration {
            let seconds = text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
            features[RankingFeature.length] = min(max((seconds / 60 - 4) / 2, -2), 2)
        } else {
            features[RankingFeature.lengthMissing] = 1
        }
        if let year = song.year {
            let thisYear = Calendar.current.component(.year, from: .now)
            features[RankingFeature.age] = min(max(Double(thisYear - year) / 10, 0), 5)
        } else {
            features[RankingFeature.ageMissing] = 1
        }
        if let plays = song.plays, plays > 0 {
            features[RankingFeature.popularity] = min(max(log10(plays) - 7, -4), 3)
        } else {
            features[RankingFeature.popularityMissing] = 1
        }
        return features
    }

    // Highest scores first, with at most `perArtist` songs per artist. `explore` slots go to
    // random lower-ranked songs placed anywhere in the mix, so the ranker keeps seeing songs
    // it wouldn't pick and doesn't narrow into a rut.
    static func rank(
        _ candidates: [Candidate],
        profile: TasteProfile,
        weights: RankerWeights,
        limit: Int,
        perArtist: Int = 2,
        explore: Int = 2
    ) -> [(SongResult, [Double])] {
        var perArtistCount: [String: Int] = [:]
        let ranked = candidates
            .map { ($0.song, features(for: $0, profile: profile)) }
            .sorted { weights.score($0.1) > weights.score($1.1) }
            .filter { song, _ in
                let key = TasteProfile.artistKey(song.artist) ?? song.id
                perArtistCount[key, default: 0] += 1
                return perArtistCount[key, default: 0] <= perArtist
            }
        let explored = min(explore, max(ranked.count - (limit - explore), 0))
        var mix = Array(ranked.prefix(limit - explored))
        for var pick in ranked.dropFirst(limit - explored).shuffled().prefix(explored) {
            pick.1[RankingFeature.explored] = 1
            mix.insert(pick, at: Int.random(in: 0...mix.count))
        }
        for index in mix.indices {
            mix[index].1[RankingFeature.mixPosition] = mix.count > 1 ? Double(index) / Double(mix.count - 1) : 0
        }
        return mix
    }
}

struct Mix: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let songs: [SongResult]
    let features: [[Double]] // one per song, for feedback
}

// One thing you did with a recommendation. Training data for the learned ranker.
@Model
final class RecommendationEvent {
    var youtubeID: String
    var mix: String
    // shown, previewed, downloaded, liked, or dismissed ("Not interested")
    var action: String
    var features: [Double]
    var at: Date

    init(youtubeID: String, mix: String, action: String, features: [Double]) {
        self.youtubeID = youtubeID
        self.mix = mix
        self.action = action
        self.features = features
        at = Date()
    }
}

enum MadeForYou {
    private static let seedCount = 3

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("made-for-you.json")
    }

    private struct Cache: Codable {
        let day: Int
        let mixes: [Mix]
    }

    // Days count from your local midnight, so mixes change overnight wherever you are.
    static var today: Int { Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0 }

    // Today's mixes, from the saved copy when there is one, so they also show offline.
    @MainActor
    static func mixes(in context: ModelContext, refresh: Bool = false) async throws -> [Mix] {
        if !refresh, let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.day == today {
            return cache.mixes
        }
        let mixes = try await generate(in: context)
        if let data = try? JSONEncoder().encode(Cache(day: today, mixes: mixes)) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        for mix in mixes {
            for (song, features) in zip(mix.songs, mix.features) {
                context.insert(RecommendationEvent(youtubeID: song.id, mix: mix.id, action: "shown", features: features))
            }
        }
        try? context.save()
        return mixes
    }

    @MainActor
    private static func generate(in context: ModelContext) async throws -> [Mix] {
        let tracks = try context.fetch(FetchDescriptor<Track>())
        var listenHistory = FetchDescriptor<ListenEvent>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        listenHistory.fetchLimit = 2_000
        let listens = try context.fetch(listenHistory)
        let dismissed = Set(try context.fetch(FetchDescriptor<RecommendationEvent>(
            predicate: #Predicate { $0.action == "dismissed" }
        )).map { $0.youtubeID })

        let profile = TasteProfile(listens: listens, tracks: tracks)
        let weights = Ranker.update(in: context, today: today)
        let seeds = profile.seeds(count: seedCount, day: today)
        guard !seeds.isEmpty else { return [] }

        // Radios for every seed, gathered into one candidate per song.
        let excluded = dismissed.union(tracks.compactMap { $0.youtubeID })
        var radios: [(seed: SongResult, songs: [SongResult])] = []
        for seed in seeds {
            if let songs = try? await YouTubeSource.radio(for: seed.id) {
                radios.append((seed, songs))
            }
        }
        guard !radios.isEmpty else { throw YouTubeSource.SourceError(errorDescription: "YouTube Music didn’t respond.") }
        var candidates: [String: Candidate] = [:]
        for (seed, songs) in radios {
            for (position, song) in songs.enumerated() where !excluded.contains(song.id) {
                var candidate = candidates[song.id] ?? Candidate(song: song, seedIDs: [], bestPosition: position)
                candidate.seedIDs.insert(seed.id)
                candidate.bestPosition = min(candidate.bestPosition, position)
                candidates[song.id] = candidate
            }
        }

        var mixes: [Mix] = []
        for (seed, _) in radios {
            let ranked = Recommender.rank(
                candidates.values.filter { $0.seedIDs.contains(seed.id) }, profile: profile, weights: weights, limit: 20
            )
            guard !ranked.isEmpty else { continue }
            mixes.append(Mix(
                id: "seed-\(seed.id)",
                title: "Mix from \(seed.title)",
                subtitle: seed.artist ?? "",
                songs: ranked.map { $0.0 },
                features: ranked.map { $0.1 }
            ))
        }
        // Discover mix: artists you don't have yet.
        let knownArtists = Set(tracks.compactMap { TasteProfile.artistKey($0.artist) })
        let fresh = candidates.values.filter { TasteProfile.artistKey($0.song.artist).map { !knownArtists.contains($0) } ?? true }
        let discover = Recommender.rank(Array(fresh), profile: profile, weights: weights, limit: 25, perArtist: 1, explore: 3)
        if !discover.isEmpty {
            mixes.append(Mix(
                id: "discover",
                title: "Discover Mix",
                subtitle: "New artists for you",
                songs: discover.map { $0.0 },
                features: discover.map { $0.1 }
            ))
        }
        return mixes
    }

    // Record what you did with a recommended song.
    @MainActor
    static func record(_ action: String, song: SongResult, in mix: Mix, context: ModelContext) {
        let features = mix.songs.firstIndex(of: song).map { mix.features[$0] } ?? []
        context.insert(RecommendationEvent(youtubeID: song.id, mix: mix.id, action: action, features: features))
        try? context.save()
    }
}
