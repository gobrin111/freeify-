import SwiftUI

// One song in a list: title, artist or download state, and a play/download icon.
struct TrackRow: View {
    let track: Track
    @EnvironmentObject private var player: LocalPlayer
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(track: track, size: 44)
                .overlay {
                    if player.trackID == track.id {
                        Image(systemName: "waveform")
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .foregroundStyle(player.trackID == track.id ? Color.mint : .primary)
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

// Saved cover art, or a music note when a song has none.
struct ArtworkView: View {
    let track: Track
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Artwork.image(for: track) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(5, size * 0.04)))
        .accessibilityHidden(true)
    }
}
