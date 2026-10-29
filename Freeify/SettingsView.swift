import SwiftData
import SwiftUI

// Plain grouped settings showing real values: storage, and About with the Freeify logo.
struct SettingsView: View {
    @Query private var tracks: [Track]
    @Query private var playlists: [Playlist]
    @State private var storageBytes: Int64 = 0
    @State private var ranker = Ranker.loadStatus()
    @AppStorage(Ranker.enabledKey) private var learnedRanker = true
    @AppStorage(VolumeMatch.enabledKey) private var matchVolume = true

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
                    Toggle(isOn: $matchVolume) {
                        Text("Match volume").foregroundStyle(Palette.textPrimary)
                    }
                    .frame(minHeight: Spacing.target)
                    .listRowBackground(Palette.surface)
                } header: {
                    SectionTitle(title: "Playback").textCase(nil)
                } footer: {
                    Text("Turns louder songs down to the same level, using YouTube's loudness for each song. Applies from the next song.")
                        .foregroundStyle(Palette.textMuted)
                }
                recommendationsSection
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
                    // The character mark, also shown when the library or a search is empty.
                    EmptyStateMark()
                        .frame(maxWidth: .infinity)
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
            .onAppear { ranker = Ranker.loadStatus() }
        }
    }

    // What the learned ranker is doing, in plain words.
    private var recommendationsSection: some View {
        Section {
            Toggle(isOn: $learnedRanker) {
                Text("Learn from my feedback").foregroundStyle(Palette.textPrimary)
            }
            .frame(minHeight: Spacing.target)
            .listRowBackground(Palette.surface)
            value("Ranking", learnedRanker && ranker?.learned != nil ? "Learned" : "Hand-set")
            value("Feedback", ranker.map { "\($0.examples) songs, \($0.yeses) yeses" } ?? "None yet")
            if learnedRanker, let learned = ranker?.learned {
                ForEach(Array(Ranker.inputNames.enumerated()), id: \.offset) { index, name in
                    if let name {
                        let was = RankerWeights.handSet.weights[index]
                        value(name, String(format: "%.2f (was %.1f)", learned.weights[index], was))
                    }
                }
            }
        } header: {
            SectionTitle(title: "Recommendations").textCase(nil)
        } footer: {
            Text(rankerFooter).foregroundStyle(Palette.textMuted)
        }
    }

    private var rankerFooter: String {
        let rule = "Made for you mixes are ranked from what you preview, download, like, and mark Not interested. Changes apply when the mixes next refresh."
        guard let ranker else { return rule }
        if ranker.examples < Ranker.minimumExamples || ranker.yeses < Ranker.minimumYeses {
            return rule + " Learning starts after \(Ranker.minimumExamples) songs with \(Ranker.minimumYeses) yeses."
        }
        if ranker.learned == nil {
            return rule + " The learned ranking didn't beat the hand-set one on your recent feedback yet, so the hand-set one stays."
        }
        return rule + String(format: " On your recent feedback, the learned ranking puts a yes above a no %.0f%% of the time, versus %.0f%% hand-set.",
                             (ranker.learnedQuality ?? 0) * 100, (ranker.handSetQuality ?? 0) * 100)
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
