import Foundation
import SwiftData

// Milestone 6: a logistic regression that learns how to rank "Made for you" candidates from
// your own feedback, trained on the phone when the mixes refresh. Until it has enough
// feedback, and unless it beats the hand-set weights on your most recent events, mixes keep
// using the hand-set weights.

// Positions in a recommendation event's `features`. Events from before milestone 6 have
// only the first three; the rest count as 0 for them, so they train only the weights they have.
enum RankingFeature {
    static let affinity = 0          // artist affinity, -1…1
    static let seeds = 1             // seed radios that suggested it, 1…3
    static let radioPosition = 2     // 1 at the top of a radio, 0 at 50th or lower
    static let length = 3            // 0 at 4 minutes, ±1 per 2 minutes
    static let lengthMissing = 4
    static let age = 5               // years since release / 10
    static let ageMissing = 6
    static let popularity = 7        // log10(YouTube plays) − 7, so 0 at 10M
    static let popularityMissing = 8
    static let mixPosition = 9       // 0 at the top of its mix, 1 at the bottom
    static let explored = 10         // 1 for an exploration slot
    static let count = 11
}

struct RankerWeights: Codable, Equatable {
    var weights: [Double] // one per model input (every feature but `explored`)
    var bias: Double

    // Today's rules (5.4), which the learned weights start from and are kept close to.
    static let handSet = RankerWeights(weights: [1.0, 0.6, 0.4, 0, 0, 0, 0, 0, 0, 0], bias: 0)

    func logit(_ inputs: [Double]) -> Double {
        zip(weights, inputs).reduce(bias) { $0 + $1.0 * $1.1 }
    }

    // Ranking score for a candidate. Its place in the mix isn't known yet, so it counts as
    // the top for every song, which removes the "near the top gets tapped" bias.
    func score(_ features: [Double]) -> Double {
        logit(Ranker.inputs(features, ranking: true))
    }
}

// What the ranker learned at the last refresh, shown in Settings.
struct RankerStatus: Codable {
    var learned: RankerWeights? // nil until it has enough feedback and beats the hand-set weights
    var examples: Int
    var yeses: Int
    var learnedQuality: Double? // on held-back events: chance a yes ranks above a no
    var handSetQuality: Double?
    var trainedAt: Date
}

enum Ranker {
    static let inputCount = RankingFeature.count - 1
    static let minimumExamples = 200
    static let minimumYeses = 30
    static let enabledKey = "learnedRankerEnabled"

