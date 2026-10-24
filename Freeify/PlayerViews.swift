import SwiftUI

// Playback controls pinned to the bottom of every library screen.
struct PlayerBar: View {
    @EnvironmentObject private var player: LocalPlayer

    var body: some View {
        if player.trackID != nil {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).font(.headline).lineLimit(1)
                    Text(player.artist ?? "Saved in Freeify").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PlaybackPosition()
                PlaybackButtons(playSize: 44)
            }
            .padding()
            .background(.regularMaterial)
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
