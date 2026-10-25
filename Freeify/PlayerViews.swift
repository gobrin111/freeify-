import SwiftData
import SwiftUI

// The mini player above the tab bar on every tab. Tap the song to open Now Playing;
// the buttons only control playback.
struct PlayerBar: View {
    @EnvironmentObject private var player: LocalPlayer
    @State private var showingPlayer = false

    var body: some View {
        if let item = player.current {
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.m) {
                    PlayItemArtwork(item: item, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Text(player.artist ?? (item.track == nil ? "Streaming" : "Saved in Freeify"))
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingPlayer = true }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens Now Playing")
                RoundPlayButton(size: 40)
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .foregroundStyle(player.hasNext ? Palette.textPrimary : Palette.textMuted)
                        .frame(width: Spacing.target, height: Spacing.target)
                }
                .disabled(!player.hasNext)
                .accessibilityLabel("Next")
                // Stops the music and clears the queue, hiding the bar.
                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Spacing.target, height: Spacing.target)
                }
                .accessibilityLabel("Close player")
                .accessibilityHint("Stops the music")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .frame(minHeight: 64)
            .background(Palette.raised)
            .overlay(alignment: .top) { ProgressStrip() }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.borderSubtle).frame(height: 1).accessibilityHidden(true)
            }
            .sheet(isPresented: $showingPlayer) {
                NowPlayingView()
            }
        }
    }
}

// The mini player's 2-point cyan progress line. Informational only, not a scrub control.
private struct ProgressStrip: View {
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        GeometryReader { geometry in
            let fraction = player.duration > 0 ? min(player.elapsed / player.duration, 1) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.borderSubtle)
                Rectangle().fill(Palette.activity).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// Play/pause in the warm action color. Small sizes use a circle; Now Playing uses the octagon.
struct RoundPlayButton: View {
    let size: CGFloat
    var octagon = false
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        Button {
            player.togglePlayback()
        } label: {
            ZStack {
                if octagon {
                    PlayHousing().fill(Palette.action)
                } else {
                    Circle().fill(Palette.action)
                }
                if player.isLoading && player.isPlaying {
                    ProgressView().tint(Palette.inkOnAccent)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.38, weight: .bold))
                        .foregroundStyle(Palette.inkOnAccent)
                }
            }
            .frame(width: size, height: size)
            .frame(minWidth: Spacing.target, minHeight: Spacing.target)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
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
                ArtworkPlaceholder(size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
        }
    }
}

// Now Playing: where it's playing from, framed artwork, like or download, seek bar,
// controls, and the queue.
struct NowPlayingView: View {
    @EnvironmentObject private var player: LocalPlayer
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var tracks: [Track]
    @State private var showingQueue = false

    var body: some View {
        VStack(spacing: 0) {
            header
            // Large text scrolls; otherwise the artwork shrinks before the controls do.
            if typeSize.isAccessibilitySize {
                ScrollView { content(artworkSide: 200) }
            } else {
                content(artworkSide: nil)
            }
        }
        .padding(.horizontal, Spacing.gutter)
        .background(Palette.canvas)
        .presentationBackground(Palette.canvas)
        .onChange(of: player.current?.id) { _, id in
            if id == nil { dismiss() }
        }
        .sheet(isPresented: $showingQueue) {
            QueueView()
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: Spacing.target, height: Spacing.target)
            }
            .accessibilityLabel("Close Now Playing")
            Spacer()
            Text("Now playing")
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Menu {
                if let item = player.current { moreItems(item) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: Spacing.target, height: Spacing.target)
            }
            .accessibilityLabel("More")
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.top, Spacing.s)
    }

    @ViewBuilder
    private func content(artworkSide: CGFloat?) -> some View {
        VStack(spacing: Spacing.xl) {
            if let context = player.context {
                playingFrom(context)
            }
            if let item = player.current {
                if let artworkSide {
                    framedArtwork(item, side: artworkSide)
                } else {
                    GeometryReader { geometry in
                        let side = max(120, min(geometry.size.width, geometry.size.height) - Spacing.l)
                        framedArtwork(item, side: side)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: 380)
                }
                HStack(alignment: .top, spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(player.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                        Text(player.artist ?? (item.track == nil ? "Streaming" : "Saved in Freeify"))
                            .font(.body)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    likeOrDownload(item)
                }
            }
            PlaybackPosition()
            PlaybackButtons()
            HStack {
                Spacer()
                Button {
                    showingQueue = true
                } label: {
                    GlyphView(path: ThemeGlyph.queue, size: 24)
                        .foregroundStyle(showingQueue ? Palette.activity : Palette.textPrimary)
                        .frame(width: Spacing.target, height: Spacing.target)
                }
                .accessibilityLabel("Queue")
            }
        }
        .padding(.vertical, Spacing.l)
    }

    private func framedArtwork(_ item: PlayItem, side: CGFloat) -> some View {
        PlayItemArtwork(item: item, size: side)
            .overlay { ArmorBrackets(isPlaying: player.isPlaying) }
            .padding(6)
    }

    // "Playing from" a list, which opens again when tapped.
    private func playingFrom(_ context: PlayContext) -> some View {
        Button {
            guard let route = context.route else { return }
            dismiss()
            store.show(route)
        } label: {
            HStack(spacing: Spacing.s) {
                HairSlash(height: 14)
                Text("Playing from")
                    .foregroundStyle(Palette.textSecondary)
                Text(context.name)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if context.route != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: Spacing.target)
        }
        .disabled(context.route == nil)
        .accessibilityHint(context.route == nil ? "" : "Opens this list")
    }

    @ViewBuilder
    private func moreItems(_ item: PlayItem) -> some View {
        if case .track(let track) = item {
            Button {
                store.toggleLike(track, in: modelContext)
            } label: {
                Label(track.likedAt == nil ? "Like" : "Unlike", systemImage: track.likedAt == nil ? "heart" : "heart.slash")
            }
        }
        Button {
            showingQueue = true
        } label: {
            Label("Queue", systemImage: "list.bullet")
        }
        if let route = player.context?.route {
            Button {
                dismiss()
                store.show(route)
            } label: {
                Label("Go to \(player.context?.name ?? "List")", systemImage: "arrow.up.forward")
            }
        }
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
                    .foregroundStyle(track.likedAt == nil ? Palette.textSecondary : Palette.hair)
                    .frame(width: Spacing.target, height: Spacing.target)
            }
            .accessibilityLabel(track.likedAt == nil ? "Like" : "Unlike")
        case .stream(let song):
            if tracks.contains(where: { $0.youtubeID == song.id }) {
                StatusChip(label: "Saved", systemImage: "checkmark", kind: .saved)
            } else if store.downloadingSongID == song.id {
                StatusChip(
                    label: store.downloadProgress.map { "\(Int($0 * 100))%" } ?? "Preparing…",
                    systemImage: "arrow.down.circle",
                    kind: .downloading
                )
            } else {
                Button {
                    store.download(song, in: modelContext)
                } label: {
                    GlyphView(path: ThemeGlyph.download, size: 24)
                        .foregroundStyle(store.isDownloading ? Palette.textMuted : Palette.textPrimary)
                        .frame(width: Spacing.target, height: Spacing.target)
                }
                .disabled(store.isDownloading)
                .accessibilityLabel("Download")
            }
        }
    }
}

