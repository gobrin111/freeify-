import SwiftUI

// One song in a list: title, artist or download state, and a play/download icon.
struct TrackRow: View {
    let track: Track
    @EnvironmentObject private var player: LocalPlayer
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: player.trackID == track.id ? "waveform" : "music.note")
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if store.downloadingTrackID == track.id {
                    ProgressView(value: store.downloadProgress ?? 0)
                    Text(store.downloadProgress.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if !track.isDownloaded {
                    Text([track.artist, "Not downloaded"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(track.artist ?? "Saved in Freeify · Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if track.likedAt != nil {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Liked")
            }
            if store.downloadingTrackID != track.id {
                Image(systemName: track.isDownloaded ? "play.circle" : "arrow.down.circle")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 6)
    }
}
