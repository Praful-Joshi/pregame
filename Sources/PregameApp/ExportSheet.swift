import AppKit
import PregameCore
import SwiftUI

struct ExportSheet: View {
    @ObservedObject var document: MixDocument
    let windowTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var wav = true
    @State private var mp3 = true
    @State private var scope = 0          // 0 = full set, 1 = range, 2 = transitions only
    @State private var from = 1
    @State private var to = 2
    @State private var lead = 8
    @State private var progress: Double?
    @State private var status = ""
    @State private var result: ExportResult?
    @State private var error: String?

    private var count: Int { document.project.included.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Export Mix").font(.title2.bold())
            Form {
                LabeledContent("Formats") {
                    HStack {
                        Toggle("WAV (24-bit, 48 kHz)", isOn: $wav)
                        Toggle("MP3 (320 kbps)", isOn: $mp3)
                    }
                }
                Picker("What", selection: $scope) {
                    Text("Full set").tag(0)
                    Text("Range of tracks").tag(1)
                    Text("Transitions only").tag(2)
                }
                .pickerStyle(.segmented)
                if scope == 1 {
                    LabeledContent("Tracks") {
                        HStack {
                            Stepper("from \(from)", value: $from, in: 1...max(1, to - 1))
                            Stepper("to \(to)", value: $to, in: (from + 1)...max(from + 1, count))
                        }
                    }
                }
                if scope == 2 {
                    Picker("Bars either side", selection: $lead) {
                        ForEach([4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
                    }
                }
                LabeledContent("Estimated size") { Text(sizeText).monospacedDigit() }
            }
            .formStyle(.grouped)

            if let progress {
                ProgressView(value: progress) { Text(status).font(.caption) }
            }
            if let error { Text(error).foregroundStyle(Ink.error).font(.callout) }
            if let result {
                Text("Exported \(clock(result.seconds)) to \(result.folder.path)").font(.callout)
            }
            HStack {
                Spacer()
                if let result {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.folder]) }
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(progress != nil)
                    Button("Export…") { start() }.keyboardShortcut(.defaultAction)
                        .disabled(progress != nil || !(wav || mp3) || notEnoughSpace)
                }
            }
        }
        .padding(Space.xxl)
        .frame(width: 520)
        .onAppear { to = max(2, count) }
    }

    private var options: ExportOptions {
        var o = ExportOptions()
        o.wav = wav
        o.mp3 = mp3
        o.transitionsOnly = scope == 2
        o.leadBars = lead
        if scope == 1 { o.subrange = (from - 1)...(to - 1) }
        return o
    }

    private var estimatedSeconds: Double {
        guard let (_, layout) = document.project.mixLayout(subrange: options.subrange) else { return 0 }
        if scope == 2 {
            return layout.windows.reduce(0) { $0 + Double($1.length) / mixSampleRate } + Double(layout.windows.count) * (1 + Double(2 * lead) * 2)
        }
        return Double(layout.length) / mixSampleRate
    }

    private var estimatedBytes: Double {
        let s = estimatedSeconds
        return (wav ? s * mixSampleRate * 6 : 0) + (mp3 ? s * 40_000 : 0)
    }

    private var freeBytes: Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    private var notEnoughSpace: Bool { estimatedBytes > freeBytes - 500_000_000 }

    private var sizeText: String {
        let f = ByteCountFormatter()
        return "\(clock(estimatedSeconds)) · \(f.string(fromByteCount: Int64(estimatedBytes)))"
            + (notEnoughSpace ? "  (not enough free space)" : "  (\(f.string(fromByteCount: Int64(freeBytes))) free)")
    }

    private func clock(_ s: Double) -> String {
        let t = Int(s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    private func start() {
        let panel = NSSavePanel()
        let base = windowTitle.replacingOccurrences(of: ".hmix", with: "")
        panel.nameFieldStringValue = scope == 2 ? "\(base) – transitions" : base
        panel.message = "Pregame creates a folder with the mix, tracklist and cue sheet."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let project = document.project
        let opts = options
        progress = 0
        error = nil
        let started = Date()
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result {
                    try project.exportMix(to: folder, options: opts) { p, s in
                        Task { @MainActor in
                            progress = p
                            status = s
                        }
                    }
                }
            }.value
            switch outcome {
            case let .success(r):
                result = r
                progress = nil
                if let format = TelemetryEvent.ExportFormat(wav: opts.wav, mp3: opts.mp3) {
                    Telemetry.shared.record(.exportFinished(format: format, mixSeconds: r.seconds,
                                                            exportSeconds: Date().timeIntervalSince(started)))
                }
            case let .failure(e): error = (e as? LocalizedError)?.errorDescription ?? "\(e)"; progress = nil
            }
        }
    }
}