// The seek slider with elapsed and remaining time. The slider is the standard, adjustable control.
struct PlaybackPosition: View {
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Slider(
                value: Binding(get: { player.elapsed }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 0.01)
            )
            .tint(Palette.activity)
            .frame(minHeight: Spacing.target)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(timeLabel(player.elapsed)) of \(timeLabel(player.duration))")
            HStack {
                Text(timeLabel(player.elapsed))
                Spacer()
                Text("-" + timeLabel(max(player.duration - player.elapsed, 0)))
            }
            .font(.footnote.weight(.medium).monospacedDigit())
            .foregroundStyle(Palette.textSecondary)
            .accessibilityHidden(true)
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// Shuffle · previous · octagonal play/pause · next · repeat.
struct PlaybackButtons: View {
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        HStack {
            toggle(systemImage: "shuffle", isOn: player.shuffle, label: player.shuffle ? "Shuffle on" : "Shuffle off") {
                player.toggleShuffle()
            }
            Spacer(minLength: 0)
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: Spacing.target, height: Spacing.target)
            }
            .accessibilityLabel("Previous")
            Spacer(minLength: 0)
            RoundPlayButton(size: 72, octagon: true)
            Spacer(minLength: 0)
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundStyle(player.hasNext ? Palette.textPrimary : Palette.textMuted)
                    .frame(width: Spacing.target, height: Spacing.target)
            }
            .disabled(!player.hasNext)
            .accessibilityLabel("Next")
            Spacer(minLength: 0)
            toggle(
                systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: player.repeatMode != .off,
                label: repeatLabel
            ) {
                player.cycleRepeat()
            }
        }
        .buttonStyle(.borderless)
    }

    // Pink with a dot underneath when on, so the state isn't shown by color alone.
    private func toggle(systemImage: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.title3)
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(isOn ? 1 : 0)
            }
            .foregroundStyle(isOn ? Palette.hair : Palette.textSecondary)
            .frame(width: Spacing.target, height: Spacing.target)
        }
        .accessibilityLabel(label)
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
                if let current = player.current {
                    Section {
                        QueueRow(item: current).themedRow(current: true)
                    } header: {
                        SectionTitle(title: "Now playing").textCase(nil)
                    }
                }
                if !player.upNext.isEmpty {
                    Section {
                        // The same song can be queued twice, so rows are keyed by position.
                        ForEach(Array(player.upNext.enumerated()), id: \.offset) { _, item in
                            QueueRow(item: item).themedRow()
                        }
                        .onMove { player.moveUpNext(from: $0, to: $1) }
                        .onDelete { player.removeUpNext(at: $0) }
                    } header: {
                        SectionTitle(title: "Next in queue").textCase(nil)
                    }
                }
                let upcoming = player.upcoming
                if !upcoming.isEmpty {
                    Section {
                        ForEach(upcoming) { item in
                            QueueRow(item: item).themedRow()
                        }
                        .onMove { player.moveUpcoming(from: $0, to: $1) }
                        .onDelete { player.removeUpcoming(at: $0) }
                    } header: {
                        SectionTitle(title: "Next up").textCase(nil)
                    }
                }
            }
            .themedList()
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Palette.raised)
    }
}

private struct QueueRow: View {
    let item: PlayItem

    var body: some View {
        HStack(spacing: Spacing.m) {
            PlayItemArtwork(item: item, size: 40)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let artist = item.artist {
                    Text(artist).font(.subheadline).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
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
