import Foundation

/// Every usage event Pregame can send, with exactly the fields it carries.
/// docs/privacy.md lists the same, and TelemetryTests keeps the two in step.
/// Fields are counts, rounded durations and fixed words: never a title, a file
/// name or a path.
enum TelemetryEvent: Equatable {
    /// Once per launch.
    case appLaunched
    /// A new, empty Mix gets its first Tracks.
    case mixCreated
    /// Tracks added to a Mix: how many, nothing about them.
    case tracksAdded(count: Int)
    /// Auto-pick chose the Tracks for a Mix.
    case autoPickUsed
    /// A Harmonize run was applied to a Mix.
    case harmonizeRun
    /// A Mix finished exporting: the formats, how long the Mix is and how long
    /// the export took.
    case exportFinished(format: ExportFormat, mixSeconds: Double, exportSeconds: Double)
    /// One Track was analysed: how long that took, and how long the Track is.
    case trackAnalysed(seconds: Double, trackSeconds: Double)

    enum ExportFormat: String, CaseIterable {
        case wav, mp3
        case wavAndMP3 = "wav+mp3"

        init?(wav: Bool, mp3: Bool) {
            switch (wav, mp3) {
            case (true, true): self = .wavAndMP3
            case (true, false): self = .wav
            case (false, true): self = .mp3
            case (false, false): return nil
            }
        }
    }

    /// One of each, for the docs check.
    static let examples: [TelemetryEvent] = [
        .appLaunched, .mixCreated, .tracksAdded(count: 1), .autoPickUsed, .harmonizeRun,
        .exportFinished(format: .wav, mixSeconds: 1, exportSeconds: 1),
        .trackAnalysed(seconds: 1, trackSeconds: 1),
    ]

    /// The signal type in TelemetryDeck.
    var name: String {
        switch self {
        case .appLaunched: "App.launched"
        case .mixCreated: "Mix.created"
        case .tracksAdded: "Tracks.added"
        case .autoPickUsed: "AutoPick.used"
        case .harmonizeRun: "Harmonize.run"
        case .exportFinished: "Export.finished"
        case .trackAnalysed: "Track.analysed"
        }
    }

    /// The event's own fields, on top of the ones every event carries.
    var fields: [String: String] {
        switch self {
        case .appLaunched, .mixCreated, .autoPickUsed, .harmonizeRun: [:]
        case let .tracksAdded(count): ["count": "\(count)"]
        case let .exportFinished(format, mixSeconds, exportSeconds):
            ["format": format.rawValue,
             "mixMinutes": "\(Int((mixSeconds / 60).rounded()))",
             "exportSeconds": "\(Int(exportSeconds.rounded()))"]
        case let .trackAnalysed(seconds, trackSeconds):
            ["analysisSeconds": String(format: "%.1f", Self.tenths(seconds)),
             "trackMinutes": "\(Int((trackSeconds / 60).rounded()))"]
        }
    }

    /// The number TelemetryDeck can average or sum, if the event has one.
    var value: Double? {
        switch self {
        case .appLaunched, .mixCreated, .autoPickUsed, .harmonizeRun: nil
        case let .tracksAdded(count): Double(count)
        case let .exportFinished(_, _, exportSeconds): exportSeconds.rounded()
        case let .trackAnalysed(seconds, _): Self.tenths(seconds)
        }
    }

    private static func tenths(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
