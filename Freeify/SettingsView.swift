import SwiftData
import SwiftUI

// Plain grouped settings showing real values: storage, and About with the Freeify logo.
struct SettingsView: View {
    @Query private var tracks: [Track]
    @Query private var playlists: [Playlist]
    @State private var storageBytes: Int64 = 0

    private var savedCount: Int { tracks.filter { $0.isDownloaded }.count }
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    value("Saved songs", "\(savedCount)")
                    if tracks.count > savedCount {
                        value("Not downloaded", "\(tracks.count - savedCount)")
                    }
                    value("Playlists", "\(playlists.count)")
                    value("Space used", ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                } header: {
                    SectionTitle(title: "Storage").textCase(nil)
                } footer: {
                    Text("Saved songs play without internet. Searching and new downloads need a connection.")
                        .foregroundStyle(Palette.textMuted)
                }
                Section {
                    HStack(spacing: Spacing.l) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Freeify")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Text("Version \(version)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.vertical, Spacing.s)
                    .listRowBackground(Palette.surface)
                } header: {
                    SectionTitle(title: "About").textCase(nil)
                } footer: {
                    Text("A personal music player. Search and downloads use YouTube Music unofficially and can stop working when YouTube changes.")
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Settings")
            .task(id: tracks.map { "\($0.filename)\($0.isDownloaded)" }) {
                storageBytes = AudioFiles.usedBytes()
            }
        }
    }

    private func value(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
        } label: {
            Text(label).foregroundStyle(Palette.textPrimary)
        }
        .frame(minHeight: Spacing.target)
        .listRowBackground(Palette.surface)
    }
}
