import SwiftData
import SwiftUI

// Compact controls pinned to the bottom of every tab. Tap to open the full player.
struct PlayerBar: View {
    @EnvironmentObject private var player: LocalPlayer
    @State private var showingPlayer = false

    var body: some View {
        if let item = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    PlayItemArtwork(item: item, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.artist ?? (item.track == nil ? "Streaming" : "Saved in Freeify"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        player.togglePlayback()
                    } label: {
                        if player.isLoading && player.isPlaying {
                            ProgressView()
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                        }
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .disabled(!player.hasNext)
                    .accessibilityLabel("Next")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
                .padding(.vertical, 10)
                ProgressView(value: min(player.elapsed, max(player.duration, 0.01)), total: max(player.duration, 0.01))
                    .progressViewStyle(.linear)
                    .scaleEffect(x: 1, y: 0.5)
            }
            .background(.regularMaterial)
            .contentShape(Rectangle())
            .onTapGesture { showingPlayer = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the player")
            .sheet(isPresented: $showingPlayer) {
                NowPlayingView()
            }
        }
    }
}

// Cover art for what's playing: a saved song's art, or a streamed song's (shown, not saved).
struct PlayItemArtwork: View {
    let item: PlayItem
    let size: CGFloat

    var body: some View {
        switch item {
        case .track(let track):
            ArtworkView(track: track, size: size)
        case .stream(let song):
            AsyncImage(url: size > 60 ? song.artworkURL ?? song.thumbnailURL : song.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(5, size * 0.04)))
            .accessibilityHidden(true)
        }
    }
}

// Full-screen player: where it's playing from, artwork, like or download, seek bar,
// controls, and the queue.
struct NowPlayingView: View {
    @EnvironmentObject private var player: LocalPlayer
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var tracks: [Track]
    @State private var showingQueue = false

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.secondary)
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            if let context = player.context {
                playingFrom(context)
            }
            Spacer(minLength: 0)
            if let item = player.current {
                PlayItemArtwork(item: item, size: 300)
                    .shadow(radius: 12, y: 6)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.title).font(.title2.bold()).lineLimit(2)
                        Text(player.artist ?? (item.track == nil ? "Streaming" : "Saved in Freeify"))
                            .font(.title3).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    likeOrDownload(item)
                }
            }
            PlaybackPosition()
            PlaybackButtons(playSize: 64)
            HStack {
                Spacer()
                Button {
                    showingQueue = true
                } label: {
                    Image(systemName: "list.bullet").font(.title3)
                }
                .accessibilityLabel("Queue")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom)
        .onChange(of: player.current?.id) { _, id in
            if id == nil { dismiss() }
        }
        .sheet(isPresented: $showingQueue) {
            QueueView()
        }
    }

    // "Playing from" a list, which opens again when tapped.
    private func playingFrom(_ context: PlayContext) -> some View {
        Button {
            guard let route = context.route else { return }
            dismiss()
            store.show(route)
        } label: {
            VStack(spacing: 2) {
                Text("PLAYING FROM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(context.name).lineLimit(1)
                    if context.route != nil {
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            }
        }
        .disabled(context.route == nil)
        .accessibilityHint(context.route == nil ? "" : "Opens this list")
    }

    // Saved songs can be liked; streamed songs can be downloaded.
    @ViewBuilder
    private func likeOrDownload(_ item: PlayItem) -> some View {
        switch item {
        case .track(let track):
            Button {
                store.toggleLike(track, in: modelContext)
            } label: {
                Image(systemName: track.likedAt == nil ? "heart" : "heart.fill")
                    .font(.title2)
                    .foregroundStyle(track.likedAt == nil ? Color.secondary : Color.pink)
            }
            .accessibilityLabel(track.likedAt == nil ? "Like" : "Unlike")
        case .stream(let song):
            if tracks.contains(where: { $0.youtubeID == song.id }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("In library")
            } else if store.downloadingSongID == song.id {
                ProgressView(value: store.downloadProgress ?? 0)
                    .frame(width: 44)
            } else {
                Button {
                    store.download(song, in: modelContext)
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title2)
                }
                .disabled(store.isDownloading)
                .accessibilityLabel("Download")
            }
        }
    }
}

struct PlaybackPosition: View {
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { player.elapsed }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 0.01)
            )
            .accessibilityLabel("Playback position")
            HStack {
                Text(timeLabel(player.elapsed))
                Spacer()
                Text(timeLabel(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// Shuffle · previous · play/pause · next · repeat.
struct PlaybackButtons: View {
    let playSize: CGFloat
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        HStack {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffle ? Color.mint : .secondary)
            }
            .accessibilityLabel(player.shuffle ? "Shuffle on" : "Shuffle off")
            Spacer()
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            .accessibilityLabel("Previous")
            Spacer()
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: playSize))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
            .disabled(!player.hasNext)
            .accessibilityLabel("Next")
            Spacer()
            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? .secondary : Color.mint)
            }
            .accessibilityLabel(repeatLabel)
        }
        .buttonStyle(.borderless)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }
}

// "Play Next" and "Add to Queue" for a song's long-press menu.
struct QueueMenuItems: View {
    let track: Track
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        if track.isDownloaded {
            Button {
                player.playNext(track)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                player.addToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
    }
}

// What plays next: queued songs first, then the rest of the list playback started from.
struct QueueView: View {
    @EnvironmentObject private var player: LocalPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Now Playing") {
                    QueueRow(title: player.title, artist: player.artist)
                }
                if !player.upNext.isEmpty {
                    Section("Next in Queue") {
                        // The same song can be queued twice, so rows are keyed by position.
                        ForEach(Array(player.upNext.enumerated()), id: \.offset) { _, item in
                            QueueRow(title: item.title, artist: item.artist)
                        }
                        .onMove { player.moveUpNext(from: $0, to: $1) }
                        .onDelete { player.removeUpNext(at: $0) }
                    }
                }
                let upcoming = player.upcoming
                if !upcoming.isEmpty {
                    Section("Next Up") {
                        ForEach(upcoming) { item in
                            QueueRow(title: item.title, artist: item.artist)
                        }
                        .onMove { player.moveUpcoming(from: $0, to: $1) }
                        .onDelete { player.removeUpcoming(at: $0) }
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct QueueRow: View {
    let title: String
    let artist: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).lineLimit(1)
            if let artist {
                Text(artist).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// Playback and preview errors, shown on every tab.
struct PlaybackErrorAlerts: ViewModifier {
    @EnvironmentObject private var player: LocalPlayer
    @EnvironmentObject private var preview: PreviewPlayer

    func body(content: Content) -> some View {
        content
            .alert("Couldn’t play audio", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { player.errorMessage = nil }
            } message: {
                Text(player.errorMessage ?? "")
            }
            .alert("Couldn’t preview song", isPresented: Binding(
                get: { preview.errorMessage != nil },
                set: { if !$0 { preview.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { preview.errorMessage = nil }
            } message: {
                Text(preview.errorMessage ?? "")
            }
    }
}
