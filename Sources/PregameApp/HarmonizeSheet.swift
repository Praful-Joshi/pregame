import PregameCore
import SwiftUI

struct HarmonizeSheet: View {
    @ObservedObject var document: MixDocument
    @Environment(\.undoManager) private var undo
    @Environment(\.dismiss) private var dismiss
    @State private var settings = HarmonizeSettings()
    @State private var preview: MixProject?
    @State private var result: SolveResult?
    @State private var working = false
    @State private var error: String?
    @State private var open: Set<String> = []

    /// A form row with an ⓘ that slides open a short explanation under it.
    private func explained(_ key: String, _ text: String, @ViewBuilder _ control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                control()
                Button {
                    withAnimation(Motion.snap) {
                        if open.contains(key) { open.remove(key) } else { open.insert(key) }
                    }
                } label: {
                    Image(systemName: open.contains(key) ? "info.circle.fill" : "info.circle")
                        .foregroundStyle(open.contains(key) ? Ink.accent : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help("What does this do?")
            }
            if open.contains(key) {
                Text(text)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    static let help: [String: String] = [
        "mode": "How adventurous the key changes are. Fuzzy plays it safe: same key, one step around the Camelot wheel, or the relative major/minor. Mood also welcomes moves that change the feel, like +2 energy boosts, mood changes (minor ↔ major) and jaws mixes, so the set can lift and turn. Clashing keys are avoided either way.",
        "slider": "What matters more when ordering. 0 = only how well the keys fit, 100 = only how close the tempos are, 50 = both equally. Slide toward BPM if tempo jumps sound worse to you than key changes.",
        "tolerance": "Tempo gaps up to this many BPM count as free (tracks get synced). Each BPM beyond it adds cost. Lower keeps tempos tight but leaves fewer good orders; higher gives the key more say.",
        "direction": "Any: tempo may rise or fall. Ascending: drops in tempo (beyond the tolerance) are penalised, so the set builds. Descending: rises are penalised, for winding down.",
        "halfDouble": "Counts a track at half or double tempo as a match, e.g. 70 → 140 BPM. Useful for trap, hip-hop and drum & bass, where a song can be mixed at half or double time.",
        "lock": "Pins one song to open (or close) the set; everything else is ordered around it. Separately, locked transitions (🔒 in the playlist) always keep their two songs together.",
        "budget": "Up to 15 songs the exact best order is found instantly. Bigger sets are solved by searching, which stops at this time. More time can find a slightly better order.",
        "seed": "Big sets often have several equally good orders. The same seed always gives the same result. Shuffle to hear an alternative of similar quality.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Harmonize").font(.title2.bold())
            Form {
                explained("mode", Self.help["mode"]!) {
                    Picker("Key mixing", selection: $settings.mode) {
                        Text("Fuzzy").tag(MixMode.fuzzy)
                        Text("Mood").tag(MixMode.mood)
                    }
                    .pickerStyle(.segmented)
                }
                explained("slider", Self.help["slider"]!) {
                    LabeledContent("Key ↔ BPM") {
                        HStack {
                            Text("Key").font(.caption)
                            Slider(value: $settings.keyBpmSlider, in: 0...100, step: 5)
                            Text("BPM").font(.caption)
                            Text("\(Int(settings.keyBpmSlider))").monospacedDigit().frame(width: 28)
                        }
                    }
                }
                explained("tolerance", Self.help["tolerance"]!) {
                    LabeledContent("BPM tolerance") {
                        Stepper(value: $settings.bpmTolerance, in: 0...20, step: 0.5) {
                            Text(String(format: "%g BPM", settings.bpmTolerance)).monospacedDigit()
                        }
                    }
                }
                explained("direction", Self.help["direction"]!) {
                    Picker("Tempo direction", selection: $settings.tempoDirection) {
                        ForEach(TempoDirection.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                explained("halfDouble", Self.help["halfDouble"]!) {
                    Toggle("Treat half/double tempo as a match", isOn: $settings.halfDouble)
                }
                explained("lockFirst", Self.help["lock"]!) {
                    Picker("Lock first", selection: $settings.lockFirst) { lockOptions }
                }
                explained("lockLast", Self.help["lock"]!) {
                    Picker("Lock last", selection: $settings.lockLast) { lockOptions }
                }
                explained("budget", Self.help["budget"]!) {
                    LabeledContent("Time budget (large sets)") {
                        HStack {
                            Slider(value: $settings.timeBudget, in: 2...60, step: 1)
                            Text("\(Int(settings.timeBudget)) s").monospacedDigit().frame(width: 36)
                        }
                    }
                }
                explained("seed", Self.help["seed"]!) {
                    LabeledContent("Seed") {
                        HStack {
                            Text("\(settings.seed)").monospacedDigit()
                            Button("Shuffle for alternative") {
                                settings.seed = UInt64.random(in: 1...1_000_000)
                                run()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: settings) { preview = nil }

            if let error {
                Text(error).foregroundStyle(Ink.error).font(.callout)
            }
            comparison

            HStack {
                if working { ProgressView().controlSize(.small); Text("Ordering…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Preview") { run() }.disabled(working)
                Button("Apply") {
                    if let preview { apply(preview) } else { run(thenApply: true) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
        }
        .padding(Space.xxl)
        .frame(width: 560)
        .onAppear { settings = document.project.settings }
    }

    @ViewBuilder private var lockOptions: some View {
        Text("— not locked —").tag(UUID?.none)
        ForEach(document.project.included) { t in Text(t.displayName).lineLimit(1).tag(UUID?.some(t.id)) }
    }

    @ViewBuilder private var comparison: some View {
        let now = document.project.summary(settings: settings)
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
            GridRow {
                Text("")
                Text("Cost").bold(); Text("🟩").bold(); Text("🟨").bold(); Text("🟦").bold(); Text("🟥").bold()
                Text("Avg gap").bold()
            }
            summaryRow("Current order", now)
            if let preview {
                summaryRow("New order", preview.summary())
            }
        }
        .font(.callout.monospacedDigit())
        if let result {
            Text("\(result.method) solver" + (result.method == "heuristic" ? " · \(result.rounds) rounds" : "")
                 + (result.hitTimeLimit ? " · stopped at the time budget, raise it for a better order" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ title: String, _ s: MixSummary) -> some View {
        GridRow {
            Text(title)
            Text(String(format: "%.1f", s.totalCost))
            Text("\(s.green)"); Text("\(s.yellow)"); Text("\(s.blue)"); Text("\(s.red)")
            Text(String(format: "%.1f", s.avgBpmGap))
        }
    }

    private func run(thenApply: Bool = false) {
        error = nil
        working = true
        let project = document.project
        let s = settings
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try project.harmonized(with: s) }
            }.value
            working = false
            switch outcome {
            case let .success((p, r)):
                preview = p
                result = r
                if thenApply { apply(p) }
            case let .failure(e):
                error = e.localizedDescription
            }
        }
    }

    private func apply(_ p: MixProject) {
        document.perform("Harmonize", undo: undo) { $0 = p }
        Telemetry.shared.record(.harmonizeRun)
        dismiss()
    }
}
