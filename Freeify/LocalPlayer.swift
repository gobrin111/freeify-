import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

enum RepeatMode: String {
    case off, all, one
}

// Something the player can play: a saved song, or a YouTube Music song streamed without saving.
enum PlayItem: Identifiable {
    case track(Track)
    case stream(SongResult)

    var id: String {
        switch self {
        case .track(let track): track.id.uuidString
        case .stream(let song): "stream-\(song.id)"
        }
    }

    var title: String {
        switch self {
        case .track(let track): track.title
        case .stream(let song): song.title
        }
    }

    var artist: String? {
        switch self {
        case .track(let track): track.artist
        case .stream(let song): song.artist
        }
    }

    var youtubeID: String? {
        switch self {
        case .track(let track): track.youtubeID
        case .stream(let song): song.id
        }
    }

    var track: Track? {
        if case .track(let track) = self { return track }
        return nil
    }

    // Saved songs whose download was removed are skipped.
    var isPlayable: Bool { track?.isDownloaded ?? true }
}

// Where playback started, shown as "Playing from …" in the full-screen player.
struct PlayContext {
    let name: String
    // For listening history: library, liked, playlist, recent, mix, discover, or radio.
    let source: String
    // Set for Discover lists, so the player can open the list again.
    var route: DiscoverRoute?
}

// One play of a song, recorded as listening history when it ends.
struct Listen {
    let trackID: UUID
    let youtubeID: String?
    let title: String
    let artist: String?
    let duration: TimeInterval
    // Where it was played from: library, liked, playlist, recent, mix, discover, radio, or queue.
    let source: String
    let startedAt = Date()
    var seconds: TimeInterval = 0
    var finished = false
}

// Shuffle, repeat, and the last song and position, kept across launches.
private enum Saved {
    static let shuffle = "player.shuffle"
    static let repeatMode = "player.repeatMode"
    static let trackID = "player.lastTrackID"
    static let time = "player.lastTime"
}

