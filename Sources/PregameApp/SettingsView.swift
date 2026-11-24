import AppKit
import PregameCore
import SwiftUI

/// Settings (⌘,): audio output, storage used by stems and caches, updates, and
/// what Pregame may send (crash reports and usage data).
struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                Section {
                    OutputDevicePicker()
                } footer: {
                    Text("System Default follows macOS (Control Centre › Sound). A chosen device is remembered; when it's not connected, the default is used until it's back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Audio", systemImage: "hifispeaker") }
            StorageSettings().tabItem { Label("Storage", systemImage: "internaldrive") }
            UpdateSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 520)
    }
}

struct StorageSettings: View {
    @ObservedObject private var stems = StemController.shared
    @State private var entries: [(hash: String, entry: StemCache.Entry)] = []
    @State private var stemBytes: Int64 = 0
    @State private var cap: Int64 = StemCache.shared.capBytes
    @State private var analysisBytes: Int64 = 0
    @State private var coreMLBytes: Int64 = 0
    @State private var confirmClear = false

    private static let caps: [Int64] = [2, 5, 10, 20, 50].map { $0 * 1024 * 1024 * 1024 }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Text("Separated stems")
                        Spacer()
                        Text("\(bytes(stemBytes)) of \(bytes(cap)) · \(entries.count) songs").foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(stemBytes), total: Double(max(cap, 1)))
                        .tint(Double(stemBytes) > 0.9 * Double(cap) ? Ink.warning : Ink.accent)
                }
                Picker("Keep up to", selection: Binding(get: { cap }, set: { v in
                    cap = v; StemCache.shared.capBytes = v; reload()
                })) {
                    ForEach(Self.caps, id: \.self) { Text(bytes($0)).tag($0) }
                }
                .help("When stems take more than this, the songs used least recently are removed first. They're separated again if needed.")
                if stems.busy || stems.preparingModel {
                    HStack {
                        ProgressView(value: stems.progress).frame(width: 120)
                        Text(stems.preparingModel ? "Preparing the separation model (first time ~40 s)…"
                             : "Separating \(stems.current?.title ?? "")… \(stems.queue.count) waiting")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DisclosureGroup("Songs (\(entries.count))") {
                    ForEach(entries, id: \.hash) { e in
                        HStack {
                            Text(e.entry.title ?? e.hash.prefix(10) + "…").lineLimit(1)
                            Spacer()
                            Text(bytes(e.entry.bytes)).foregroundStyle(.secondary).monospacedDigit()
                            Button { StemCache.shared.remove(e.hash); reload() } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Remove this song's stems")
                        }
                        .font(.callout)
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear All Stems…", role: .destructive) { confirmClear = true }
                        .disabled(entries.isEmpty)
                }
            } header: {
                Text("Stems")
            } footer: {
                Text("Drums, bass and vocals are kept as AAC per song (melody is worked out from the track). About 15 MB per song.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Caches") {
                LabeledContent("Analysis (key, BPM, structure, your corrections)") { Text(bytes(analysisBytes)).foregroundStyle(.secondary) }
                HStack {
                    LabeledContent("Core ML model compilation") { Text(bytes(coreMLBytes)).foregroundStyle(.secondary) }
                    Button("Clear") { try? FileManager.default.removeItem(at: StemSeparator.coreMLCacheURL); reload() }
                        .help("Recompiled on the next separation (~40 s)")
                }
            }
            Section {
                LabeledContent("Location") {
                    Text(DataFolders.displayPath(DataFolders.applicationSupport))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(2).truncationMode(.middle)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([DataFolders.applicationSupport])
                    }
                }
            } header: {
                Text("Where it's kept")
            } footer: {
                Text("Pregame keeps its analysis, presets and stems in its own folder, apart from the rest of your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onChange(of: stems.done) { reload() }
        .confirmationDialog("Remove all separated stems?", isPresented: $confirmClear) {
            Button("Remove All", role: .destructive) { StemCache.shared.removeAll(); reload() }
        } message: {
            Text("They'll be separated again when a transition needs them (about 20 s per song).")
        }
    }

    private func reload() {
        let idx = StemCache.shared.index()
        entries = idx.map { ($0.key, $0.value) }.sorted { $0.1.lastUsed > $1.1.lastUsed }
        stemBytes = idx.values.reduce(0) { $0 + $1.bytes }
        cap = StemCache.shared.capBytes
        analysisBytes = folderSize(AnalysisCache.shared.directory)
        coreMLBytes = folderSize(StemSeparator.coreMLCacheURL)
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }

    private func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
}
