import SwiftUI

// A song in a list: the row plays it, and a separate More button opens its actions, so no
// core action needs a swipe or long press. In Select mode the row is just its content.
struct TrackListRow<MenuItems: View>: View {
    let track: Track
    var isSelecting = false
    let onPlay: () -> Void
    @ViewBuilder let menu: MenuItems
    @EnvironmentObject private var player: LocalPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                TrackRow(track: track)
            } else {
                Button(action: onPlay) {
                    TrackRow(track: track).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(track.isDownloaded ? "Plays the song" : "Downloads the song")
                Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Spacing.target, height: Spacing.target)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(track.title)")
            }
        }
        .themedRow(current: player.trackID == track.id)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: player.trackID == track.id)
        .contextMenu { menu }
    }
}

// One song's content: cover, title, artist, and its state.
struct TrackRow: View {
    let track: Track
    @EnvironmentObject private var player: LocalPlayer
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isCurrent = player.trackID == track.id
        HStack(spacing: Spacing.m) {
            ArtworkView(track: track, size: Spacing.thumbnail)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(track.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                if store.downloadingTrackID == track.id {
                    StatusChip(
                        label: store.downloadProgress.map { "Downloading \(Int($0 * 100))%" } ?? "Preparing…",
                        systemImage: "arrow.down.circle",
                        kind: .downloading
                    )
                } else if !track.isDownloaded {
                    StatusChip(label: "Not downloaded", systemImage: "icloud.slash")
                } else if let videoID = track.youtubeID, store.recentlySavedID == videoID {
                    StatusChip(label: "Saved", systemImage: "checkmark", kind: .saved)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            // One quick check transition when a download completes; none with Reduce Motion.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: store.recentlySavedID)
            Spacer(minLength: Spacing.s)
            if track.likedAt != nil {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.hair)
                    .accessibilityLabel("Liked")
            }
            if isCurrent {
                PlayingIndicator(isPlaying: player.isPlaying)
            }
        }
        .padding(.vertical, Spacing.m)
        .frame(minHeight: Spacing.rowMinHeight - 2 * Spacing.m)
    }
}

// Saved cover art, or a themed placeholder when a song has none.
struct ArtworkView: View {
    let track: Track
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image = Artwork.image(for: track) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkPlaceholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

// Missing art: a music note on a dark panel, never a broken image.
struct ArtworkPlaceholder: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.38))
            .foregroundStyle(Palette.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.raised)
    }
}
