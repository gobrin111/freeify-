import AVFAudio
import Combine
import Foundation
import MediaPlayer

@MainActor
final class LocalPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var trackID: UUID?
    @Published private(set) var title = ""
    @Published private(set) var artist: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?

    private var audio: AVAudioPlayer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var commands: [(MPRemoteCommand, Any)] = []
    private var resumeAfterInterruption = false

    override init() {
        super.init()
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
        commands.forEach { $0.0.removeTarget($0.1) }
    }

    func load(_ track: Track) {
        if trackID == track.id {
            play()
            return
        }
        do {
            let next = try AVAudioPlayer(contentsOf: track.fileURL)
            audio?.stop()
            audio = next
            next.delegate = self
            trackID = track.id
            title = track.title
            artist = track.artist
            duration = next.duration
            elapsed = 0
            isPlaying = false
            play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func play() {
        guard let audio else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if audio.currentTime >= audio.duration { audio.currentTime = 0 }
            guard audio.play() else {
                throw NSError(domain: "Freeify", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "This audio file couldn’t start playing."
                ])
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
        isPlaying = false
        elapsed = audio?.currentTime ?? elapsed
        timer?.invalidate()
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Unload the current track, e.g. when it is removed from the library.
    func stop() {
        pause()
        audio = nil
        trackID = nil
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
        guard let audio else { return }
        audio.currentTime = min(max(time, 0), duration)
        elapsed = audio.currentTime
        updateNowPlaying()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsed = self.audio?.currentTime ?? 0
            }
        }
    }

    private func updateNowPlaying() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = audio != nil
        center.pauseCommand.isEnabled = audio != nil
        center.togglePlayPauseCommand.isEnabled = audio != nil
        center.changePlaybackPositionCommand.isEnabled = audio != nil
        guard audio != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        register(center.playCommand) { $0.play() }
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

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            self.pause()
            self.seek(to: 0)
            if !flag { self.errorMessage = "Playback ended unexpectedly." }
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