    // Plain names for Settings, by model input; nil for the "not listed" flags.
    static let inputNames: [String?] = [
        "Artist familiarity", "Suggested by several of your songs", "High in the song radio",
        "Longer songs", nil, "Older releases", nil, "Popular on YouTube", nil, "Lower in the mix"
    ]

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private static var statusURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ranker.json")
    }

    static func loadStatus() -> RankerStatus? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(RankerStatus.self, from: data)
    }

    // Retrain from all feedback and return the weights for today's mixes.
    @MainActor
    static func update(in context: ModelContext, today: Int) -> RankerWeights {
        let events = (try? context.fetch(FetchDescriptor<RecommendationEvent>(sortBy: [SortDescriptor(\.at)]))) ?? []
        // The newest examples are plenty, and keep training quick as history grows.
        let examples = Array(Self.examples(from: events, today: today).suffix(5_000))
        let yeses = examples.filter { $0.label == 1 }.count
        var status = RankerStatus(learned: nil, examples: examples.count, yeses: yeses, trainedAt: .now)
        if examples.count >= minimumExamples, yeses >= minimumYeses {
            // Test on the newest 20%, which the trial model never sees.
            let split = examples.count * 4 / 5
            let trial = train(Array(examples[..<split]))
            let test = Array(examples[split...])
            status.learnedQuality = quality(trial, on: test)
            status.handSetQuality = quality(.handSet, on: test)
            if let learned = status.learnedQuality, let handSet = status.handSetQuality, learned > handSet {
                status.learned = train(examples)
            }
        }
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: statusURL, options: .atomic)
        }
        return isEnabled ? status.learned ?? .handSet : .handSet
    }

    // Model inputs from saved features: the seed count starts at 0, and missing values are 0.
    static func inputs(_ features: [Double], ranking: Bool = false) -> [Double] {
        var inputs = (0..<inputCount).map { $0 < features.count ? features[$0] : 0 }
        inputs[RankingFeature.seeds] = max(inputs[RankingFeature.seeds] - 1, 0)
        if ranking { inputs[RankingFeature.mixPosition] = 0 }
        return inputs
    }

    struct Example {
        let inputs: [Double]
        let label: Double
        let weight: Double
    }

    // One example per time a song was shown in a mix, labeled by what you did with it before
    // it was shown again: liked or downloaded = yes; "Not interested" = no; previewed = weak
    // yes; nothing by the next refresh = weak no. Songs from today's mixes wait for tomorrow.
    static func examples(from events: [RecommendationEvent], today: Int) -> [Example] {
        struct Showing {
            let features: [Double]
            let day: Int
            var actions: Set<String> = []
        }
        var showings: [String: [Showing]] = [:]
        for event in events {
            let key = "\(event.mix)|\(event.youtubeID)"
            if event.action == "shown" {
                let day = Calendar.current.ordinality(of: .day, in: .era, for: event.at) ?? 0
                // A pull-to-refresh shows a song again the same day; that's still one showing.
                guard showings[key]?.last?.day != day else { continue }
                showings[key, default: []].append(Showing(features: event.features, day: day))
            } else if var list = showings[key], !list.isEmpty {
                list[list.count - 1].actions.insert(event.action)
                showings[key] = list
            }
        }
        return showings.values.flatMap { $0 }
            .sorted { $0.day < $1.day }
            .compactMap { showing -> Example? in
                guard showing.features.count >= 3 else { return nil }
                let actions = showing.actions
                let label: (Double, Double)
                if !actions.isDisjoint(with: ["liked", "downloaded"]) {
                    label = (1, 1)
                } else if actions.contains("dismissed") {
                    label = (0, 1)
                } else if actions.contains("previewed") {
                    label = (1, 0.5)
                } else if showing.day < today {
                    label = (0, 0.2)
                } else {
                    return nil
                }
                return Example(inputs: inputs(showing.features), label: label.0, weight: label.1)
            }
    }

    // Weighted logistic regression by gradient descent, pulled toward the hand-set weights
    // so a little feedback moves them only a little.
    static func train(_ examples: [Example], steps: Int = 400) -> RankerWeights {
        let prior = RankerWeights.handSet
        let total = examples.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return prior }
        var model = prior
        let rate = min(max(examples.reduce(0) { $0 + $1.weight * $1.label } / total, 0.01), 0.99)
        model.bias = log(rate / (1 - rate))
        let strength = 10.0 // worth about 10 examples of evidence
        let learningRate = 0.5
        for _ in 0..<steps {
            var gradient = [Double](repeating: 0, count: inputCount)
            var biasGradient = 0.0
            for example in examples {
                let error = (sigmoid(model.logit(example.inputs)) - example.label) * example.weight
                for index in 0..<inputCount { gradient[index] += error * example.inputs[index] }
                biasGradient += error
            }
            for index in 0..<inputCount {
                gradient[index] += strength * (model.weights[index] - prior.weights[index])
                model.weights[index] -= learningRate * gradient[index] / total
            }
            model.bias -= learningRate * biasGradient / total
        }
        return model
    }

    // The chance a random yes ranks above a random no (AUC); nil without both.
    static func quality(_ model: RankerWeights, on examples: [Example]) -> Double? {
        let scores = examples.map { ($0.label, model.logit(rankingInputs($0.inputs))) }
        let yes = scores.filter { $0.0 == 1 }.map { $0.1 }
        let no = scores.filter { $0.0 == 0 }.map { $0.1 }
        guard !yes.isEmpty, !no.isEmpty else { return nil }
        var wins = 0.0
        for a in yes {
            for b in no { wins += a > b ? 1 : (a == b ? 0.5 : 0) }
        }
        return wins / Double(yes.count * no.count)
    }

    private static func rankingInputs(_ inputs: [Double]) -> [Double] {
        var inputs = inputs
        inputs[RankingFeature.mixPosition] = 0
        return inputs
    }

    private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
}
