import Foundation

// A playlist or album on a YouTube Music browse page.
struct BrowseCard: Identifiable, Hashable, Sendable {
    let id: String // browse ID of its page: "VL…" for playlists, "MPRE…" for albums
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

// A Moods & genres tile, which opens a page of playlists.
struct MoodTile: Identifiable, Hashable, Sendable {
    let id: String // params for its category page
    let title: String
}

// YouTube Music pages for Discover: song radio, charts, new releases, and moods.
// Items are collected wherever they appear on a page, so a small layout change
// doesn't break a row.
extension YouTubeSource {
    // Songs like one song, from YouTube Music's song radio. The song itself is left out.
    static func radio(for videoID: String) async throws -> [SongResult] {
        let json = try await musicRequest("next", body: [
            "videoId": videoID,
            "playlistId": "RDAMVM\(videoID)",
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true
        ])
        var seen: Set<String> = [videoID]
        return collect("playlistPanelVideoRenderer", in: json)
            .compactMap(parseRadioSong)
            .filter { seen.insert($0.id).inserted }
    }

    static func charts() async throws -> [BrowseCard] {
        try await cards(browseID: "FEmusic_charts")
    }

    static func newReleases() async throws -> [BrowseCard] {
        try await cards(browseID: "FEmusic_new_releases_albums")
    }

    static func moods() async throws -> [MoodTile] {
        let json = try await musicRequest("browse", body: ["browseId": "FEmusic_moods_and_genres"])
        var seen = Set<String>()
        return collect("musicNavigationButtonRenderer", in: json).compactMap { button -> MoodTile? in
            guard let title = text(dig(button, "buttonText")),
                  let params = dig(button, "clickCommand", "browseEndpoint", "params") as? String,
                  seen.insert(params).inserted
            else { return nil }
            return MoodTile(id: params, title: title)
        }
    }

    static func playlists(for mood: MoodTile) async throws -> [BrowseCard] {
        try await cards(browseID: "FEmusic_moods_and_genres_category", params: mood.id)
    }

    // Songs on a playlist or album page. Album rows have no artist or art of their own,
    // so they use the album's.
    static func songs(in card: BrowseCard) async throws -> [SongResult] {
        let json = try await musicRequest("browse", body: ["browseId": card.id])
        let isAlbum = card.id.hasPrefix("MPRE")
        // Album subtitles read "Album • Artist" or "Single • Artist".
        let albumArtist = isAlbum ? card.subtitle.components(separatedBy: " • ").dropFirst().first : nil
        var seen = Set<String>()
        return collect("musicResponsiveListItemRenderer", in: json)
            .compactMap { parseSong(["musicResponsiveListItemRenderer": $0]) }
            .filter { seen.insert($0.id).inserted }
            .map { song in
                SongResult(
                    id: song.id,
                    title: song.title,
                    artist: song.artist ?? albumArtist,
                    duration: song.duration,
                    thumbnailURL: song.thumbnailURL ?? card.thumbnailURL,
                    artworkURL: song.artworkURL ?? card.thumbnailURL.flatMap { largeArtwork($0.absoluteString) }
                )
            }
    }

    // Playlist and album cards on a browse page. Other cards (artists, videos) are skipped.
    private static func cards(browseID: String, params: String? = nil) async throws -> [BrowseCard] {
        var body: [String: Any] = ["browseId": browseID]
        if let params { body["params"] = params }
        let json = try await musicRequest("browse", body: body)
        var seen = Set<String>()
        return collect("musicTwoRowItemRenderer", in: json).compactMap { item -> BrowseCard? in
            guard let id = dig(item, "navigationEndpoint", "browseEndpoint", "browseId") as? String,
                  id.hasPrefix("VL") || id.hasPrefix("MPRE"),
                  let title = text(dig(item, "title")),
                  seen.insert(id).inserted
            else { return nil }
            let thumbnails = collect("thumbnails", in: item).first as? [Any]
            let thumbnail = dig(thumbnails?.last, "url") as? String
            return BrowseCard(
                id: id,
                title: title,
                subtitle: text(dig(item, "subtitle")) ?? "",
                thumbnailURL: thumbnail.flatMap { URL(string: $0) }
            )
        }
    }

    private static func parseRadioSong(_ item: Any) -> SongResult? {
        guard let videoID = dig(item, "videoId") as? String, let title = text(dig(item, "title")) else { return nil }
        // Bylines read "Artist • Album • Year" or "Artist • 3.1B views • 18M likes".
        let byline = text(dig(item, "longBylineText"))?.components(separatedBy: " • ") ?? []
        let year = byline.dropFirst().compactMap { $0.count == 4 ? Int($0) : nil }.first
        let plays = byline.dropFirst().compactMap(playCount).first
        let thumbnails = dig(item, "thumbnail", "thumbnails") as? [Any]
        let thumbnail = dig(thumbnails?.last, "url") as? String
        return SongResult(
            id: videoID,
            title: title,
            artist: byline.first,
            duration: text(dig(item, "lengthText")),
            thumbnailURL: thumbnail.flatMap { URL(string: $0) },
            artworkURL: nil, // downloads fall back to the video thumbnail
            year: year,
            plays: plays
        )
    }

    // "3.1B views", "820K plays", or "1,234 views" as a number.
    private static func playCount(_ text: String) -> Double? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, parts[1] == "views" || parts[1] == "plays", var number = parts.first else { return nil }
        let scale: Double
        switch number.last {
        case "K": scale = 1e3
        case "M": scale = 1e6
        case "B": scale = 1e9
        default: scale = 1
        }
        if scale > 1 { number = number.dropLast() }
        return Double(number.replacingOccurrences(of: ",", with: "")).map { $0 * scale }
    }

    // Every value stored under `key`, anywhere in a JSON page, in page order.
    private static func collect(_ key: String, in value: Any) -> [Any] {
        var found: [Any] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let match = dictionary[key] { found.append(match) }
                for (name, child) in dictionary where name != key { walk(child) }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(value)
        return found
    }
}
