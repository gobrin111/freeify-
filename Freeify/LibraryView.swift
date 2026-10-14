import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Track.addedAt, order: .reverse) private var tracks: [Track]
    @StateObject private var player = LocalPlayer()
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if tracks.isEmpty {
                    ContentUnavailableView {
                        Label("Your offline library", systemImage: "music.note.list")
                    } description: {
                        Text("Import an audio file to start listening. Your music stays on this iPhone.")
                    } actions: {
                        importButton
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(tracks) { track in
                        Button {
                            player.load(track)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: player.trackID == track.id ? "waveform" : "music.note")
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text("Available offline")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.tint)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Freeify")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    importButton
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player.trackID != nil {
                    playbackControls
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing audio…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
                switch result {
                case .success(let source):
                    importAudio(source)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Couldn’t import audio", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("Couldn’t play audio", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { player.errorMessage = nil }
            } message: {
                Text(player.errorMessage ?? "")
            }
        }
        .tint(.mint)
    }

    private var importButton: some View {
        Button {
            showingImporter = true
        } label: {
            Label("Import audio", systemImage: "plus")
        }
        .disabled(isImporting)
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).font(.headline).lineLimit(1)
                    Text("On this iPhone").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
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
        .padding()
        .background(.regularMaterial)
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func importAudio(_ source: URL) {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try AudioFiles.importFile(source)
                }.value
                let track = Track(title: imported.title, filename: imported.filename)
                let importedURL = track.fileURL
                modelContext.insert(track)
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    try? FileManager.default.removeItem(at: importedURL)
                    throw error
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