@MainActor
final class LocalPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: PlayItem?
    // The current saved song, for marking it in library lists.
    @Published private(set) var trackID: UUID?
    @Published private(set) var context: PlayContext?
    @Published private(set) var title = ""
    @Published private(set) var artist: String?
    @Published private(set) var isPlaying = false
    // A streamed song is still buffering.
    @Published private(set) var isLoading = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode = RepeatMode.off
    @Published private(set) var hasNext = false
    @Published var errorMessage: String?

    // Songs added with "Play next" or "Add to queue". They play before the rest of the list.
    @Published private(set) var upNext: [PlayItem] = []
    // The list playback started from, and the order it plays in (shuffled or not).
    @Published private(set) var queue: [PlayItem] = []
    @Published private(set) var position = 0
    private var source: [PlayItem] = []
    private var playingFromUpNext = false
    private var nowPlayingArtwork: MPMediaItemArtwork?
    var onListen: ((Listen) -> Void)?
    private var listen: Listen?
    // Saved songs play from their file; streamed songs use AVPlayer.
    private var audio: AVAudioPlayer?
    private var stream: AVPlayer?
    private var streamStatus: NSKeyValueObservation?
    private var streamEnd: NSObjectProtocol?
    // Bumped whenever a new song opens, so late stream callbacks for an old song are ignored.
    private var openGeneration = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var commands: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        shuffle = defaults.bool(forKey: Saved.shuffle)
        repeatMode = defaults.string(forKey: Saved.repeatMode).flatMap { RepeatMode(rawValue: $0) } ?? .off
        configureCommands()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type, options: options)
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let streamEnd { NotificationCenter.default.removeObserver(streamEnd) }
        commands.forEach { $0.0.removeTarget($0.1) }
    }

    // Play an item, queueing the rest of the list it was picked from.
    func play(_ item: PlayItem, in list: [PlayItem], context: PlayContext) {
        if current?.id == item.id {
            play()
            return
        }
        self.context = context
        source = list
        queue = shuffle ? [item] + list.filter { $0.id != item.id }.shuffled() : list
        position = queue.firstIndex { $0.id == item.id } ?? 0
        playingFromUpNext = false
        if open(item) { play() }
    }

    var savedTrackID: UUID? {
        UserDefaults.standard.string(forKey: Saved.trackID).flatMap { UUID(uuidString: $0) }
    }

    // Load the last song paused at its saved position, without starting playback.
    func restore(_ track: Track, in list: [Track]) {
        guard current == nil else { return }
        let items = list.map(PlayItem.track)
        context = PlayContext(name: "Library", source: "library")
        source = items
        queue = shuffle ? [.track(track)] + items.filter { $0.id != track.id.uuidString }.shuffled() : items
        position = queue.firstIndex { $0.id == track.id.uuidString } ?? 0
        guard open(.track(track)), let audio else { return }
        audio.currentTime = min(UserDefaults.standard.double(forKey: Saved.time), audio.duration)
        elapsed = audio.currentTime
        updateNowPlaying()
    }

    func next() {
        if !upNext.isEmpty {
            playUpNext()
        } else if let index = neighbor(1) {
            move(to: index)
        }
    }

    // Restart the song when more than a few seconds in, like Spotify; otherwise go back one.
    // From a queued song, go back to the list song that played before it.
    func previous() {
        if currentTime <= 3 {
            if playingFromUpNext && queue.indices.contains(position) {
                move(to: position)
                return
            }
            if let index = neighbor(-1) {
                move(to: index)
                return
            }
        }
        seek(to: 0)
    }

    // Nothing playing yet: start the song on its own instead of queueing it.
    func playNext(_ track: Track) {
        guard track.isDownloaded else { return }
        if current == nil {
            play(.track(track), in: [.track(track)], context: PlayContext(name: "Queue", source: "queue"))
        } else {
            upNext.insert(.track(track), at: 0)
            updateNowPlaying()
        }
    }

    func addToQueue(_ track: Track) {
        guard track.isDownloaded else { return }
        if current == nil {
            play(.track(track), in: [.track(track)], context: PlayContext(name: "Queue", source: "queue"))
        } else {
            upNext.append(.track(track))
            updateNowPlaying()
        }
    }

    // The list songs still to come, after the current one.
    var upcoming: [PlayItem] {
        guard position + 1 < queue.count else { return [] }
        return Array(queue[(position + 1)...])
    }

    func moveUpNext(from offsets: IndexSet, to destination: Int) {
        upNext.move(fromOffsets: offsets, toOffset: destination)
    }

    func removeUpNext(at offsets: IndexSet) {
        upNext.remove(atOffsets: offsets)
        updateNowPlaying()
    }

    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        guard queue.indices.contains(position) else { return }
        var rest = upcoming
        rest.move(fromOffsets: offsets, toOffset: destination)
        queue = Array(queue[...position]) + rest
        if !shuffle { source = queue }
    }

    func removeUpcoming(at offsets: IndexSet) {
        guard queue.indices.contains(position) else { return }
        let removed = Set(offsets.map { upcoming[$0].id })
        var rest = upcoming
        rest.remove(atOffsets: offsets)
        queue = Array(queue[...position]) + rest
        source.removeAll { removed.contains($0.id) }
        updateNowPlaying()
    }

    func toggleShuffle() {
        shuffle.toggle()
        UserDefaults.standard.set(shuffle, forKey: Saved.shuffle)
        guard queue.indices.contains(position) else { return }
        let playing = queue[position]
        queue = shuffle ? [playing] + source.filter { $0.id != playing.id }.shuffled() : source
        position = queue.firstIndex { $0.id == playing.id } ?? 0
        updateNowPlaying()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: Saved.repeatMode)
        updateNowPlaying()
    }

    // Drop a track that is about to be deleted, so the queue never touches a deleted model.
    func forget(_ track: Track) {
        if trackID == track.id {
            stop()
            return
        }
        let id = track.id.uuidString
        if let index = queue.firstIndex(where: { $0.id == id }), index < position {
            position -= 1
        }
        queue.removeAll { $0.id == id }
        source.removeAll { $0.id == id }
        upNext.removeAll { $0.id == id }
        updateNowPlaying()
    }

    private func playUpNext() {
        let item = upNext.removeFirst()
        playingFromUpNext = true
        if open(item) { play() }
    }

    private func beginListen(_ item: PlayItem) {
        listen = Listen(
            // Streamed songs aren't in the library, so they get an ID of their own.
            trackID: item.track?.id ?? UUID(),
            youtubeID: item.youtubeID,
            title: item.title,
            artist: item.artist,
            duration: duration,
            source: playingFromUpNext ? "queue" : context?.source ?? "library"
        )
    }

    private func endListen(finished: Bool) {
        guard var listen else { return }
        self.listen = nil
        listen.finished = finished
        // Songs that were only loaded or barely started aren't history.
        if finished || listen.seconds >= 5 { onListen?(listen) }
    }

    // The next playable item in the given direction, wrapping only with repeat all.
    private func neighbor(_ step: Int) -> Int? {
        guard !queue.isEmpty else { return nil }
        var index = position
        for _ in 0..<queue.count {
            index += step
            if !queue.indices.contains(index) {
                guard repeatMode == .all else { return nil }
                index = step > 0 ? 0 : queue.count - 1
            }
            // With repeat all, a lone song loops back to itself.
            if (index != position || repeatMode == .all) && queue[index].isPlayable { return index }
        }
        return nil
    }

    // Switch songs without pausing first: deactivating the audio session between songs
    // can let iOS suspend Freeify while the screen is locked.
    private func move(to index: Int) {
        position = index
        playingFromUpNext = false
        if open(queue[index]) { play() }
    }

    private func open(_ item: PlayItem) -> Bool {
        endListen(finished: false)
        openGeneration += 1
        audio?.stop()
        audio = nil
        unloadStream()
        current = item
        trackID = item.track?.id
        title = item.title
        artist = item.artist
        elapsed = 0
        duration = 0
        isPlaying = false
        nowPlayingArtwork = nil

        switch item {
        case .track(let track):
            do {
                let player = try AVAudioPlayer(contentsOf: track.fileURL)
                player.delegate = self
                audio = player
                duration = player.duration
            } catch {
                current = nil
                trackID = nil
                errorMessage = error.localizedDescription
                updateNowPlaying()
                return false
            }
            UserDefaults.standard.set(track.id.uuidString, forKey: Saved.trackID)
            UserDefaults.standard.set(0.0, forKey: Saved.time)
            nowPlayingArtwork = Artwork.image(for: track).map { image in
                MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        case .stream(let song):
            // Streams can't be reopened offline, so they aren't remembered across launches.
            UserDefaults.standard.removeObject(forKey: Saved.trackID)
            duration = Self.seconds(from: song.duration)
            isLoading = true
            loadStream(song, generation: openGeneration)
        }
        beginListen(item)
        return true
    }

    // Resolve the stream link, then start playback if play was pressed meanwhile.
    private func loadStream(_ song: SongResult, generation: Int) {
        Task { @MainActor in
            if let url = song.artworkURL ?? song.thumbnailURL,
               let result = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: result.0),
               generation == openGeneration {
                nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                updateNowPlaying()
            }
        }
        Task { @MainActor in
            do {
                let asset = try await YouTubeSource.previewAsset(videoID: song.id)
                guard generation == openGeneration else { return }
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                stream = player
                streamStatus = item.observe(\.status) { [weak self] item, _ in
                    let status = item.status
                    let seconds = item.duration.seconds
                    let details = item.error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.openGeneration else { return }
                        if status == .readyToPlay {
                            self.isLoading = false
                            if seconds.isFinite && seconds > 0 { self.duration = seconds }
                            self.updateNowPlaying()
                        } else if status == .failed {
                            self.streamFailed(details ?? "unknown")
                        }
                    }
                }
                streamEnd = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, generation == self.openGeneration else { return }
                        self.finished(successfully: true)
                    }
                }
                if isPlaying { player.play() }
            } catch {
                guard generation == openGeneration else { return }
                streamFailed(YouTubeSource.describe(error))
            }
        }
    }

    private func streamFailed(_ details: String) {
        isLoading = false
        pause()
        errorMessage = "Couldn’t stream “\(title)”. Check your connection, or try another song.\n\nDetails: \(details)"
    }

    private func unloadStream() {
        stream?.pause()
        stream = nil
        streamStatus = nil
        if let streamEnd { NotificationCenter.default.removeObserver(streamEnd) }
        streamEnd = nil
        isLoading = false
    }

    private var currentTime: TimeInterval {
        if let audio { return audio.currentTime }
        let seconds = stream?.currentTime().seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    func play() {
        guard current != nil else { return }
        if listen == nil, let current { beginListen(current) }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if let audio {
                if audio.currentTime >= audio.duration { audio.currentTime = 0 }
                guard audio.play() else {
                    throw NSError(domain: "Freeify", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "This audio file couldn’t start playing."
                    ])
                }
            } else {
                // A stream still loading starts as soon as it's ready.
                stream?.play()
            }
            isPlaying = true
            errorMessage = nil
            startTimer()
            updateNowPlaying()
        } catch {
            isPlaying = false
            timer?.invalidate()
            updateNowPlaying()
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        resumeAfterInterruption = false
        audio?.pause()
        stream?.pause()
        isPlaying = false
        elapsed = currentTime
        if trackID != nil { UserDefaults.standard.set(elapsed, forKey: Saved.time) }
        timer?.invalidate()
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Unload the current song, e.g. when it is removed from the library.
    func stop() {
        endListen(finished: false)
        pause()
        openGeneration += 1
        audio = nil
        unloadStream()
        source = []
        queue = []
        upNext = []
        position = 0
        playingFromUpNext = false
        current = nil
        trackID = nil
        context = nil
        nowPlayingArtwork = nil
        UserDefaults.standard.removeObject(forKey: Saved.trackID)
        title = ""
        artist = nil
        elapsed = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateNowPlaying()
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        let target = min(max(time, 0), duration)
        if let audio {
            audio.currentTime = target
        } else if let stream {
            stream.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        } else {
            return
        }
        elapsed = target
        updateNowPlaying()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed = self.currentTime
                if self.isPlaying && !self.isLoading { self.listen?.seconds += 0.5 }
                if self.trackID != nil { UserDefaults.standard.set(self.elapsed, forKey: Saved.time) }
            }
        }
    }

    private func updateNowPlaying() {
        let loaded = current != nil
        hasNext = loaded && (!upNext.isEmpty || neighbor(1) != nil)
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = hasNext
        center.previousTrackCommand.isEnabled = loaded
        center.playCommand.isEnabled = loaded
        center.pauseCommand.isEnabled = loaded
        center.togglePlayPauseCommand.isEnabled = loaded
        center.changePlaybackPositionCommand.isEnabled = loaded
        guard loaded else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.play() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.togglePlayback() }
        let token = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
        commands.append((center.changePlaybackPositionCommand, token))
        updateNowPlaying()
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (LocalPlayer) -> Void) {
        let token = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
            return .success
        }
        commands.append((command, token))
    }

    private func handleInterruption(type: UInt?, options: UInt) {
        guard let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch interruption {
        case .began:
            resumeAfterInterruption = isPlaying
            audio?.pause()
            stream?.pause()
            isPlaying = false
            timer?.invalidate()
            updateNowPlaying()
        case .ended:
            let shouldResume = resumeAfterInterruption
                && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            resumeAfterInterruption = false
            if shouldResume { play() }
        @unknown default:
            break
        }
    }

    // A song reached its end: repeat it, or move to the next one.
    private func finished(successfully: Bool) {
        if !successfully {
            pause()
            errorMessage = "Playback ended unexpectedly."
        } else if repeatMode == .one {
            endListen(finished: true)
            if let current { beginListen(current) }
            seek(to: 0)
            play()
        } else if !upNext.isEmpty {
            endListen(finished: true)
            playUpNext()
        } else if let index = neighbor(1) {
            endListen(finished: true)
            move(to: index)
        } else {
            endListen(finished: true)
            pause()
            seek(to: 0)
        }
    }

    // "3:24" or "1:02:03" to seconds; 0 when unknown.
    private static func seconds(from text: String?) -> TimeInterval {
        guard let text else { return 0 }
        return text.split(separator: ":").reduce(0) { total, part in total * 60 + (Double(part) ?? 0) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            self.finished(successfully: flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            self.pause()
            self.errorMessage = error?.localizedDescription ?? "This audio file couldn’t be decoded."
        }
    }
}
